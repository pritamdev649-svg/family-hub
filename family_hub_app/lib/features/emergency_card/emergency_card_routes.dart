import 'package:go_router/go_router.dart';

import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/features/emergency_card/presentation/screens/emergency_card_form_screen.dart';
import 'package:family_hub/features/emergency_card/presentation/screens/emergency_card_screen.dart';
import 'package:family_hub/features/emergency_card/presentation/screens/emergency_cards_screen.dart';

/// Full-screen routes of the emergency card feature (registered top-level by
/// `goRouterProvider`, so they cover the navigation bar):
///
/// * `/emergency-cards` → [EmergencyCardsScreen]
/// * `/emergency-cards/:memberId` → [EmergencyCardScreen]
/// * `/emergency-cards/:memberId/edit` → [EmergencyCardFormScreen]
///
/// A missing / blank `memberId` reaches the screens as `''`, which the
/// repository rejects as `NOT_FOUND` (shown as an error with retry).
List<RouteBase> get emergencyCardRoutes => [
  GoRoute(
    path: AppRoutes.emergencyCards,
    builder: (context, state) => const EmergencyCardsScreen(),
  ),
  GoRoute(
    path: AppRoutes.emergencyCardEditPath,
    builder: (context, state) =>
        EmergencyCardFormScreen(memberId: _memberId(state)),
  ),
  GoRoute(
    path: AppRoutes.emergencyCardPath,
    builder: (context, state) =>
        EmergencyCardScreen(memberId: _memberId(state)),
  ),
];

String _memberId(GoRouterState state) =>
    state.pathParameters[AppRoutes.memberIdParam]?.trim() ?? '';
