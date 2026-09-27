import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/network/api_client.dart';
import 'package:family_hub/features/notices/data/notices_repository.dart';
import 'package:family_hub/features/notices/domain/notice.dart';
import 'package:family_hub/shared/providers/shared_providers.dart';

// ── Permissions ─────────────────────────────────────────────────────────────

/// What the signed-in member may do on the notice board.
final noticePermissionsProvider = Provider<NoticePermissions>(
  (ref) => NoticePermissions(
    memberId: ref.watch(currentMemberProvider.select((m) => m?.id)),
    isAdmin: ref.watch(isAdminProvider),
  ),
);

// ── Board (paged list) ──────────────────────────────────────────────────────

/// Loaded part of the notice board plus the "load more" status.
@immutable
class NoticeListState {
  const NoticeListState({required this.paged, this.isLoadingMore = false});

  static const empty = NoticeListState(paged: Paged<Notice>.empty());

  final Paged<Notice> paged;

  /// A next page is being fetched.
  final bool isLoadingMore;

  List<Notice> get items => paged.items;
  bool get hasMore => paged.hasMore;
  bool get isEmpty => paged.isEmpty;

  Notice? find(String id) {
    for (final n in paged.items) {
      if (n.id == id) return n;
    }
    return null;
  }

  NoticeListState copyWith({Paged<Notice>? paged, bool? isLoadingMore}) =>
      NoticeListState(
        paged: paged ?? this.paged,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      );

  @override
  bool operator ==(Object other) =>
      other is NoticeListState &&
      other.paged == paged &&
      other.isLoadingMore == isLoadingMore;

  @override
  int get hashCode => Object.hash(paged, isLoadingMore);
}

/// The family notice board: pinned first, then newest first, paginated.
///
/// * Resets on logout / account or family switch (watches the session).
/// * Refetches on `markChanged({DataScope.notices})`, on
///   `markChanged({DataScope.members})` (author names / avatars are resolved
///   by the server at read time, so a renamed or removed member shows up
///   correctly) and on pull-to-refresh, reloading as many notices as were
///   loaded (up to [NoticesRepository.maxPageSize]) so "load more" progress
///   and the scroll position survive a mutation.
/// * [loadMore] appends the next page. Duplicates are dropped when new
///   notices shifted the offsets in between; when notices were deleted
///   elsewhere (the server total shrank) the offsets moved the other way and
///   a notice could be skipped, so the loaded window is refetched.
class NoticeListController extends AsyncNotifier<NoticeListState> {
  /// Notices per page.
  static const int pageSize = 20;

  /// Bumped on every (re)build: results of a `loadMore` started before a
  /// rebuild are dropped.
  int _generation = 0;

  /// How many notices were loaded last time (size of the refetch window).
  int _loadedCount = 0;

  /// Session the loaded window belongs to.
  String? _sessionKey;

  @override
  Future<NoticeListState> build() async {
    final generation = ++_generation;
    final userId = ref.watch(sessionUserIdProvider);
    final familyId = ref.watch(currentFamilyProvider.select((f) => f?.id));
    ref.watch(dataRefreshProvider.select((m) => m[DataScope.notices]));
    ref.watch(dataRefreshProvider.select((m) => m[DataScope.members]));
    final repository = ref.watch(noticesRepositoryProvider);

    final sessionKey = userId == null || familyId == null
        ? null
        : '$userId|$familyId';
    if (sessionKey != _sessionKey) {
      _sessionKey = sessionKey;
      _loadedCount = 0;
    }
    if (sessionKey == null) return NoticeListState.empty;

    final limit = math.min(
      math.max(pageSize, _loadedCount),
      NoticesRepository.maxPageSize,
    );
    final paged = await repository.list(page: 1, limit: limit);
    if (generation == _generation) _loadedCount = paged.length;
    return NoticeListState(paged: paged);
  }

  /// Loads the next page. No-op while a page or a refresh is loading, or when
  /// everything is loaded. Rethrows API errors so the screen can show them;
  /// the loaded notices stay.
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null ||
        state.isLoading ||
        !current.hasMore ||
        current.isLoadingMore) {
      return;
    }
    final generation = _generation;
    state = AsyncData(current.copyWith(isLoadingMore: true));
    try {
      final next = await ref
          .read(noticesRepositoryProvider)
          .list(page: current.paged.nextPage, limit: current.paged.limit);
      if (!ref.mounted || generation != _generation) return;
      final base = state.value?.paged ?? current.paged;
      final merged = base.append(next, identity: (n) => n.id);
      _loadedCount = merged.length;
      state = AsyncData(NoticeListState(paged: merged));
      // Someone deleted notices meanwhile: page `n` now starts later than
      // expected and may have skipped one. Reload the whole window.
      if (next.total < base.total) ref.invalidateSelf();
    } catch (_) {
      if (ref.mounted && generation == _generation) {
        final latest = state.value ?? current;
        state = AsyncData(latest.copyWith(isLoadingMore: false));
      }
      rethrow;
    }
  }

  /// Puts [notice] into the loaded board (replacing the same id) in board
  /// order, so a mutation shows up instantly. The refetch triggered by
  /// `markChanged` then confirms it.
  void applyUpsert(Notice notice) {
    final current = state.value;
    if (current == null) return;
    final items = [
      for (final n in current.items)
        if (n.id != notice.id) n,
      notice,
    ]..sort(Notice.compareForBoard);
    // A new notice beyond the loaded window belongs to a later page.
    final isNew = current.find(notice.id) == null;
    if (isNew && current.hasMore && items.last.id == notice.id) return;
    _setItems(current, items);
  }

  /// Removes a notice from the loaded board.
  void applyRemove(String id) {
    final current = state.value;
    if (current == null || current.find(id) == null) return;
    _setItems(current, [
      for (final n in current.items)
        if (n.id != id) n,
    ]);
  }

  void _setItems(NoticeListState current, List<Notice> items) {
    _loadedCount = items.length;
    state = AsyncData(
      current.copyWith(paged: current.paged.copyWith(items: items)),
    );
  }
}

final noticeListProvider =
    AsyncNotifierProvider<NoticeListController, NoticeListState>(
      NoticeListController.new,
      retry: apiRetryPolicy,
    );

/// One notice by id (for the edit screen). Served from the loaded board when
/// present, else looked up on the server (the contract has no
/// `GET /notices/:id`). `NOT_FOUND` when it does not exist.
final noticeByIdProvider = FutureProvider.autoDispose.family<Notice, String>((
  ref,
  id,
) async {
  final userId = ref.watch(sessionUserIdProvider);
  if (userId == null || id.trim().isEmpty) {
    throw const ApiException(code: ApiErrorCode.notFound, statusCode: 404);
  }
  if (ref.exists(noticeListProvider)) {
    final loaded = ref.read(noticeListProvider).value?.find(id);
    if (loaded != null) return loaded;
  }
  return ref.watch(noticesRepositoryProvider).findById(id);
}, retry: apiRetryPolicy);

// ── Mutations ───────────────────────────────────────────────────────────────

/// Creates, edits, pins and deletes notices.
///
/// State = ids of notices with a mutation in flight (cards show a busy state
/// and ignore further taps). A second call for a busy notice is ignored and
/// returns `null` / `false`. After every success the loaded board is updated
/// immediately and `markChanged({DataScope.notices})` refetches every screen
/// that shows notices (board, dashboard).
class NoticesController extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    ref.watch(sessionUserIdProvider);
    return const <String>{};
  }

  NoticesRepository get _repository => ref.read(noticesRepositoryProvider);

  bool isBusy(String id) => state.contains(id);

  /// How far back [create] looks for a notice that was posted although the
  /// response was lost (generous: device and server clocks may differ).
  static const Duration uncertainPostWindow = Duration(minutes: 10);

  /// `POST /notices`.
  ///
  /// `POST` is not idempotent: after a timeout or a dropped connection the
  /// notice may exist although no response arrived, and posting again would
  /// duplicate it. In that case the newest notices are checked for the same
  /// title and text by the current member; when found it counts as posted.
  /// Otherwise the original error is rethrown (and the board refetched).
  Future<Notice> create(NoticeDraft draft) async {
    final startedAt = DateTime.now().toUtc();
    Notice notice;
    try {
      notice = await _repository.create(draft);
    } on ApiException catch (e) {
      if (!e.isNetwork) rethrow;
      final posted = await _findPosted(draft, since: startedAt);
      if (posted == null) {
        if (ref.mounted) markChanged(ref, {DataScope.notices});
        rethrow;
      }
      notice = posted;
    }
    _changed(upsert: notice);
    return notice;
  }

  /// The current member's newest notice matching [draft], posted at most
  /// [uncertainPostWindow] before [since]; `null` when there is none or the
  /// lookup fails too.
  Future<Notice?> _findPosted(
    NoticeDraft draft, {
    required DateTime since,
  }) async {
    final memberId = ref.read(currentMemberProvider)?.id;
    if (memberId == null) return null;
    final expected = draft.toJson();
    final notBefore = since.subtract(uncertainPostWindow);
    try {
      final page = await _repository.list(limit: NoticeListController.pageSize);
      for (final n in page.items) {
        if (n.isAuthoredBy(memberId) &&
            n.title == expected['title'] &&
            n.body == expected['body'] &&
            !n.createdAt.isBefore(notBefore)) {
          return n;
        }
      }
    } on ApiException {
      // Still offline: the outcome stays unknown.
    }
    return null;
  }

  /// `PATCH /notices/:id`. An empty [patch] returns [before] without a
  /// request.
  Future<Notice?> update(Notice before, NoticePatch patch) {
    if (patch.isEmpty) return Future.value(before);
    return _guard(before.id, () async {
      final notice = await _repository.update(before.id, patch);
      _changed(upsert: notice);
      return notice;
    });
  }

  /// Pins / unpins (admins only — the server answers `FORBIDDEN` otherwise).
  Future<Notice?> setPinned(Notice notice, bool pinned) {
    if (notice.pinned == pinned) return Future.value(notice);
    return update(notice, NoticePatch.pin(pinned));
  }

  /// `DELETE /notices/:id`. A notice that is already gone counts as deleted.
  /// Returns `false` when a mutation for it was already running.
  Future<bool> delete(Notice notice) async {
    final result = await _guard(notice.id, () async {
      try {
        await _repository.delete(notice.id);
      } on ApiException catch (e) {
        if (!e.isNotFound) rethrow;
      }
      _changed(removedId: notice.id);
      return true;
    });
    return result ?? false;
  }

  /// Runs [action] unless a mutation for [id] is in flight. A `NOT_FOUND`
  /// (deleted meanwhile by someone else) drops the stale notice from the
  /// board before rethrowing.
  Future<T?> _guard<T>(String id, Future<T> Function() action) async {
    if (state.contains(id)) return null;
    state = {...state, id};
    try {
      return await action();
    } on ApiException catch (e) {
      if (e.isNotFound && ref.mounted) _changed(removedId: id);
      rethrow;
    } finally {
      if (ref.mounted) state = {...state}..remove(id);
    }
  }

  void _changed({Notice? upsert, String? removedId}) {
    if (!ref.mounted) return;
    if (ref.exists(noticeListProvider)) {
      final list = ref.read(noticeListProvider.notifier);
      if (upsert != null) list.applyUpsert(upsert);
      if (removedId != null) list.applyRemove(removedId);
    }
    markChanged(ref, {DataScope.notices});
  }
}

final noticesControllerProvider =
    NotifierProvider<NoticesController, Set<String>>(NoticesController.new);
