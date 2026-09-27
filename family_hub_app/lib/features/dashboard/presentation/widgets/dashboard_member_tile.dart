import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/dashboard/domain/dashboard_data.dart';
import 'package:family_hub/features/dashboard/presentation/dashboard_navigation.dart';
import 'package:family_hub/shared/l10n/shared_labels.dart';

/// One member on the family board: avatar, name, designation and their task
/// progress (pending / overdue / done this week). Tapping opens the member.
class DashboardMemberTile extends StatelessWidget {
  const DashboardMemberTile({
    super.key,
    required this.stats,
    this.isMe = false,
  });

  final MemberStats stats;

  /// Marks the signed-in member's own card ("You").
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic = context.semanticColors;
    final member = stats.member;

    return AppCard(
      onTap: member.id.isEmpty
          ? null
          : () => context.openFromDashboard(AppRoutes.memberDetail(member.id)),
      child: MergeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The name is read from the text next to it.
            ExcludeSemantics(
              child: MemberAvatar(
                name: member.name,
                avatarUrl: member.avatarUrl,
                radius: AppSizes.avatarLg,
              ),
            ),
            AppGap.hMd,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        member.name.isEmpty ? l10n.commonUnknown : member.name,
                        style: theme.textTheme.titleSmall,
                      ),
                      if (isMe) StatusChip(label: l10n.dashboardMemberYou),
                    ],
                  ),
                  AppGap.xxs,
                  Text(
                    member.titleOrRole(l10n),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  AppGap.sm,
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      if (stats.pendingTasks == 0)
                        StatusChip(
                          label: l10n.dashboardMemberAllClear,
                          icon: AppIcons.check,
                          color: semantic.success,
                        )
                      else
                        StatusChip(
                          label: l10n.dashboardMemberPending(
                            stats.pendingTasks,
                          ),
                          icon: AppIcons.taskPending,
                          color: context.accent(AppAccents.tasks).foreground,
                        ),
                      if (stats.hasOverdue)
                        StatusChip(
                          label: l10n.dashboardMemberOverdue(
                            stats.overdueTasks,
                          ),
                          icon: AppIcons.overdue,
                          color: scheme.error,
                        ),
                      if (stats.completedThisWeek > 0)
                        StatusChip(
                          label: l10n.dashboardMemberDoneThisWeek(
                            stats.completedThisWeek,
                          ),
                          icon: AppIcons.taskDone,
                          color: semantic.success,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
