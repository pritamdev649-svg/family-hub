import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'package:family_hub/core/router/app_routes.dart';

/// Leaves a full-screen task route: pops it, or goes to the Tasks tab when
/// the screen was opened directly (deep link / notification) and there is
/// nothing to pop to.
void closeTaskScreen(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(AppRoutes.tasks);
  }
}

/// Opens a task route from a list, tile or button. A second quick tap (or a
/// tap during the page transition) never stacks the same screen twice: the
/// push is ignored when the router is already at [location] or this screen
/// is covered by another route.
void openTaskRoute(BuildContext context, String location) {
  final router = GoRouter.maybeOf(context);
  if (router == null) return;
  // `state` is the top-most route and is updated synchronously by `push`
  // (unlike `currentConfiguration.uri`, which stays at the base location).
  if (router.state.uri.toString() == location) return;
  if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
  router.push(location);
}
