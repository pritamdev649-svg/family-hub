import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/widgets/widgets.dart';

/// Shown instead of a goal that no longer exists (deleted by an admin, or a
/// stale link from a notification). A retry would fail the same way, so it
/// offers the Money tab instead.
class GoalNotFoundView extends StatelessWidget {
  const GoalNotFoundView({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return EmptyState(
      icon: AppIcons.goalOutlined,
      title: l10n.ledgerGoalNotFoundTitle,
      message: l10n.ledgerGoalNotFoundMessage,
      action: AppButton(
        label: l10n.ledgerBackToMoney,
        icon: AppIcons.money,
        variant: AppButtonVariant.secondary,
        expand: false,
        onPressed: () => context.go(AppRoutes.money),
      ),
    );
  }
}
