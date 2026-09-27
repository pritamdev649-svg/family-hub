import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;

import 'package:family_hub/core/network/api_exception.dart';
import 'package:family_hub/core/network/paged.dart';
import 'package:family_hub/core/utils/date_x.dart';
import 'package:family_hub/features/ledger/data/goal_repository.dart';
import 'package:family_hub/features/ledger/data/ledger_repository.dart';
import 'package:family_hub/features/ledger/domain/ledger_entry.dart';
import 'package:family_hub/features/ledger/domain/ledger_requests.dart';
import 'package:family_hub/features/ledger/domain/ledger_summary.dart';
import 'package:family_hub/features/ledger/domain/savings_goal.dart';
import 'package:family_hub/shared/providers/shared_providers.dart';

// ── Month selection ──────────────────────────────────────────────────────────

/// First day of the current (device-local) month.
DateTime currentLedgerMonth([DateTime? now]) =>
    (now ?? DateTime.now()).toLocal().startOfMonth;

/// [month] normalised to the first day of its month and never later than
/// the current month (the ledger has no future months).
DateTime clampLedgerMonth(DateTime month, {DateTime? now}) {
  final m = DateTime(month.year, month.month);
  final current = currentLedgerMonth(now);
  return m.isAfter(current) ? current : m;
}

/// Whether [month] is before the current month (so "next" is possible).
bool canGoToNextMonth(DateTime month, {DateTime? now}) =>
    DateTime(month.year, month.month).isBefore(currentLedgerMonth(now));

/// The month shown on the Money tab (first day, local). Resets to the
/// current month on sign-in / account switch.
class SelectedLedgerMonth extends Notifier<DateTime> {
  @override
  DateTime build() {
    ref.watch(sessionUserIdProvider);
    return currentLedgerMonth();
  }

  bool get canGoNext => canGoToNextMonth(state);

  void previous() => state = DateTime(state.year, state.month).addMonths(-1);

  void next() {
    if (canGoNext) state = DateTime(state.year, state.month).addMonths(1);
  }

  /// Shows [month] (clamped to the current month).
  void select(DateTime month) => state = clampLedgerMonth(month);
}

final selectedLedgerMonthProvider =
    NotifierProvider<SelectedLedgerMonth, DateTime>(SelectedLedgerMonth.new);

// ── Stale session ────────────────────────────────────────────────────────────

/// Re-reads the session (`GET /auth/me`) in the background when a ledger
/// call shows that the session no longer matches the server: the member was
/// removed from the family (`NO_FAMILY`) or lost a permission (`FORBIDDEN`,
/// e.g. demoted from admin on another phone). The router and every
/// role-aware screen then catch up. Concurrent requests share one refresh.
class LedgerSessionResync {
  LedgerSessionResync(this._refresh);

  final Future<void> Function() _refresh;
  bool _running = false;

  /// Starts a refresh unless one is running. Never throws.
  void call() {
    if (_running) return;
    _running = true;
    unawaited(
      Future<void>.sync(_refresh)
          .catchError((Object e) {
            if (kDebugMode) debugPrint('[Ledger] session resync failed: $e');
          })
          .whenComplete(() => _running = false),
    );
  }
}

final ledgerSessionResyncProvider = Provider<LedgerSessionResync>(
  (ref) => LedgerSessionResync(
    () => ref.read(sessionControllerProvider.notifier).refreshMe(),
  ),
);

/// Runs a read; a `NO_FAMILY` answer also resyncs the session (see
/// [LedgerSessionResync]) before it is rethrown for the screen.
Future<T> _load<T>(Ref ref, Future<T> Function() load) async {
  // Read before the await: an auto-disposed provider's ref may be gone by
  // the time the answer arrives.
  final resync = ref.read(ledgerSessionResyncProvider);
  try {
    return await load();
  } on ApiException catch (e) {
    if (e.code == ApiErrorCode.noFamily) resync();
    rethrow;
  }
}

// ── Summary & recent entries ─────────────────────────────────────────────────

/// Number of entries shown in "Recent entries" on the Money tab.
const recentEntriesCount = 10;

/// `GET /ledger/summary?month=` for a `YYYY-MM` key (family scope for
/// admins, personal for members). Refetches on ledger / family changes and
/// when the caller's role changes (the scope follows the role).
final ledgerSummaryProvider = FutureProvider.autoDispose
    .family<LedgerSummary, String>((ref, month) async {
      final userId = ref.watch(sessionUserIdProvider);
      ref.watch(isAdminProvider);
      ref.watch(dataRefreshProvider.select((m) => m[DataScope.ledger]));
      ref.watch(dataRefreshProvider.select((m) => m[DataScope.family]));
      if (userId == null) return LedgerSummary.empty(month: month);
      final repository = ref.watch(ledgerRepositoryProvider);
      return _load(ref, () => repository.summary(month: month));
    }, retry: apiRetryPolicy);

/// The newest [recentEntriesCount] entries of a `YYYY-MM` month (what the
/// caller may see, which depends on the role).
final recentLedgerEntriesProvider = FutureProvider.autoDispose
    .family<List<LedgerEntry>, String>((ref, month) async {
      final userId = ref.watch(sessionUserIdProvider);
      ref.watch(isAdminProvider);
      ref.watch(dataRefreshProvider.select((m) => m[DataScope.ledger]));
      if (userId == null) return const <LedgerEntry>[];
      final repository = ref.watch(ledgerRepositoryProvider);
      final page = await _load(
        ref,
        () => repository.listEntries(
          query: LedgerEntryQuery(month: month),
          limit: recentEntriesCount,
        ),
      );
      return page.items;
    }, retry: apiRetryPolicy);

// ── Goals ────────────────────────────────────────────────────────────────────

/// Every goal of the family (`status=all`, active first). Refetches on goal
/// changes (contributions, edits) and account switch.
final savingsGoalsProvider = FutureProvider.autoDispose<List<SavingsGoal>>((
  ref,
) async {
  final userId = ref.watch(sessionUserIdProvider);
  ref.watch(dataRefreshProvider.select((m) => m[DataScope.goals]));
  if (userId == null) return const <SavingsGoal>[];
  final repository = ref.watch(goalRepositoryProvider);
  return _load(ref, repository.listGoals);
}, retry: apiRetryPolicy);

/// One goal by id, served from [savingsGoalsProvider] (the contract has no
/// `GET /goals/:id`). `NOT_FOUND` when it does not exist (anymore).
final savingsGoalProvider = FutureProvider.autoDispose
    .family<SavingsGoal, String>((ref, id) async {
      final List<SavingsGoal> goals;
      try {
        goals = await ref.watch(savingsGoalsProvider.future);
      } on ProviderException catch (e) {
        // Surface the real ApiException so screens show a proper message.
        Error.throwWithStackTrace(e.exception, e.stackTrace);
      }
      for (final g in goals) {
        if (g.id == id) return g;
      }
      throw const ApiException(code: ApiErrorCode.notFound, statusCode: 404);
    }, retry: apiRetryPolicy);

// ── Paginated entries ────────────────────────────────────────────────────────

/// Loaded pages of an entries list plus the "load more" busy flag.
@immutable
class LedgerEntriesState {
  const LedgerEntriesState({required this.page, this.isLoadingMore = false});

  const LedgerEntriesState.empty()
    : page = const Paged<LedgerEntry>.empty(),
      isLoadingMore = false;

  final Paged<LedgerEntry> page;
  final bool isLoadingMore;

  List<LedgerEntry> get items => page.items;
  bool get hasMore => page.hasMore;
  bool get isEmpty => page.isEmpty;
  int get total => page.total;

  LedgerEntriesState copyWith({
    Paged<LedgerEntry>? page,
    bool? isLoadingMore,
  }) => LedgerEntriesState(
    page: page ?? this.page,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
  );

  @override
  bool operator ==(Object other) =>
      other is LedgerEntriesState &&
      other.page == page &&
      other.isLoadingMore == isLoadingMore;

  @override
  int get hashCode => Object.hash(page, isLoadingMore);
}

/// `GET /ledger/entries` with [query], page by page. Starts over from page 1
/// whenever the ledger changes (`markChanged({DataScope.ledger})`) or the
/// caller's role changes (visibility follows the role).
class LedgerEntriesController extends AsyncNotifier<LedgerEntriesState> {
  LedgerEntriesController(this.query);

  final LedgerEntryQuery query;

  static const pageSize = 20;

  /// Bumped on every (re)build so a page that arrives after a refresh is
  /// dropped instead of being appended to the new list.
  int _generation = 0;

  @override
  Future<LedgerEntriesState> build() async {
    final userId = ref.watch(sessionUserIdProvider);
    ref.watch(isAdminProvider);
    ref.watch(dataRefreshProvider.select((m) => m[DataScope.ledger]));
    final repository = ref.watch(ledgerRepositoryProvider);
    _generation++;
    if (userId == null) return const LedgerEntriesState.empty();
    final page = await _load(
      ref,
      () => repository.listEntries(query: query, limit: pageSize),
    );
    return LedgerEntriesState(page: page);
  }

  /// Loads the next page. No-op while loading / refreshing or when there is
  /// nothing more. Errors are rethrown for the UI (the loaded pages stay).
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null ||
        !current.hasMore ||
        current.isLoadingMore ||
        state.isLoading) {
      return;
    }
    final generation = _generation;
    state = AsyncData(current.copyWith(isLoadingMore: true));
    try {
      final next = await ref
          .read(ledgerRepositoryProvider)
          .listEntries(
            query: query,
            page: current.page.nextPage,
            limit: pageSize,
          );
      if (!ref.mounted || generation != _generation) return;
      final latest = state.value ?? current;
      state = AsyncData(
        LedgerEntriesState(
          page: latest.page.append(next, identity: (e) => e.id),
        ),
      );
    } catch (_) {
      if (ref.mounted && generation == _generation) {
        final latest = state.value ?? current;
        state = AsyncData(latest.copyWith(isLoadingMore: false));
      }
      rethrow;
    }
  }
}

final ledgerEntriesProvider = AsyncNotifierProvider.autoDispose
    .family<LedgerEntriesController, LedgerEntriesState, LedgerEntryQuery>(
      LedgerEntriesController.new,
      retry: apiRetryPolicy,
    );

// ── Mutations ────────────────────────────────────────────────────────────────

/// Every ledger / goal write. Each successful call announces
/// `markChanged({DataScope.ledger, DataScope.goals})` so the Money tab,
/// entry lists, goal screens and the dashboard refresh together.
///
/// Failures are rethrown for the screen (busy state and message stay with
/// the screen), but some of them first repair the client's view:
/// * `NOT_FOUND` / `409` (the record was deleted or archived by someone
///   else) and `TIMEOUT` (the write may still have gone through) →
///   `markChanged` so every list shows the server's current state;
/// * `422 details.memberId` (the chosen member left the family) →
///   `markChanged({DataScope.members})`;
/// * `FORBIDDEN` / `NO_FAMILY` (role changed or removed from the family) →
///   background session resync ([ledgerSessionResyncProvider]).
class LedgerActions {
  LedgerActions(this._ref);

  final Ref _ref;

  /// Scopes touched by every ledger / goal mutation (a contribution changes
  /// both; an entry deletion may change a goal).
  static const changedScopes = {DataScope.ledger, DataScope.goals};

  LedgerRepository get _ledger => _ref.read(ledgerRepositoryProvider);
  GoalRepository get _goals => _ref.read(goalRepositoryProvider);

  void _changed() => markChanged(_ref, changedScopes);

  Future<T> _run<T>(Future<T> Function() write) async {
    try {
      return await write();
    } catch (e) {
      _recover(e);
      rethrow;
    }
  }

  void _recover(Object error) {
    if (error is! ApiException) return;
    if (error.isNotFound ||
        error.statusCode == 409 ||
        error.code == ApiErrorCode.conflict ||
        error.code == ApiErrorCode.timeout) {
      _changed();
    }
    if (error.isValidation && error.fieldErrors.containsKey('memberId')) {
      markChanged(_ref, const {DataScope.members});
    }
    if (error.isForbidden || error.code == ApiErrorCode.noFamily) {
      _ref.read(ledgerSessionResyncProvider)();
    }
  }

  Future<LedgerEntry> createEntry(LedgerEntryInput input) => _run(() async {
    final entry = await _ledger.createEntry(input);
    _changed();
    return entry;
  });

  /// Returns the updated entry, or null when [patch] was empty (nothing
  /// sent, nothing changed).
  Future<LedgerEntry?> updateEntry(String id, LedgerEntryPatch patch) =>
      _run(() async {
        final entry = await _ledger.updateEntry(id, patch);
        if (entry != null) _changed();
        return entry;
      });

  Future<void> deleteEntry(String id) => _run(() async {
    await _ledger.deleteEntry(id);
    _changed();
  });

  Future<SavingsGoal> createGoal(GoalInput input) => _run(() async {
    final goal = await _goals.createGoal(input);
    _changed();
    return goal;
  });

  Future<SavingsGoal?> updateGoal(String id, GoalPatch patch) => _run(() async {
    final goal = await _goals.updateGoal(id, patch);
    if (goal != null) _changed();
    return goal;
  });

  /// Archive ([GoalStatus.archived]) or restore ([GoalStatus.active]; the
  /// server re-derives `achieved` from the saved amount).
  Future<SavingsGoal?> setGoalStatus(String id, GoalStatus status) =>
      updateGoal(id, GoalPatch.status(status));

  Future<void> deleteGoal(String id) => _run(() async {
    await _goals.deleteGoal(id);
    _changed();
  });

  Future<GoalContributionResult> contribute(
    String goalId,
    GoalContributionInput input,
  ) => _run(() async {
    final result = await _goals.contribute(goalId, input);
    _changed();
    return result;
  });
}

final ledgerActionsProvider = Provider<LedgerActions>(LedgerActions.new);
