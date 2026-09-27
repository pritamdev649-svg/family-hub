import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Navigation from the dashboard. Every entry point ignores a tap while
/// another route covers the dashboard (a quick second tap during the page
/// transition, an open sheet), so the same screen is never stacked twice.
extension DashboardNavigationX on BuildContext {
  bool get _isTopRoute => ModalRoute.of(this)?.isCurrent ?? true;

  /// Opens a full-screen route (`AppRoutes.taskNew()`, member detail, …).
  void openFromDashboard(String location) {
    final router = GoRouter.maybeOf(this);
    if (router == null || !_isTopRoute) return;
    // `state` is the top-most route and is updated synchronously by `push`.
    if (router.state.uri.toString() == location) return;
    router.push<void>(location);
  }

  /// Switches to another bottom-navigation tab (`AppRoutes.tasks`,
  /// `AppRoutes.money`).
  void goToTab(String location) {
    final router = GoRouter.maybeOf(this);
    if (router == null || !_isTopRoute) return;
    router.go(location);
  }
}
