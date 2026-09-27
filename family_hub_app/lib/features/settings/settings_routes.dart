import 'package:go_router/go_router.dart';

import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/features/settings/presentation/screens/about_screen.dart';
import 'package:family_hub/features/settings/presentation/screens/appearance_screen.dart';
import 'package:family_hub/features/settings/presentation/screens/change_password_screen.dart';
import 'package:family_hub/features/settings/presentation/screens/language_screen.dart';
import 'package:family_hub/features/settings/presentation/screens/location_sharing_screen.dart';
import 'package:family_hub/features/settings/presentation/screens/privacy_screen.dart';
import 'package:family_hub/features/settings/presentation/screens/profile_screen.dart';

/// Full-screen settings routes (registered top-level by `goRouterProvider`,
/// so they cover the navigation bar). The More tab itself is a shell branch.
List<RouteBase> get settingsRoutes => [
  GoRoute(
    path: AppRoutes.settingsProfile,
    builder: (context, state) => const ProfileScreen(),
  ),
  GoRoute(
    path: AppRoutes.settingsLanguage,
    builder: (context, state) => const LanguageScreen(),
  ),
  GoRoute(
    path: AppRoutes.settingsAppearance,
    builder: (context, state) => const AppearanceScreen(),
  ),
  GoRoute(
    path: AppRoutes.settingsLocation,
    builder: (context, state) => const LocationSharingScreen(),
  ),
  GoRoute(
    path: AppRoutes.settingsPrivacy,
    builder: (context, state) => const PrivacyScreen(),
  ),
  GoRoute(
    path: AppRoutes.settingsPassword,
    builder: (context, state) => const ChangePasswordScreen(),
  ),
  GoRoute(
    path: AppRoutes.settingsAbout,
    builder: (context, state) => const AboutScreen(),
  ),
];
