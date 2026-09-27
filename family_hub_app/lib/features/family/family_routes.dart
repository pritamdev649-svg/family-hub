import 'package:go_router/go_router.dart';

import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/features/family/presentation/screens/family_settings_screen.dart';
import 'package:family_hub/features/family/presentation/screens/member_detail_screen.dart';
import 'package:family_hub/features/family/presentation/screens/member_form_screen.dart';
import 'package:family_hub/features/family/presentation/screens/members_screen.dart';

/// Full-screen routes of the family feature (registered top-level by
/// `goRouterProvider`). `/members/new` is listed before `/members/:id`.
List<RouteBase> get familyRoutes => [
  GoRoute(
    path: AppRoutes.members,
    builder: (context, state) => const MembersScreen(),
  ),
  GoRoute(
    path: AppRoutes.memberNew,
    builder: (context, state) => const MemberFormScreen(),
  ),
  GoRoute(
    path: AppRoutes.memberDetailPath,
    builder: (context, state) => MemberDetailScreen(memberId: _memberId(state)),
  ),
  GoRoute(
    path: AppRoutes.memberEditPath,
    builder: (context, state) => MemberFormScreen(memberId: _memberId(state)),
  ),
  GoRoute(
    path: AppRoutes.familySettings,
    builder: (context, state) => const FamilySettingsScreen(),
  ),
];

/// `:id` of the location (an unknown / blank id answers `NOT_FOUND`).
String _memberId(GoRouterState state) =>
    state.pathParameters[AppRoutes.idParam] ?? '';
