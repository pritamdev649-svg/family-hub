import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Shown by the router for unknown or malformed locations (e.g. an outdated
/// notification link). Offers a way back to the dashboard.
class RouteErrorScreen extends StatelessWidget {
  const RouteErrorScreen({super.key, this.error});

  /// The router's matching error (logged in debug builds only).
  final Object? error;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (kDebugMode && error != null) debugPrint('[Router] $error');
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: ResponsiveCenter(
          child: EmptyState(
            icon: AppIcons.warning,
            title: l10n.homeRouteNotFoundTitle,
            message: l10n.homeRouteNotFoundMessage,
            action: AppButton(
              label: l10n.homeGoHome,
              icon: AppIcons.home,
              expand: false,
              onPressed: () => context.go(AppRoutes.home),
            ),
          ),
        ),
      ),
    );
  }
}
