import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/router/route_error_screen.dart';
import 'package:family_hub/core/router/route_guard.dart';
import 'package:family_hub/features/auth/auth_routes.dart';
import 'package:family_hub/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:family_hub/features/emergency_card/emergency_card_routes.dart';
import 'package:family_hub/features/family/family_routes.dart';
import 'package:family_hub/features/home/home_shell.dart';
import 'package:family_hub/features/home/splash_screen.dart';
import 'package:family_hub/features/ledger/ledger_routes.dart';
import 'package:family_hub/features/ledger/presentation/screens/money_screen.dart';
import 'package:family_hub/features/notices/notices_routes.dart';
import 'package:family_hub/features/settings/presentation/screens/more_screen.dart';
import 'package:family_hub/features/settings/settings_routes.dart';
import 'package:family_hub/features/sos/presentation/screens/sos_screen.dart';
import 'package:family_hub/features/sos/sos_routes.dart';
import 'package:family_hub/features/tasks/presentation/screens/tasks_screen.dart';
import 'package:family_hub/features/tasks/tasks_routes.dart';
import 'package:family_hub/shared/session/session_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

export 'package:family_hub/core/router/app_routes.dart';
export 'package:family_hub/core/router/route_guard.dart' show RouteGate;

/// Current [RouteGate]. Only notifies when the gate actually changes, so
/// profile edits etc. never re-run the router redirect.
final routeGateProvider = Provider<RouteGate>(
  (ref) => routeGateOf(ref.watch(sessionControllerProvider)),
);

/// Navigator of every top-level (full-screen) route.
final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// The app's single [GoRouter].
///
/// * `redirect` implements the session gates (see [RouteGuard]).
/// * `refreshListenable` is bridged to `sessionControllerProvider` through
///   [routeGateProvider], so the redirect re-runs only when the gate changes
///   (signed in / out, verified, joined a family) — never on profile edits.
/// * Tabs live in a `StatefulShellRoute.indexedStack` ([HomeShell]); feature
///   screens are top-level routes that cover the navigation bar.
final goRouterProvider = Provider<GoRouter>((ref) {
  final guard = ref.watch(routeGuardProvider);
  final gate = ValueNotifier<RouteGate>(ref.read(routeGateProvider));
  ref.listen<RouteGate>(routeGateProvider, (previous, next) {
    guard.onGateChanged(previous, next);
    gate.value = next;
  });

  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoutes.splash,
    refreshListenable: gate,
    // Read the provider (not `gate.value`) so a navigation that happens
    // between a session change and the listener callback sees the new gate.
    redirect: (context, state) =>
        guard.redirect(ref.read(routeGateProvider), state.uri),
    errorBuilder: (context, state) => RouteErrorScreen(error: state.error),
    routes: [
      GoRoute(path: '/', redirect: (context, state) => AppRoutes.splash),
      GoRoute(
        path: AppRoutes.splash,
        pageBuilder: (context, state) =>
            NoTransitionPage(key: state.pageKey, child: const SplashScreen()),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            HomeShell(navigationShell: navigationShell),
        branches: [
          _tab(AppRoutes.home, const DashboardScreen()),
          _tab(AppRoutes.tasks, const TasksScreen()),
          _tab(AppRoutes.sos, const SosScreen()),
          _tab(AppRoutes.money, const MoneyScreen()),
          _tab(AppRoutes.more, const MoreScreen()),
        ],
      ),
      ...authRoutes,
      ...taskRoutes,
      ...ledgerRoutes,
      ...familyRoutes,
      ...noticeRoutes,
      ...emergencyCardRoutes,
      ...sosRoutes,
      ...settingsRoutes,
    ],
  );

  ref.onDispose(() {
    router.dispose();
    gate.dispose();
  });
  return router;
});

StatefulShellBranch _tab(String path, Widget screen) {
  return StatefulShellBranch(
    routes: [
      GoRoute(
        path: path,
        pageBuilder: (context, state) =>
            NoTransitionPage(key: state.pageKey, child: screen),
      ),
    ],
  );
}

/// Opens locations that come from outside the widget tree (push notification
/// taps, including the cold-start tap).
class DeepLinkOpener {
  DeepLinkOpener(this._ref);

  final Ref _ref;

  /// Validates [rawLocation] and navigates to it. When the session is not
  /// complete yet the location is remembered and opened right after sign-in /
  /// session restore. Returns `false` if the location was rejected.
  bool open(String rawLocation) {
    final location = AppRoutes.sanitizeLocation(rawLocation);
    if (location == null) return false;

    if (_ref.read(routeGateProvider) != RouteGate.ready) {
      _ref.read(routeGuardProvider).remember(location);
      return true;
    }

    final router = _ref.read(goRouterProvider);
    final current = router.routerDelegate.currentConfiguration.uri.toString();
    if (current == location) return true; // already showing it

    if (AppRoutes.isTabRoot(location)) {
      router.go(location);
    } else {
      router.push(location);
    }
    return true;
  }
}

final deepLinkOpenerProvider = Provider<DeepLinkOpener>(DeepLinkOpener.new);
