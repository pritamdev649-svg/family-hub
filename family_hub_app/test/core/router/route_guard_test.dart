import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/router/route_guard.dart';
import 'package:family_hub/shared/models/session_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

SessionState _session({bool verified = true, bool withFamily = true}) {
  return SessionState.fromJson({
    'user': {
      'id': 'u1',
      'email': 'demo@familyhub.app',
      'name': 'Amit',
      'emailVerified': verified,
      'familyId': withFamily ? 'f1' : null,
      'memberId': withFamily ? 'm1' : null,
      'role': withFamily ? 'admin' : null,
    },
    if (withFamily)
      'member': {'id': 'm1', 'familyId': 'f1', 'name': 'Amit', 'role': 'admin'},
    if (withFamily)
      'family': {
        'id': 'f1',
        'name': 'Sharma Family',
        'country': 'IN',
        'currency': 'INR',
      },
  });
}

void main() {
  group('routeGateOf', () {
    test('loading without a value -> loading', () {
      expect(
        routeGateOf(const AsyncLoading<SessionState>()),
        RouteGate.loading,
      );
    });

    test('error without a value -> signedOut', () {
      expect(
        routeGateOf(
          AsyncError<SessionState>(Exception('boom'), StackTrace.empty),
        ),
        RouteGate.signedOut,
      );
    });

    test('maps the session state', () {
      expect(
        routeGateOf(const AsyncData(SessionState.signedOut)),
        RouteGate.signedOut,
      );
      expect(
        routeGateOf(AsyncData(_session(verified: false))),
        RouteGate.needsVerification,
      );
      expect(
        routeGateOf(AsyncData(_session(withFamily: false))),
        RouteGate.needsFamily,
      );
      expect(routeGateOf(AsyncData(_session())), RouteGate.ready);
    });

    test('an unverified user without family must verify first', () {
      expect(
        routeGateOf(AsyncData(_session(verified: false, withFamily: false))),
        RouteGate.needsVerification,
      );
    });

    test('refreshing keeps the previous value (no splash flash)', () async {
      var calls = 0;
      final session = FutureProvider<SessionState>((ref) async {
        calls++;
        if (calls > 1) await Future<void>.delayed(const Duration(seconds: 1));
        return _session();
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final sub = container.listen(session, (_, _) {});
      addTearDown(sub.close);

      await container.read(session.future);
      expect(routeGateOf(container.read(session)), RouteGate.ready);

      container.invalidate(session);
      final refreshing = container.read(session);
      expect(refreshing.isLoading, isTrue);
      expect(routeGateOf(refreshing), RouteGate.ready);
    });
  });

  group('RouteGuard.redirect', () {
    late RouteGuard guard;
    setUp(() => guard = RouteGuard());

    String? go(RouteGate gate, String location) =>
        guard.redirect(gate, Uri.parse(location));

    test('loading shows the splash', () {
      expect(go(RouteGate.loading, '/splash'), isNull);
      expect(go(RouteGate.loading, '/home'), AppRoutes.splash);
      expect(go(RouteGate.loading, '/login'), AppRoutes.splash);
    });

    test('signed out may only see signed-out screens', () {
      for (final p in [
        '/welcome',
        '/login',
        '/register?mode=join',
        '/forgot-password',
      ]) {
        expect(go(RouteGate.signedOut, p), isNull, reason: p);
      }
      for (final p in [
        '/splash',
        '/',
        '/home',
        '/tasks/1',
        '/verify-email',
        '/family-setup',
        '/nope',
      ]) {
        expect(go(RouteGate.signedOut, p), AppRoutes.welcome, reason: p);
      }
    });

    test('unverified users are held on verify-email', () {
      expect(go(RouteGate.needsVerification, '/verify-email'), isNull);
      expect(go(RouteGate.needsVerification, '/home'), AppRoutes.verifyEmail);
      expect(go(RouteGate.needsVerification, '/login'), AppRoutes.verifyEmail);
      expect(
        go(RouteGate.needsVerification, '/family-setup'),
        AppRoutes.verifyEmail,
      );
    });

    test('users without a family are held on family-setup', () {
      expect(go(RouteGate.needsFamily, '/family-setup'), isNull);
      expect(go(RouteGate.needsFamily, '/home'), AppRoutes.familySetup);
      expect(go(RouteGate.needsFamily, '/verify-email'), AppRoutes.familySetup);
    });

    test('a complete session leaves public screens for home', () {
      for (final p in [
        '/',
        '/splash',
        '/welcome',
        '/login',
        '/register',
        '/verify-email',
        '/family-setup',
      ]) {
        expect(go(RouteGate.ready, p), AppRoutes.home, reason: p);
      }
      for (final p in [
        '/home',
        '/tasks',
        '/tasks/1',
        '/money/goals/new',
        '/settings/language',
        '/unknown',
      ]) {
        expect(go(RouteGate.ready, p), isNull, reason: p);
      }
    });

    test(
      'a deep link requested during restore opens after the session is ready',
      () {
        expect(go(RouteGate.loading, '/sos/alert/a1'), AppRoutes.splash);
        expect(guard.pendingLocation, '/sos/alert/a1');
        // Restored as signed out: pending survives the login flow…
        guard.onGateChanged(RouteGate.loading, RouteGate.signedOut);
        expect(go(RouteGate.signedOut, '/splash'), AppRoutes.welcome);
        expect(guard.pendingLocation, '/sos/alert/a1');
        // …and is consumed exactly once when the session becomes complete.
        guard.onGateChanged(RouteGate.signedOut, RouteGate.ready);
        expect(go(RouteGate.ready, '/login'), '/sos/alert/a1');
        expect(guard.pendingLocation, isNull);
        expect(go(RouteGate.ready, '/login'), AppRoutes.home);
      },
    );

    test('public locations are never remembered', () {
      go(RouteGate.loading, '/login');
      expect(guard.pendingLocation, isNull);
      guard.remember('/verify-email');
      guard.remember('/');
      expect(guard.pendingLocation, isNull);
      guard.remember('/tasks/new?assigneeId=m1');
      expect(guard.pendingLocation, '/tasks/new?assigneeId=m1');
    });

    test('signing out forgets the pending location', () {
      guard.remember('/tasks/1');
      guard.onGateChanged(RouteGate.ready, RouteGate.signedOut);
      expect(guard.pendingLocation, isNull);

      guard.remember('/tasks/1');
      guard.onGateChanged(RouteGate.needsVerification, RouteGate.signedOut);
      expect(guard.pendingLocation, isNull);
    });
  });
}
