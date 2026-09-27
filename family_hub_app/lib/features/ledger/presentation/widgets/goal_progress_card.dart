import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/utils/formatters.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/ledger/domain/savings_goal.dart';
import 'package:family_hub/features/ledger/presentation/ledger_labels.dart';
import 'package:family_hub/features/ledger/presentation/ledger_open_guard.dart';
import 'package:family_hub/features/ledger/presentation/widgets/on_gradient.dart';

/// A savings goal as a solid gradient "payment card": title, saved of
/// target, a white progress bar, the deadline and the percentage, in white
/// on the goal's colour. Public: used in the Money tab's goal carousel and
/// on the dashboard.
///
/// [accent] picks the card colour; by default each goal gets a stable one
/// of pink / violet / teal ([SavingsGoalStyle.cardAccent]). Tapping opens
/// the goal (`AppRoutes.goalDetail`, once per tap burst) unless [onTap] is
/// given.
///
/// Sizes itself to its content (no fixed height), so it works in vertical
/// lists and — wrapped in a fixed width — in horizontal carousels.
class GoalProgressCard extends ConsumerStatefulWidget {
  const GoalProgressCard(this.goal, {super.key, this.onTap, this.accent});

  final SavingsGoal goal;
  final VoidCallback? onTap;
  final AppAccent? accent;

  @override
  ConsumerState<GoalProgressCard> createState() => _GoalProgressCardState();
}

class _GoalProgressCardState extends ConsumerState<GoalProgressCard>
    with LedgerOpenGuard {
  void _open() =>
      guardedOpen(() => context.push(AppRoutes.goalDetail(widget.goal.id)));

  @override
  Widget build(BuildContext context) {
    final goal = widget.goal;
    final l10n = context.l10n;
    final fmt = ref.watch(fmtProvider);
    final theme = Theme.of(context);
    final accent = widget.accent ?? goal.cardAccent;
    final deadline = goalDeadlineLabel(goal, l10n, fmt);
    final overdue = goal.isOverdue();

    return GradientCard(
      gradient: AppGradients.of(accent),
      glowColor: accent.base,
      padding: AppSpacing.card,
      onTap: widget.onTap ?? _open,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(child: GlassIcon(icon: goal.status.cardIcon)),
              const Spacer(),
              if (!goal.isActive)
                Flexible(
                  flex: 3,
                  child: GlassChip(
                    label: goal.status.label(l10n),
                    icon: goal.status.icon,
                  ),
                ),
            ],
          ),
          AppGap.lg,
          Text(
            goal.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(color: Colors.white),
          ),
          AppGap.xxs,
          Text(
            l10n.ledgerGoalSavedOfTarget(
              fmt.money(goal.savedAmount),
              fmt.money(goal.targetAmount),
            ),
            style: theme.textTheme.bodySmall
                ?.merge(AppTypography.tabularFigures)
                .copyWith(color: onGradientMuted),
          ),
          AppGap.md,
          OnGradientProgressBar(value: goal.progress),
          AppGap.sm,
          Row(
            children: [
              if (deadline != null) ...[
                Icon(
                  overdue ? AppIcons.warning : AppIcons.dueDate,
                  size: AppSizes.iconXs,
                  color: onGradientMuted,
                ),
                AppGap.hXs,
                Expanded(
                  child: Text(
                    deadline,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: onGradientMuted,
                    ),
                  ),
                ),
                AppGap.hSm,
              ] else
                const Spacer(),
              Text(
                fmt.percent(goal.progress),
                style: theme.textTheme.labelLarge
                    ?.merge(AppTypography.tabularFigures)
                    .copyWith(color: Colors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

extension on GoalStatus {
  /// Icon on the card's frosted square.
  IconData get cardIcon => switch (this) {
    GoalStatus.active => AppIcons.goal,
    GoalStatus.achieved => AppIcons.goalAchieved,
    GoalStatus.archived => AppIcons.archive,
  };
}

/// "12 days left" / "Due today" / "3 days past target date" for active goals
/// with a target date, "Target date: Mar 15, 2027" otherwise; null without a
/// target date.
String? goalDeadlineLabel(
  SavingsGoal goal,
  AppLocalizations l10n,
  Fmt fmt, {
  DateTime? now,
}) {
  final target = goal.targetDate;
  final left = goal.daysLeft(now: now);
  if (target == null || left == null) return null;
  if (!goal.isActive) return l10n.ledgerGoalTargetDate(fmt.date(target));
  if (left == 0) return l10n.ledgerGoalDueToday;
  if (left < 0) return l10n.ledgerGoalOverdue(-left);
  return l10n.ledgerGoalDaysLeft(left);
}
