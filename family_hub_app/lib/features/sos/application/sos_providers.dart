import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/design/app_durations.dart';
import 'package:family_hub/core/network/api_client.dart';
import 'package:family_hub/features/sos/application/sos_runtime.dart';
import 'package:family_hub/features/sos/data/sos_repository.dart';
import 'package:family_hub/features/sos/domain/sos_alert.dart';
import 'package:family_hub/shared/providers/shared_providers.dart';

export 'package:family_hub/features/sos/domain/sos_alert.dart';

// ── Active alerts (public API) ──────────────────────────────────────────────

/// Active SOS alerts of the family, the signed-in member's own included,
/// newest first (public API, docs/05-FLUTTER_GUIDE.md §10).
///
/// * Polls `GET /sos/active` every [AppDurations.pollActiveSos] while the
///   app is in the foreground and someone listens ([SosStatusBanner] in the
///   home shell, the SOS controller). Polling pauses in the background and
///   polls once right away when the app comes back.
/// * Polls are silent: the list is only replaced when it changed, and a
///   failed poll keeps the last list (a first-load failure is an error).
/// * Resets on logout / account or family switch; refetches on
///   `markChanged({DataScope.sos})`.
///
/// The server expires alerts lazily, so widgets should still check
/// [SosAlert.isActiveAt] when showing a list fetched a while ago.
final activeSosAlertsProvider =
    AsyncNotifierProvider<ActiveSosAlertsNotifier, List<SosAlert>>(
      ActiveSosAlertsNotifier.new,
      retry: apiRetryPolicy,
    );

class ActiveSosAlertsNotifier extends AsyncNotifier<List<SosAlert>> {
  int _generation = 0;
  DateTime? _fetchedAt;

  @override
  Future<List<SosAlert>> build() async {
    final generation = ++_generation;
    final userId = ref.watch(sessionUserIdProvider);
    final familyId = ref.watch(currentFamilyProvider.select((f) => f?.id));
    ref.watch(dataRefreshProvider.select((m) => m[DataScope.sos]));
    final repository = ref.watch(sosRepositoryProvider);
    if (userId == null || familyId == null) return const <SosAlert>[];

    final polling = _PollBinding(
      ref,
      interval: AppDurations.pollActiveSos,
      poll: () => _poll(generation),
      isStale: _isStale,
    );
    final List<SosAlert> alerts;
    try {
      alerts = await _read(ref, repository.active);
    } catch (_) {
      // Keep polling after a failed (re)load (offline right after a
      // `markChanged`): the next successful poll replaces the error, so
      // the banner never stays stale until the app restarts.
      if (generation == _generation) polling.start();
      rethrow;
    }
    if (generation == _generation) {
      _fetchedAt = ref.read(sosClockProvider)();
      polling.start();
    }
    return alerts;
  }

  bool _isStale() {
    final at = _fetchedAt;
    if (at == null) return true;
    final age = ref.read(sosClockProvider)().difference(at);
    return age.isNegative || age >= AppDurations.pollActiveSos;
  }

  Future<void> _poll(int generation) async {
    if (!ref.mounted || generation != _generation || state.isLoading) return;
    try {
      final alerts = await _read(ref, ref.read(sosRepositoryProvider).active);
      if (!ref.mounted || generation != _generation) return;
      _fetchedAt = ref.read(sosClockProvider)();
      if (state.hasError || !listEquals(state.value, alerts)) {
        state = AsyncData(alerts);
      }
    } catch (e, stack) {
      if (!ref.mounted || generation != _generation) return;
      if (e is ApiException && e.code == ApiErrorCode.noFamily) {
        // Removed from the family: none of its alerts may stay on screen
        // (the banner would say "Priya needs help" forever). The session
        // resync started by `_read` moves the app out of the family.
        if (!state.hasValue || state.requireValue.isNotEmpty) {
          state = const AsyncData(<SosAlert>[]);
        }
        return;
      }
      // Keep showing the last list; only a missing list becomes an error.
      if (!state.hasValue) state = AsyncError(e, stack);
      debugPrint('activeSosAlertsProvider: poll failed ($e)');
    }
  }
}

/// Runs an SOS read; a `NO_FAMILY` answer (the member was removed from the
/// family meanwhile) also resyncs the session ([sosSessionResyncProvider])
/// before it is rethrown.
Future<T> _read<T>(Ref ref, Future<T> Function() load) async {
  // Read before the await: an auto-disposed provider's ref may be gone by
  // the time the answer arrives.
  final resync = ref.read(sosSessionResyncProvider);
  try {
    return await load();
  } on ApiException catch (e) {
    if (e.code == ApiErrorCode.noFamily) resync();
    rethrow;
  }
}

/// Ids of alerts this session has seen end (resolved from this phone, or
/// found resolved / expired / gone by the SOS controller).
///
/// A list fetched before the change still reports such an alert as active
/// until its refetch lands (`markChanged` → reload, or a poll that was
/// already in flight); readers of [activeSosAlertsProvider] skip these ids
/// so a banner never flashes "needs help" / "Your SOS is active" again and
/// an ended alert is never adopted for tracking again. The server never
/// re-activates an alert, so the set is always safe. Resets on logout /
/// account switch.
final sosEndedAlertIdsProvider =
    NotifierProvider<SosEndedAlertIds, Set<String>>(SosEndedAlertIds.new);

class SosEndedAlertIds extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    ref.watch(sessionUserIdProvider);
    return const <String>{};
  }

  /// Records that [alertId] ended.
  void add(String alertId) {
    if (alertId.isEmpty || state.contains(alertId)) return;
    state = Set.unmodifiable({...state, alertId});
  }
}

/// Whether [alert] of a `/sos/active` list still counts as active: the
/// server said so (its lazy expiry is authoritative, a phone clock running
/// ahead must not hide someone who needs help) and this session has not
/// seen it end.
bool _stillActive(SosAlert alert, Set<String> ended) =>
    alert.status == SosStatus.active && !ended.contains(alert.id);

/// The signed-in member's own active alert (newest), if any.
final myActiveSosAlertProvider = Provider<SosAlert?>((ref) {
  final me = ref.watch(currentMemberProvider.select((m) => m?.id));
  final alerts = ref.watch(activeSosAlertsProvider).value;
  final ended = ref.watch(sosEndedAlertIdsProvider);
  if (me == null || alerts == null) return null;
  for (final a in alerts) {
    if (a.isOwnedBy(me) && _stillActive(a, ended)) return a;
  }
  return null;
});

/// Active alerts of **other** family members, newest first. Stays an
/// [AsyncValue] so screens can render it with `AsyncValueView`.
///
/// While the list reloads (every `markChanged({DataScope.sos})`) or after a
/// failed refetch, the last loaded list stays visible as data: `whenData`
/// would turn a reload into a bare loading state, and the banner's
/// "Priya needs help" / the SOS tab's list would blink out on every change.
final otherActiveSosAlertsProvider = Provider<AsyncValue<List<SosAlert>>>((
  ref,
) {
  final me = ref.watch(currentMemberProvider.select((m) => m?.id));
  final ended = ref.watch(sosEndedAlertIdsProvider);
  final all = ref.watch(activeSosAlertsProvider);
  if (all.hasValue) {
    return AsyncData(
      List<SosAlert>.unmodifiable([
        for (final a in all.requireValue)
          if (!a.isOwnedBy(me) && _stillActive(a, ended)) a,
      ]),
    );
  }
  if (all.hasError) return AsyncError(all.error!, all.stackTrace!);
  return const AsyncLoading();
});

// ── One alert (alert screen) ────────────────────────────────────────────────

/// One alert with its trail (`GET /sos/:id`), for `/sos/alert/:id`.
///
/// While the alert is active and the screen is visible (Riverpod pauses the
/// subscription of covered routes) it polls every [AppDurations.pollSos] in
/// the foreground. Ended alerts are not polled. `NOT_FOUND` for unknown ids,
/// other families' alerts and when signed out / without a family. Refetches
/// on account or family switch and on `markChanged({DataScope.sos})`.
final sosAlertProvider = AsyncNotifierProvider.autoDispose
    .family<SosAlertNotifier, SosAlert, String>(
      SosAlertNotifier.new,
      retry: apiRetryPolicy,
    );

class SosAlertNotifier extends AsyncNotifier<SosAlert> {
  SosAlertNotifier(this.alertId);

  final String alertId;
  int _generation = 0;
  DateTime? _fetchedAt;
  _PollBinding? _polling;

  /// Whether the shown alert is still active (only active alerts poll).
  bool _pollable = false;

  @override
  Future<SosAlert> build() async {
    final generation = ++_generation;
    final userId = ref.watch(sessionUserIdProvider);
    final familyId = ref.watch(currentFamilyProvider.select((f) => f?.id));
    ref.watch(dataRefreshProvider.select((m) => m[DataScope.sos]));
    final repository = ref.watch(sosRepositoryProvider);
    final id = alertId.trim();
    if (userId == null || familyId == null || id.isEmpty) {
      throw const ApiException(code: ApiErrorCode.notFound, statusCode: 404);
    }

    final polling = _polling = _PollBinding(
      ref,
      interval: AppDurations.pollSos,
      poll: () => _poll(generation),
      isStale: _isStale,
      canPoll: () => _pollable,
    );
    final SosAlert alert;
    try {
      alert = await _read(ref, () => repository.get(id));
    } catch (e) {
      // A transient failure (offline, 5xx) recovers by itself while the
      // screen is open; a missing alert does not.
      if (generation == _generation && !_isGone(e)) {
        _pollable = true;
        polling.start();
      }
      rethrow;
    }
    if (generation == _generation) {
      _fetchedAt = ref.read(sosClockProvider)();
      _pollable = _isLive(alert);
      polling.start();
    }
    return alert;
  }

  static bool _isGone(Object error) =>
      error is ApiException &&
      (error.isNotFound ||
          error.code == ApiErrorCode.badRequest ||
          error.code == ApiErrorCode.noFamily ||
          error.isUnauthorized);

  /// Polls while the server reports the alert as active (its status is
  /// computed lazily at read time, so it is authoritative; the phone clock
  /// may be off).
  static bool _isLive(SosAlert alert) => alert.status == SosStatus.active;

  /// Shows a fresher copy of the alert right away (e.g. the resolve
  /// response) until the next fetch confirms it.
  void apply(SosAlert alert) {
    if (!ref.mounted || alert.id != state.value?.id) return;
    final current = state.value;
    // Mutation responses carry no trail; keep the one already loaded.
    final merged = alert.trail.isEmpty && current != null
        ? alert.copyWith(trail: current.trail)
        : alert;
    state = AsyncData(merged);
    _setPollable(merged);
  }

  void _setPollable(SosAlert alert) {
    _pollable = _isLive(alert);
    _polling?.refresh();
  }

  bool _isStale() {
    final at = _fetchedAt;
    if (at == null) return true;
    final age = ref.read(sosClockProvider)().difference(at);
    return age.isNegative || age >= AppDurations.pollSos;
  }

  Future<void> _poll(int generation) async {
    if (!ref.mounted || generation != _generation || state.isLoading) return;
    try {
      final alert = await _read(
        ref,
        () => ref.read(sosRepositoryProvider).get(alertId.trim()),
      );
      if (!ref.mounted || generation != _generation) return;
      _fetchedAt = ref.read(sosClockProvider)();
      if (state.hasError || state.value != alert) state = AsyncData(alert);
      _setPollable(alert);
    } on ApiException catch (e, stack) {
      if (!ref.mounted || generation != _generation) return;
      // The alert disappeared (deleted, member removed, other family): show
      // it and stop. A transient failure keeps the loaded alert (or the
      // error already shown, without rebuilding it every poll).
      final gone = _isGone(e);
      final shown = state.error;
      final alreadyShown = shown is ApiException && shown.code == e.code;
      if ((gone || !state.hasValue) && !alreadyShown) {
        state = AsyncError(e, stack);
      }
      if (gone) {
        _pollable = false;
        _polling?.refresh();
      }
    }
  }
}

/// Polling of one provider build: enabled after the first load while
/// someone listens (Riverpod pauses the subscriptions of covered routes and
/// hidden tabs), the app is in the foreground and [canPoll] allows it.
/// Coming back (listener resumed / app resumed) polls once right away when
/// the data is stale. Released when the build is disposed.
class _PollBinding {
  _PollBinding(
    this._ref, {
    required Duration interval,
    required Future<void> Function() poll,
    required this.isStale,
    this.canPoll,
  }) : _poller = SosPoller(interval: interval, poll: poll),
       _foreground = _ref.read(sosAppForegroundProvider) {
    _ref.onDispose(_poller.dispose);
    // Life-cycle callbacks must not use `ref`: they only flip flags; the
    // catch-up poll runs in a microtask.
    _ref.onCancel(() {
      _listening = false;
      _update();
    });
    _ref.onResume(() {
      _listening = true;
      _update(catchUp: true);
    });
    _ref.listen<bool>(sosAppForegroundProvider, (previous, foreground) {
      _foreground = foreground;
      _update(catchUp: foreground && previous == false);
    });
  }

  final Ref _ref;
  final SosPoller _poller;
  final bool Function() isStale;
  final bool Function()? canPoll;
  bool _foreground;
  bool _listening = true;
  bool _started = false;

  /// Starts polling (called by the build after the first load).
  void start() {
    _started = true;
    _update();
  }

  /// Re-evaluates [canPoll] (e.g. the alert ended).
  void refresh() => _update();

  void _update({bool catchUp = false}) {
    if (!_started || !_ref.mounted) return;
    final enable = _listening && _foreground && (canPoll?.call() ?? true);
    _poller.enabled = enable;
    if (!enable || !catchUp) return;
    scheduleMicrotask(() {
      if (_ref.mounted && _poller.isEnabled && isStale()) {
        unawaited(_poller.pollNow());
      }
    });
  }
}

// ── History ─────────────────────────────────────────────────────────────────

/// Loaded part of the SOS history plus the "load more" status.
@immutable
class SosHistoryState {
  const SosHistoryState({required this.paged, this.isLoadingMore = false});

  static const empty = SosHistoryState(paged: Paged<SosAlert>.empty());

  final Paged<SosAlert> paged;
  final bool isLoadingMore;

  List<SosAlert> get items => paged.items;
  bool get hasMore => paged.hasMore;
  bool get isEmpty => paged.isEmpty;

  SosHistoryState copyWith({Paged<SosAlert>? paged, bool? isLoadingMore}) =>
      SosHistoryState(
        paged: paged ?? this.paged,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      );

  @override
  bool operator ==(Object other) =>
      other is SosHistoryState &&
      other.paged == paged &&
      other.isLoadingMore == isLoadingMore;

  @override
  int get hashCode => Object.hash(paged, isLoadingMore);
}

/// Resolved / expired alerts of the family, newest first, paginated.
///
/// Refetches on account / family switch and on
/// `markChanged({DataScope.sos})` (an alert that just ended moves here),
/// reloading as many alerts as were loaded so "load more" progress survives.
final sosHistoryProvider =
    AsyncNotifierProvider.autoDispose<SosHistoryNotifier, SosHistoryState>(
      SosHistoryNotifier.new,
      retry: apiRetryPolicy,
    );

class SosHistoryNotifier extends AsyncNotifier<SosHistoryState> {
  static const int pageSize = 20;

  int _generation = 0;
  int _loadedCount = 0;

  @override
  Future<SosHistoryState> build() async {
    final generation = ++_generation;
    final userId = ref.watch(sessionUserIdProvider);
    final familyId = ref.watch(currentFamilyProvider.select((f) => f?.id));
    ref.watch(dataRefreshProvider.select((m) => m[DataScope.sos]));
    final repository = ref.watch(sosRepositoryProvider);
    if (userId == null || familyId == null) return SosHistoryState.empty;

    final limit = math.min(
      math.max(pageSize, _loadedCount),
      SosRepository.maxPageSize,
    );
    final paged = await _read(
      ref,
      () => repository.history(page: 1, limit: limit),
    );
    if (generation == _generation) _loadedCount = paged.length;
    return SosHistoryState(paged: paged);
  }

  /// Appends the next page. No-op while loading or when everything is
  /// loaded. Rethrows API errors (the loaded alerts stay).
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
          .read(sosRepositoryProvider)
          .history(page: current.paged.nextPage, limit: current.paged.limit);
      if (!ref.mounted || generation != _generation) return;
      final merged = current.paged.append(next, identity: (a) => a.id);
      _loadedCount = merged.length;
      state = AsyncData(SosHistoryState(paged: merged));
    } catch (_) {
      if (ref.mounted && generation == _generation) {
        state = AsyncData(
          (state.value ?? current).copyWith(isLoadingMore: false),
        );
      }
      rethrow;
    }
  }
}
