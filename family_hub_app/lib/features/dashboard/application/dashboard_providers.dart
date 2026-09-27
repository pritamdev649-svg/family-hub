import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/l10n/error_messages.dart';
import 'package:family_hub/core/providers/core_providers.dart';
import 'package:family_hub/features/dashboard/data/dashboard_cache.dart';
import 'package:family_hub/features/dashboard/data/dashboard_repository.dart';
import 'package:family_hub/features/dashboard/domain/dashboard_data.dart';
import 'package:family_hub/features/dashboard/domain/dashboard_greeting.dart';
import 'package:family_hub/features/sos/application/sos_providers.dart';
import 'package:family_hub/shared/providers/shared_providers.dart';

export 'package:family_hub/features/dashboard/domain/dashboard_data.dart';

// ── Injectable collaborators (overridden in tests) ──────────────────────────

/// Current time for the greeting and the offline-copy age.
final dashboardClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// How long the first load may take before the offline copy (if any) is
/// shown. The request keeps running and replaces the copy when it arrives.
final dashboardOfflineFallbackDelayProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 2),
);

/// Re-reads the session (`GET /auth/me`). Used when the dashboard shows that
/// the session is out of date: the member was removed (`NO_FAMILY`), or the
/// server reports another role / family than the session (e.g. promoted on
/// another phone). The router and every role-aware screen then catch up.
final dashboardSessionRefreshProvider = Provider<Future<void> Function()>(
  (ref) =>
      () => ref.read(sessionControllerProvider.notifier).refreshMe(),
);

/// The live list of active SOS alerts (`activeSosAlertsProvider`, polled by
/// the SOS feature while the app is in the foreground), or `null` while it
/// has not loaded. Preferred over the dashboard's own `activeSos` snapshot so
/// the dashboard and the SOS banner always agree.
final dashboardLiveSosAlertsProvider = Provider<List<SosAlert>?>(
  (ref) => ref.watch(activeSosAlertsProvider).value,
);

/// How long the app must have been in the background before coming back
/// refetches the dashboard (other members may have changed things
/// meanwhile). Shorter trips (a phone call, the share sheet) keep the data.
const dashboardResumeRefreshAfter = Duration(minutes: 1);

// ── Time of day ─────────────────────────────────────────────────────────────

/// "Now" for the time-dependent parts of the dashboard. The value only
/// changes when they do ([GreetingPeriod.nextChangeAfter]):
///
/// * at 05:00, 12:00, 17:00 and 22:00 — the greeting;
/// * at local midnight — the header date, and "overdue", "done this week"
///   and "this month" count from a new day, so [dashboardProvider]
///   refetches.
///
/// Timers do not run while the phone sleeps: the dashboard screen calls
/// [DashboardNow.sync] when the app comes back to the foreground, and a
/// clock that was changed (time zone, manual time) is picked up there too.
final dashboardNowProvider = NotifierProvider<DashboardNow, DateTime>(
  DashboardNow.new,
);

class DashboardNow extends Notifier<DateTime> {
  /// Shortest wait between two checks: a timer that fires a little early
  /// checks again shortly instead of spinning.
  static const _minWait = Duration(seconds: 1);

  Timer? _timer;

  @override
  DateTime build() {
    ref.onDispose(_cancel);
    return _scheduleAfter(ref.watch(dashboardClockProvider)());
  }

  /// Re-reads the clock. Listeners are notified only when the greeting
  /// period or the local date changed.
  void sync() {
    if (!ref.mounted) return;
    final now = ref.read(dashboardClockProvider)();
    final changed = !GreetingPeriod.sameSlot(now, state);
    _scheduleAfter(now);
    if (changed) state = now;
  }

  DateTime _scheduleAfter(DateTime now) {
    _cancel();
    var wait = GreetingPeriod.nextChangeAfter(now).difference(now);
    if (wait < _minWait) wait = _minWait;
    _timer = Timer(wait, sync);
    return now;
  }

  void _cancel() {
    _timer?.cancel();
    _timer = null;
  }
}

/// The local calendar date of [time] (what [dashboardProvider] refetches
/// on).
DateTime _localDay(DateTime time) {
  final t = time.toLocal();
  return DateTime(t.year, t.month, t.day);
}

// ── Dashboard (public API) ──────────────────────────────────────────────────

/// The signed-in member's dashboard (`GET /dashboard`, public API,
/// docs/05-FLUTTER_GUIDE.md §10).
///
/// * Refetches on account / family switch, when the member's role changes,
///   on **every** `markChanged(...)` scope (the dashboard summarises all
///   of them) and at local midnight ([dashboardNowProvider]: "overdue",
///   "this week" and "this month" are relative to today).
/// * Every successful load is saved on the device ([DashboardCache]). When
///   the server cannot be reached (no connection, timeout, 5xx) the saved
///   copy is returned instead of an error, marked as
///   [DashboardSnapshot.isOfflineCopy]; it refreshes by itself once the
///   server answers again. On a slow first load the copy is shown after
///   [dashboardOfflineFallbackDelayProvider] (right away when the app
///   already knows it is offline) and replaced when the request finishes.
///   A reload while the copy is on screen keeps it there in the loading
///   state (so a retry shows its progress) until the request settles.
/// * Unreachable without a saved copy → the network error; it refetches by
///   itself once another request reaches the server again.
/// * `NO_FAMILY` drops the copy and resyncs the session.
/// * Signed out / without family → `NO_FAMILY` error (no request is made).
///
/// Screens should watch [dashboardViewProvider], which never shows a
/// previous account's snapshot while the new one loads.
final dashboardProvider =
    AsyncNotifierProvider<DashboardNotifier, DashboardSnapshot>(
      DashboardNotifier.new,
      retry: apiRetryPolicy,
    );

class DashboardNotifier extends AsyncNotifier<DashboardSnapshot> {
  /// Mismatches (session vs. dashboard) a resync was already started for,
  /// so a server that keeps disagreeing can never cause a refresh loop.
  final Set<String> _resynced = {};

  @override
  Future<DashboardSnapshot> build() async {
    // This build's own ref: `ref` always points at the newest build, so only
    // `buildRef.mounted` tells whether this build was superseded (account
    // switch, markChanged) while it awaited.
    final buildRef = ref;
    final userId = ref.watch(sessionUserIdProvider);
    final familyId = ref.watch(currentFamilyProvider.select((f) => f?.id));
    ref.watch(isAdminProvider);
    ref.watch(dataRefreshProvider);
    ref.watch(dashboardNowProvider.select(_localDay));
    final repository = ref.watch(dashboardRepositoryProvider);
    final cache = ref.watch(dashboardCacheProvider);
    final fallbackAfter = ref.watch(dashboardOfflineFallbackDelayProvider);
    final clock = ref.watch(dashboardClockProvider);

    if (userId == null || familyId == null || familyId.isEmpty) {
      throw const ApiException(code: ApiErrorCode.noFamily, statusCode: 403);
    }

    final request = repository.fetch().then<_Outcome>(
      _Outcome.value,
      onError: (Object e, StackTrace s) => _Outcome.error(e, s),
    );

    // First load (nothing of this account / family on screen yet): a slow
    // request shows the saved copy meanwhile. When something is on screen
    // already (fresh data or the offline copy) it stays there in the
    // loading state instead — re-emitting the copy would end the loading
    // state (retry spinner, pull to refresh) while the request still runs.
    final shown = state.value;
    DashboardSnapshot? offline;
    if (shown == null ||
        shown.userId != userId ||
        shown.data.family.id != familyId) {
      final knownOffline = ref.read(connectivityStatusProvider).isOffline;
      final settled = await _settlesWithin(
        request,
        knownOffline ? Duration.zero : fallbackAfter,
      );
      if (!settled && buildRef.mounted) {
        offline = cache.read(userId, familyId, now: clock());
        if (offline != null) state = AsyncData(offline);
      }
    }

    final outcome = await request;
    final data = outcome.data;
    if (data != null) {
      if (buildRef.mounted) {
        unawaited(cache.write(userId, data));
        _resyncIfSessionDisagrees(data);
      }
      return DashboardSnapshot(userId: userId, data: data);
    }

    final error = outcome.error!;
    if (_isUnreachable(error)) {
      if (buildRef.mounted) _refreshWhenBackOnline(buildRef);
      offline ??= buildRef.mounted
          ? cache.read(userId, familyId, now: clock())
          : null;
      if (offline != null) return offline;
    } else if (error is ApiException && error.code == ApiErrorCode.noFamily) {
      if (buildRef.mounted) {
        unawaited(cache.clear());
        _resyncSession('noFamily:$userId:$familyId');
      }
    }
    Error.throwWithStackTrace(error, outcome.stackTrace ?? StackTrace.current);
  }

  static bool _isUnreachable(Object error) {
    final e = unwrapProviderError(error);
    return e is ApiException && (e.isNetwork || e.isServer);
  }

  /// The session is refreshed when the server reports another member,
  /// family or role than the one the app works with.
  void _resyncIfSessionDisagrees(DashboardData data) {
    final member = ref.read(currentMemberProvider);
    final familyId = ref.read(currentFamilyProvider)?.id;
    if (member == null) return;
    final mismatch =
        member.id != data.me.id ||
        member.role != data.me.role ||
        familyId != data.family.id;
    if (!mismatch) return;
    _resyncSession(
      'mismatch:${data.me.id}:${data.me.role.name}:${data.family.id}',
    );
  }

  void _resyncSession(String reason) {
    if (!_resynced.add(reason)) return;
    final refresh = ref.read(dashboardSessionRefreshProvider);
    unawaited(
      Future<void>.sync(refresh).catchError((Object e) {
        if (kDebugMode) debugPrint('[Dashboard] session resync failed: $e');
      }),
    );
  }

  /// After the server could not be reached (offline copy or network error
  /// on screen): refetch once any request reaches the server again. The
  /// listener belongs to [buildRef], so it ends with the next build.
  void _refreshWhenBackOnline(Ref buildRef) {
    buildRef.listen<ConnectivityStatus>(connectivityStatusProvider, (
      previous,
      next,
    ) {
      if (previous == ConnectivityStatus.offline &&
          next.isOnline &&
          buildRef.mounted) {
        buildRef.invalidateSelf();
      }
    });
  }
}

/// Pull-to-refresh of the dashboard: announces a change of every
/// [DataScope] (so every screen of the app refetches, not just the
/// dashboard) and completes when the dashboard has reloaded. Errors are
/// left to the provider state (shown by `AsyncValueView`).
Future<void> refreshDashboard(WidgetRef ref) async {
  ref.read(dataRefreshProvider.notifier).markAllChanged();
  try {
    await ref.read(dashboardProvider.future);
  } catch (_) {
    // Surfaced through dashboardProvider's state.
  }
}

/// [dashboardProvider] for the **signed-in account and family only**: while
/// a snapshot of another account or family is still in the provider (a
/// reload after a switch keeps the previous value) this reports loading — or
/// the error of the new load — without that value. Screens watch this
/// provider.
final dashboardViewProvider = Provider<AsyncValue<DashboardSnapshot>>((ref) {
  final userId = ref.watch(sessionUserIdProvider);
  final familyId = ref.watch(currentFamilyProvider.select((f) => f?.id));
  final value = ref.watch(dashboardProvider);
  final shown = value.value;
  if (shown == null ||
      (shown.userId == userId && shown.data.family.id == familyId)) {
    return value;
  }
  final error = value.error;
  if (error != null && !value.isLoading) {
    return AsyncError<DashboardSnapshot>(
      error,
      value.stackTrace ?? StackTrace.current,
    );
  }
  return const AsyncLoading<DashboardSnapshot>();
});

/// Active SOS alerts for the dashboard's alert section, newest first:
/// the live SOS list when it has loaded, else the dashboard's own snapshot.
/// An offline copy only keeps alerts whose live window has not passed (the
/// copy may be hours old).
List<SosAlert> dashboardActiveSos({
  required DashboardSnapshot snapshot,
  required List<SosAlert>? live,
  required DateTime now,
}) {
  final source = live ?? snapshot.data.activeSos;
  final alerts = [
    for (final a in source)
      if (a.status == SosStatus.active &&
          (live != null || !snapshot.isOfflineCopy || a.isActiveAt(now)))
        a,
  ]..sort(SosAlert.compareNewestFirst);
  return List.unmodifiable(alerts);
}

// ── Helpers ─────────────────────────────────────────────────────────────────

/// Result of a request that never throws.
class _Outcome {
  _Outcome.value(DashboardData this.data) : error = null, stackTrace = null;
  _Outcome.error(Object this.error, this.stackTrace) : data = null;

  final DashboardData? data;
  final Object? error;
  final StackTrace? stackTrace;
}

/// Completes with `true` when [future] settles within [timeout], else
/// `false` (without cancelling [future]). The timer is always cancelled, so
/// no timer outlives the request.
Future<bool> _settlesWithin(Future<Object?> future, Duration timeout) {
  final result = Completer<bool>();
  final timer = Timer(timeout, () {
    if (!result.isCompleted) result.complete(false);
  });
  future.then((_) {
    timer.cancel();
    if (!result.isCompleted) result.complete(true);
  });
  return result.future;
}
