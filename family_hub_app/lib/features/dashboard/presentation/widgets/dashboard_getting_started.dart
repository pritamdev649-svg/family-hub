import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/dashboard/domain/dashboard_data.dart';
import 'package:family_hub/features/dashboard/presentation/dashboard_navigation.dart';

/// Checklist for a new family ([DashboardData.isNewFamily]): add members,
/// create the first task, set a savings goal (admins) and post the first
/// notice. Finished steps are ticked; open steps are tappable shortcuts.
/// Hidden once every step is done.
class DashboardGettingStarted extends StatelessWidget {
  const DashboardGettingStarted({super.key, required this.data});

  final DashboardData data;

  /// Whether the card has anything to show for [data].
  static bool isVisibleFor(DashboardData data) =>
      data.isNewFamily && _steps(data).any((s) => !s.done);

  static List<_Step> _steps(DashboardData data) => [
    if (data.isAdmin)
      _Step(
        icon: AppIcons.addMember,
        label: (l10n) => l10n.dashboardStepAddMembers,
        location: AppRoutes.memberNew,
        done: data.hasOtherMembers,
      ),
    _Step(
      icon: AppIcons.task,
      label: (l10n) => l10n.dashboardStepFirstTask,
      location: AppRoutes.taskNew(),
      done: data.hasAnyTasks,
    ),
    if (data.isAdmin)
      _Step(
        icon: AppIcons.goal,
        label: (l10n) => l10n.dashboardStepFirstGoal,
        location: AppRoutes.goalNew,
        done: data.goals.isNotEmpty,
      ),
    _Step(
      icon: AppIcons.notice,
      label: (l10n) => l10n.dashboardStepFirstNotice,
      location: AppRoutes.noticeNew,
      done: data.latestNotices.isNotEmpty,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic = context.semanticColors;

    return AppCard(
      color: scheme.primaryContainer,
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              l10n.dashboardGettingStartedTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                color: scheme.onPrimaryContainer,
              ),
            ),
          ),
          AppGap.xs,
          Text(
            l10n.dashboardGettingStartedMessage,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onPrimaryContainer,
            ),
          ),
          AppGap.sm,
          for (final step in _steps(data))
            _StepRow(
              step: step,
              doneColor: semantic.success,
              color: scheme.onPrimaryContainer,
            ),
        ],
      ),
    );
  }
}

class _Step {
  const _Step({
    required this.icon,
    required this.label,
    required this.location,
    required this.done,
  });

  final IconData icon;
  final String Function(AppLocalizations l10n) label;
  final String location;
  final bool done;
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.step,
    required this.doneColor,
    required this.color,
  });

  final _Step step;
  final Color doneColor;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final label = step.label(l10n);
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppSizes.minTapTarget),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            Icon(
              step.done ? AppIcons.taskDone : step.icon,
              size: AppSizes.iconMd,
              color: step.done ? doneColor : color,
            ),
            AppGap.hMd,
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: color,
                  decoration: step.done ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            if (!step.done)
              Icon(AppIcons.chevron, size: AppSizes.iconMd, color: color),
          ],
        ),
      ),
    );

    if (step.done) {
      return Semantics(
        label: l10n.dashboardStepDone(label),
        excludeSemantics: true,
        child: row,
      );
    }
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: AppRadius.brMd,
        onTap: () => context.openFromDashboard(step.location),
        child: row,
      ),
    );
  }
}
