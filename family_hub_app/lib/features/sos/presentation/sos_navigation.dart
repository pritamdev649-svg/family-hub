import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'package:family_hub/core/router/app_routes.dart';

/// Opens a full-screen route (`AppRoutes.sosAlert(id)`,
/// `AppRoutes.sosHistory`, `AppRoutes.settingsLocation`) from the SOS
/// banner, a tile or a button.
///
/// A second quick tap (or a tap during the page transition) never stacks
/// the same screen twice: the push is ignored when the router already shows
/// [location] or the tapped screen is covered by another route.
void openSosRoute(BuildContext context, String location) {
  final router = GoRouter.maybeOf(context);
  if (router == null) return;
  // `state` is the top-most route and is updated synchronously by `push`
  // (unlike `currentConfiguration.uri`, which stays at the base location).
  if (router.state.uri.toString() == location) return;
  if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
  router.push<void>(location);
}

/// [openSosRoute] for one alert.
void openSosAlert(BuildContext context, String alertId) =>
    openSosRoute(context, AppRoutes.sosAlert(alertId));
