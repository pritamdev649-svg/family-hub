import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/features/dashboard/presentation/dashboard_layout.dart';
import 'package:family_hub/features/dashboard/presentation/dashboard_navigation.dart';
import 'package:family_hub/features/ledger/domain/ledger_entry.dart';

/// Shortcuts to the most common actions: add a task, record an expense,
/// post a notice and open the emergency cards. Colourful [ActionTile]s in
/// each module's accent, one row of four on wide screens, two by two on
/// phones.
///
/// Every member may use all four (members create tasks and entries for
/// themselves; the forms apply the rules), so nothing is hidden by role.
class DashboardQuickActions extends StatelessWidget {
  const DashboardQuickActions({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final actions = [
      ActionTile(
        icon: AppIcons.task,
        label: l10n.dashboardActionAddTask,
        accent: AppAccents.tasks,
        onTap: () => context.openFromDashboard(AppRoutes.taskNew()),
      ),
      ActionTile(
        icon: AppIcons.expense,
        label: l10n.dashboardActionAddExpense,
        accent: AppAccent.orange,
        onTap: () => context.openFromDashboard(
          AppRoutes.ledgerEntryNew(type: LedgerType.expense.name),
        ),
      ),
      ActionTile(
        icon: AppIcons.notice,
        label: l10n.dashboardActionPostNotice,
        accent: AppAccents.notices,
        onTap: () => context.openFromDashboard(AppRoutes.noticeNew),
      ),
      ActionTile(
        icon: AppIcons.emergencyCard,
        label: l10n.dashboardActionEmergencyCards,
        accent: AppAccents.emergency,
        onTap: () => context.openFromDashboard(AppRoutes.emergencyCards),
      ),
    ];

    return Semantics(
      container: true,
      label: l10n.dashboardQuickActionsTitle,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = DashboardLayout.isWide(context, constraints.maxWidth);
          return DashboardLayout.grid(columns: wide ? 4 : 2, children: actions);
        },
      ),
    );
  }
}
