import 'package:go_router/go_router.dart';

import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/features/sos/presentation/screens/sos_alert_screen.dart';
import 'package:family_hub/features/sos/presentation/screens/sos_history_screen.dart';

/// Full-screen routes of the SOS feature (registered top-level by
/// `goRouterProvider`, so they cover the navigation bar). The SOS tab
/// itself (`/sos` → `SosScreen`) is a shell branch.
///
/// * `/sos/history` → [SosHistoryScreen]
/// * `/sos/alert/:id` → [SosAlertScreen] (also the route of `sos` /
///   `sos_resolved` pushes)
List<RouteBase> get sosRoutes => [
  // Static segment before the `:id` route.
  GoRoute(
    path: AppRoutes.sosHistory,
    builder: (context, state) => const SosHistoryScreen(),
  ),
  GoRoute(
    path: AppRoutes.sosAlertPath,
    builder: (context, state) =>
        SosAlertScreen(alertId: state.pathParameters[AppRoutes.idParam] ?? ''),
  ),
];
