import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/shared/models/session_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where the session allows the user to be. Derived from
/// `sessionControllerProvider` by `routeGateProvider` (app_router.dart); the
/// router only refreshes when this changes.
enum RouteGate {
  /// The saved session is being restored -> splash.
  loading,

  /// Nobody is signed in -> welcome / login / register / forgot password.
  signedOut,

  /// Signed in, email not verified -> verify-email.
  needsVerification,

  /// Signed in and verified, but not in a family -> family-setup.
  needsFamily,

  /// Complete session -> the app.
  ready,
}

RouteGate routeGateOf(AsyncValue<SessionState> session) {
  final state = session.value;
  if (state == null) {
    // No value yet: still restoring (or retrying). A hard error without any
    // cached session means we cannot know who the user is -> signed out.
    return session.isLoading ? RouteGate.loading : RouteGate.signedOut;
  }
  if (!state.isSignedIn) return RouteGate.signedOut;
  if (state.needsEmailVerification) return RouteGate.needsVerification;
  if (state.needsFamily) return RouteGate.needsFamily;
  return RouteGate.ready;
}

/// Redirect rules of the app (docs/05-FLUTTER_GUIDE.md §9) plus a pending
/// deep link: a protected location requested before the session is complete
/// (cold start, notification tap while signed out) is opened as soon as the
/// session becomes complete instead of the default `/home`.
class RouteGuard {
  String? _pending;

  /// The location that will be opened once the session is complete.
  String? get pendingLocation => _pending;

  /// Remembers [location] (a sanitised in-app location) to open after
  /// sign-in / verification / family setup. Public locations are ignored.
  void remember(String location) {
    final uri = Uri.tryParse(location);
    if (uri == null) return;
    final path = uri.path.isEmpty ? '/' : uri.path;
    if (path == '/' || AppRoutes.isPublic(path)) return;
    _pending = location;
  }

  void clearPending() => _pending = null;

  String? _takePending() {
    final pending = _pending;
    _pending = null;
    return pending;
  }

  /// Call when the gate changes. Signing out forgets the pending location so
  /// the next account does not land on the previous account's screen.
  void onGateChanged(RouteGate? previous, RouteGate next) {
    if (next == RouteGate.signedOut && previous != RouteGate.loading) {
      clearPending();
    }
  }

  /// The go_router `redirect`: returns the location to go to, or `null` to
  /// stay on [uri].
  String? redirect(RouteGate gate, Uri uri) {
    final path = _normalize(uri.path);
    switch (gate) {
      case RouteGate.loading:
        if (path == AppRoutes.splash) return null;
        remember(uri.toString());
        return AppRoutes.splash;
      case RouteGate.signedOut:
        return AppRoutes.isSignedOutPath(path) ? null : AppRoutes.welcome;
      case RouteGate.needsVerification:
        return path == AppRoutes.verifyEmail ? null : AppRoutes.verifyEmail;
      case RouteGate.needsFamily:
        return path == AppRoutes.familySetup ? null : AppRoutes.familySetup;
      case RouteGate.ready:
        if (path == '/' || AppRoutes.isPublic(path)) {
          return _takePending() ?? AppRoutes.home;
        }
        return null;
    }
  }

  static String _normalize(String path) {
    if (path.isEmpty) return '/';
    if (path.length > 1 && path.endsWith('/')) {
      return path.substring(0, path.length - 1);
    }
    return path;
  }
}

/// Single [RouteGuard] shared by the router and the deep-link opener.
final routeGuardProvider = Provider<RouteGuard>((ref) => RouteGuard());
