import 'package:go_router/go_router.dart';

import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/features/auth/domain/register_args.dart';
import 'package:family_hub/features/auth/presentation/screens/family_setup_screen.dart';
import 'package:family_hub/features/auth/presentation/screens/forgot_password_screen.dart';
import 'package:family_hub/features/auth/presentation/screens/login_screen.dart';
import 'package:family_hub/features/auth/presentation/screens/register_screen.dart';
import 'package:family_hub/features/auth/presentation/screens/verify_email_screen.dart';
import 'package:family_hub/features/auth/presentation/screens/welcome_screen.dart';

/// Public and onboarding routes, registered top-level by `goRouterProvider`
/// (which also decides who may see them, see `RouteGuard`):
///
/// * signed out: `/welcome`, `/login`, `/register?mode=create|join&code=`,
///   `/forgot-password` (optional `extra`: the email typed on log-in);
/// * signed in, unverified: `/verify-email`;
/// * signed in, verified, no family: `/family-setup` (optional
///   `?mode=join&code=` like `/register`, to open an invite link).
List<RouteBase> get authRoutes => [
  GoRoute(path: AppRoutes.welcome, builder: (_, _) => const WelcomeScreen()),
  GoRoute(
    path: AppRoutes.login,
    builder: (_, state) => LoginScreen(initialEmail: _stringExtra(state)),
  ),
  GoRoute(
    path: AppRoutes.registerPath,
    builder: (_, state) =>
        RegisterScreen(args: RegisterArgs.fromQuery(state.uri.queryParameters)),
  ),
  GoRoute(
    path: AppRoutes.forgotPassword,
    builder: (_, state) =>
        ForgotPasswordScreen(initialEmail: _stringExtra(state)),
  ),
  GoRoute(
    path: AppRoutes.verifyEmail,
    builder: (_, _) => const VerifyEmailScreen(),
  ),
  GoRoute(
    path: AppRoutes.familySetup,
    builder: (_, state) => FamilySetupScreen(
      args: RegisterArgs.fromQuery(state.uri.queryParameters),
    ),
  ),
];

/// `extra` when it is a string (it is dropped on process restore / deep
/// links, so it is only ever a convenience).
String? _stringExtra(GoRouterState state) {
  final extra = state.extra;
  return extra is String && extra.trim().isNotEmpty ? extra.trim() : null;
}
