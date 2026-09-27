import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/providers/core_providers.dart';
import 'package:family_hub/features/dashboard/application/dashboard_providers.dart';
import 'package:family_hub/features/dashboard/data/dashboard_cache.dart';
import 'package:family_hub/features/sos/domain/sos_alert.dart';
import 'package:family_hub/shared/models/family.dart';
import 'package:family_hub/shared/models/member.dart';
import 'package:family_hub/shared/providers/shared_providers.dart';

import 'dashboard_test_utils.dart';

const _network = ApiException.network();
const _forbidden = ApiException(code: ApiErrorCode.forbidden, statusCode: 403);
const _noFamily = ApiException(code: ApiErrorCode.noFamily, statusCode: 403);

void main() {
  late FakeDashboardRepository repository;
  late SessionRefreshRecorder sessionRefresh;

  Future<ProviderContainer> makeContainer({
    List<Object>? responses,
    Map<String, Object> prefs = const {},
    Duration fallbackDelay = const Duration(milliseconds: 50),
    void Function(DashboardCache cache)? seedCache,
    TestClock? clock,
  }) async {
    repository = FakeDashboardRepository(responses);
    sessionRefresh = SessionRefreshRecorder();
    final sharedPrefs = await mockPrefs(prefs);
    final container = ProviderContainer.test(
      retry: (_, _) => null,
      overrides: dashboardOverrides(
        repository: repository,
        prefs: sharedPrefs,
        sessionRefresh: sessionRefresh,
        fallbackDelay: fallbackDelay,
        clock: clock,
      ),
    );
    seedCache?.call(container.read(dashboardCacheProvider));
    return container;
  }

  /// Keeps [dashboardProvider] alive and returns the listened states.
  List<AsyncValue<DashboardSnapshot>> listen(ProviderContainer c) {
    final states = <AsyncValue<DashboardSnapshot>>[];
    c.listen(
      dashboardProvider,
      (_, next) => states.add(next),
      fireImmediately: true,
    );
    return states;
  }

  group('dashboardProvider', () {
    test('loads the dashboard of the signed-in account and saves it', () async {
      final c = await makeContainer();
      listen(c);

      final snapshot = await c.read(dashboardProvider.future);
      expect(snapshot.userId, testUserId);
      expect(snapshot.isOfflineCopy, isFalse);
      expect(snapshot.data.family.name, 'Sharma Family');
      expect(repository.calls, 1);

      await pumpEventQueue();
      final saved = c
          .read(dashboardCacheProvider)
          .read(testUserId, testFamilyId);
      expect(saved?.data, snapshot.data);
    });

    test('refetches on a change of any data scope', () async {
      final c = await makeContainer();
      listen(c);
      await c.read(dashboardProvider.future);

      for (final scope in DataScope.values) {
        c.read(dataRefreshProvider.notifier).markChanged({scope});
        await c.read(dashboardProvider.future);
      }
      expect(repository.calls, 1 + DataScope.values.length);
    });

    test('refetches when the member\'s role changes', () async {
      final c = await makeContainer();
      listen(c);
      await c.read(dashboardProvider.future);

      c
          .read(testSessionProvider.notifier)
          .set(
            userId: testUserId,
            family: testFamily,
            member: testMe.copyWith(role: MemberRole.member),
          );
      await c.read(dashboardProvider.future);
      expect(repository.calls, 2);
    });

    test('signed out or without family → NO_FAMILY, no request', () async {
      final c = await makeContainer();
      c.read(testSessionProvider.notifier).set(userId: null);
      listen(c);

      await expectLater(
        c.read(dashboardProvider.future),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            ApiErrorCode.noFamily,
          ),
        ),
      );
      expect(repository.calls, 0);

      c
          .read(testSessionProvider.notifier)
          .set(userId: testUserId, member: testMe);
      await expectLater(
        c.read(dashboardProvider.future),
        throwsA(isA<ApiException>()),
      );
      expect(repository.calls, 0);
    });

    test('offline with a saved copy → the copy, marked offline', () async {
      final c = await makeContainer(responses: [_network]);
      await c.read(dashboardCacheProvider).write(testUserId, dashboardData());
      listen(c);

      final snapshot = await c.read(dashboardProvider.future);
      expect(snapshot.isOfflineCopy, isTrue);
      expect(snapshot.savedAt, isNotNull);
      expect(snapshot.data.family.name, 'Sharma Family');
    });

    test('server errors (5xx) also fall back to the saved copy', () async {
      final c = await makeContainer(
        responses: [
          const ApiException(code: ApiErrorCode.internal, statusCode: 500),
        ],
      );
      await c.read(dashboardCacheProvider).write(testUserId, dashboardData());
      listen(c);

      expect((await c.read(dashboardProvider.future)).isOfflineCopy, isTrue);
    });

    test('offline without a saved copy → the network error', () async {
      final c = await makeContainer(responses: [_network]);
      listen(c);
      await expectLater(
        c.read(dashboardProvider.future),
        throwsA(
          isA<ApiException>().having((e) => e.isNetwork, 'network', true),
        ),
      );
    });

    test('a saved copy of another account is never used', () async {
      final c = await makeContainer(responses: [_forbidden]);
      await c.read(dashboardCacheProvider).write('other-user', dashboardData());
      listen(c);
      await expectLater(
        c.read(dashboardProvider.future),
        throwsA(isA<ApiException>()),
      );
    });

    test('other errors are not replaced by the saved copy', () async {
      final c = await makeContainer(responses: [_forbidden]);
      await c.read(dashboardCacheProvider).write(testUserId, dashboardData());
      listen(c);
      await expectLater(
        c.read(dashboardProvider.future),
        throwsA(
          isA<ApiException>().having((e) => e.isForbidden, 'forbidden', true),
        ),
      );
      expect(sessionRefresh.calls, 0);
    });

    test(
      'NO_FAMILY drops the saved copy and resyncs the session once',
      () async {
        final c = await makeContainer(responses: [_noFamily]);
        await c.read(dashboardCacheProvider).write(testUserId, dashboardData());
        listen(c);

        await expectLater(
          c.read(dashboardProvider.future),
          throwsA(isA<ApiException>()),
        );
        await pumpEventQueue();
        expect(
          c.read(dashboardCacheProvider).read(testUserId, testFamilyId),
          isNull,
        );
        expect(sessionRefresh.calls, 1);

        c.invalidate(dashboardProvider);
        await expectLater(
          c.read(dashboardProvider.future),
          throwsA(isA<ApiException>()),
        );
        await pumpEventQueue();
        expect(sessionRefresh.calls, 1, reason: 'no refresh loop');
      },
    );

    test('resyncs the session when the server reports another role', () async {
      final demoted = dashboardData(
        dashboardJson(me: memberJson(role: 'member')),
      );
      final c = await makeContainer(responses: [demoted]);
      listen(c);
      await c.read(dashboardProvider.future);
      await pumpEventQueue();
      expect(sessionRefresh.calls, 1);

      c.read(dataRefreshProvider.notifier).markAllChanged();
      await c.read(dashboardProvider.future);
      await pumpEventQueue();
      expect(sessionRefresh.calls, 1, reason: 'same mismatch → no loop');
    });

    test('no resync when session and dashboard agree', () async {
      final c = await makeContainer();
      listen(c);
      await c.read(dashboardProvider.future);
      await pumpEventQueue();
      expect(sessionRefresh.calls, 0);
    });

    test(
      'a slow first load shows the saved copy, then the fresh data',
      () async {
        final gate = Completer<DashboardData>();
        final c = await makeContainer(responses: [gate]);
        await c
            .read(dashboardCacheProvider)
            .write(
              testUserId,
              dashboardData(
                dashboardJson(family: familyJson(name: 'Cached Family')),
              ),
            );
        final states = listen(c);

        await Future<void>.delayed(const Duration(milliseconds: 120));
        final shown = c.read(dashboardProvider).value;
        expect(shown?.isOfflineCopy, isTrue);
        expect(shown?.data.family.name, 'Cached Family');

        // Showing the copy completes `.future` early; the build's own
        // result replaces it once the request finishes.
        gate.complete(dashboardData());
        await pumpEventQueue();
        final fresh = c.read(dashboardProvider).requireValue;
        expect(fresh.isOfflineCopy, isFalse);
        expect(fresh.data.family.name, 'Sharma Family');
        expect(states.last.value?.isOfflineCopy, isFalse);
        expect(repository.calls, 1);
      },
    );

    test('a known-offline start shows the saved copy right away', () async {
      final gate = Completer<DashboardData>();
      final c = await makeContainer(
        responses: [gate],
        fallbackDelay: const Duration(hours: 1),
      );
      await c.read(dashboardCacheProvider).write(testUserId, dashboardData());
      c.read(connectivityStatusProvider.notifier).report(false);
      listen(c);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.read(dashboardProvider).value?.isOfflineCopy, isTrue);
      gate.complete(dashboardData());
      await c.read(dashboardProvider.future);
    });

    test('an offline copy refreshes when the server answers again', () async {
      final c = await makeContainer(responses: [_network, dashboardData()]);
      await c.read(dashboardCacheProvider).write(testUserId, dashboardData());
      final connectivity = c.read(connectivityStatusProvider.notifier)
        ..report(false);
      listen(c);
      expect((await c.read(dashboardProvider.future)).isOfflineCopy, isTrue);

      connectivity.report(true);
      await pumpEventQueue();
      final fresh = await c.read(dashboardProvider.future);
      expect(fresh.isOfflineCopy, isFalse);
      expect(repository.calls, 2);
    });

    test('without a saved copy it also refetches once back online', () async {
      final c = await makeContainer(responses: [_network, dashboardData()]);
      final connectivity = c.read(connectivityStatusProvider.notifier)
        ..report(false);
      listen(c);
      await expectLater(
        c.read(dashboardProvider.future),
        throwsA(isA<ApiException>()),
      );
      expect(c.read(dashboardProvider).hasError, isTrue);

      connectivity.report(true);
      await pumpEventQueue();
      final fresh = await c.read(dashboardProvider.future);
      expect(fresh.isOfflineCopy, isFalse);
      expect(repository.calls, 2);
    });

    test('a retry keeps the offline copy on screen, loading, until the '
        'request settles', () async {
      final gate = Completer<DashboardData>();
      final c = await makeContainer(
        responses: [_network, gate],
        fallbackDelay: Duration.zero,
      );
      await c.read(dashboardCacheProvider).write(testUserId, dashboardData());
      c.read(connectivityStatusProvider.notifier).report(false);
      listen(c);
      expect((await c.read(dashboardProvider.future)).isOfflineCopy, isTrue);

      c.invalidate(dashboardProvider);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      // Still loading (retry spinner / progress bar) with the copy shown —
      // not the copy re-emitted as if the retry had finished.
      final retrying = c.read(dashboardProvider);
      expect(retrying.isLoading, isTrue);
      expect(retrying.value?.isOfflineCopy, isTrue);

      gate.complete(dashboardData());
      final fresh = await c.read(dashboardProvider.future);
      expect(fresh.isOfflineCopy, isFalse);
      expect(c.read(dashboardProvider).isLoading, isFalse);
      expect(repository.calls, 2);
    });

    test('refetches at local midnight, not at a greeting change', () async {
      final clock = TestClock(DateTime(2026, 9, 21, 11, 59));
      final c = await makeContainer(clock: clock);
      listen(c);
      await c.read(dashboardProvider.future);
      final now = c.read(dashboardNowProvider.notifier);

      // 12:00 — only the greeting changes.
      clock.now = DateTime(2026, 9, 21, 12, 0, 1);
      now.sync();
      await c.read(dashboardProvider.future);
      expect(c.read(dashboardNowProvider), clock.now);
      expect(repository.calls, 1);

      // Midnight — "overdue", "this week" and "this month" move on.
      clock.now = DateTime(2026, 9, 22, 0, 0, 1);
      now.sync();
      await c.read(dashboardProvider.future);
      expect(repository.calls, 2);
    });
  });

  group('dashboardNowProvider', () {
    test('changes only when the greeting period or the date changes', () async {
      final clock = TestClock(DateTime(2026, 9, 21, 9));
      final c = await makeContainer(clock: clock);
      final states = <DateTime>[];
      c.listen(dashboardNowProvider, (_, next) => states.add(next));
      expect(c.read(dashboardNowProvider), DateTime(2026, 9, 21, 9));

      clock.now = DateTime(2026, 9, 21, 11, 30);
      c.read(dashboardNowProvider.notifier).sync();
      expect(states, isEmpty, reason: 'still morning');

      clock.now = DateTime(2026, 9, 21, 17, 5);
      c.read(dashboardNowProvider.notifier).sync();
      expect(states, [DateTime(2026, 9, 21, 17, 5)]);

      // A clock set back a day (manual time / time zone change) counts too.
      clock.now = DateTime(2026, 9, 20, 17, 30);
      c.read(dashboardNowProvider.notifier).sync();
      expect(states.last, DateTime(2026, 9, 20, 17, 30));
    });
  });

  group('dashboardViewProvider', () {
    test('never shows the previous account\'s dashboard', () async {
      final gate = Completer<DashboardData>();
      final c = await makeContainer(responses: [dashboardData(), gate]);
      c.listen(dashboardViewProvider, (_, _) {}, fireImmediately: true);
      await c.read(dashboardProvider.future);
      expect(c.read(dashboardViewProvider).value?.userId, testUserId);

      final priya = Member.fromJson(
        memberJson(id: 'm-priya', userId: 'u-priya', name: 'Priya'),
      );
      c
          .read(testSessionProvider.notifier)
          .set(userId: 'u-priya', family: testFamily, member: priya);
      await pumpEventQueue();

      // The provider still holds Amit's snapshot while Priya's loads …
      expect(c.read(dashboardProvider).value?.userId, testUserId);
      // … but the view does not expose it.
      final view = c.read(dashboardViewProvider);
      expect(view.isLoading, isTrue);
      expect(view.hasValue, isFalse);

      gate.complete(
        dashboardData(
          dashboardJson(
            me: memberJson(id: 'm-priya', userId: 'u-priya', name: 'Priya'),
          ),
        ),
      );
      await c.read(dashboardProvider.future);
      expect(c.read(dashboardViewProvider).value?.userId, 'u-priya');
    });

    test(
      'the error of another account\'s load comes without its data',
      () async {
        final c = await makeContainer(responses: [dashboardData(), _forbidden]);
        c.listen(dashboardViewProvider, (_, _) {}, fireImmediately: true);
        await c.read(dashboardProvider.future);

        c
            .read(testSessionProvider.notifier)
            .set(
              userId: 'u-priya',
              family: testFamily,
              member: testMe.copyWith(id: 'm-priya'),
            );
        await expectLater(c.read(dashboardProvider.future), throwsA(anything));
        final view = c.read(dashboardViewProvider);
        expect(view.hasError, isTrue);
        expect(view.hasValue, isFalse);
      },
    );

    test('hides a snapshot of another family', () async {
      final gate = Completer<DashboardData>();
      final c = await makeContainer(responses: [dashboardData(), gate]);
      c.listen(dashboardViewProvider, (_, _) {}, fireImmediately: true);
      await c.read(dashboardProvider.future);

      c
          .read(testSessionProvider.notifier)
          .set(
            userId: testUserId,
            family: Family.fromJson(familyJson(id: 'fam2', name: 'New')),
            member: testMe,
          );
      await pumpEventQueue();
      expect(c.read(dashboardViewProvider).hasValue, isFalse);
      gate.complete(
        dashboardData(dashboardJson(family: familyJson(id: 'fam2'))),
      );
      await c.read(dashboardProvider.future);
      expect(c.read(dashboardViewProvider).value?.data.family.id, 'fam2');
    });
  });

  group('dashboardActiveSos', () {
    final now = testNow;
    SosAlert alert(
      String id, {
      String status = 'active',
      DateTime? startedAt,
    }) => SosAlert.fromJson(
      sosJson(id: id, status: status, startedAt: startedAt),
    );

    DashboardSnapshot snapshot(List<SosAlert> alerts, {bool offline = false}) =>
        DashboardSnapshot(
          userId: testUserId,
          data: dashboardData().copyWith(activeSos: alerts),
          savedAt: offline ? now : null,
        );

    test('prefers the live SOS list when it has loaded', () {
      final result = dashboardActiveSos(
        snapshot: snapshot([alert('a')]),
        live: [alert('live')],
        now: now,
      );
      expect(result.map((a) => a.id), ['live']);
    });

    test('falls back to the snapshot and keeps only active alerts', () {
      final result = dashboardActiveSos(
        snapshot: snapshot([alert('a'), alert('b', status: 'resolved')]),
        live: null,
        now: now,
      );
      expect(result.map((a) => a.id), ['a']);
    });

    test('an offline copy drops alerts whose window has passed', () {
      final old = alert(
        'old',
        startedAt: now.subtract(const Duration(hours: 3)),
      );
      final fresh = alert('fresh');
      expect(
        dashboardActiveSos(
          snapshot: snapshot([old, fresh], offline: true),
          live: null,
          now: now,
        ).map((a) => a.id),
        ['fresh'],
      );
      // Online data trusts the server's lazy expiry.
      expect(
        dashboardActiveSos(
          snapshot: snapshot([old, fresh]),
          live: null,
          now: now,
        ),
        hasLength(2),
      );
    });

    test('newest first', () {
      final older = alert(
        'older',
        startedAt: now.subtract(const Duration(minutes: 9)),
      );
      final newer = alert(
        'newer',
        startedAt: now.subtract(const Duration(minutes: 1)),
      );
      expect(
        dashboardActiveSos(
          snapshot: snapshot([older, newer]),
          live: null,
          now: now,
        ).map((a) => a.id),
        ['newer', 'older'],
      );
    });
  });
}
