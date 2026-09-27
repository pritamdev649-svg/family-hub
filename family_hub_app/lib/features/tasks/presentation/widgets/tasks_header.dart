import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/settings/text_scale.dart';
import 'package:family_hub/core/utils/formatters.dart';
import 'package:family_hub/features/tasks/presentation/task_text_measure.dart';
import 'package:family_hub/features/tasks/presentation/tasks_header_stats.dart';
import 'package:family_hub/features/tasks/presentation/widgets/task_glass.dart';

/// Content of the full-bleed violet header of the Tasks tab (rendered inside
/// `GradientHeaderScrollView`): today's date, the "Tasks" title, a short
/// subtitle naming whose tasks are shown, three frosted counters (pending,
/// overdue, done this week) and a white weekly progress bar.
///
/// It condenses so the list stays within reach: with large text the date
/// and subtitle are left out, in landscape (short screens) the progress bar
/// too.
class TasksHeader extends ConsumerWidget {
  const TasksHeader({
    super.key,
    required this.stats,
    required this.subtitle,
    required this.today,
  });

  final TasksHeaderStats stats;
  final String subtitle;

  /// Local midnight of today.
  final DateTime today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final fmt = ref.watch(fmtProvider);

    String? count(int? n, {bool atLeast = false}) {
      if (n == null) return null;
      final text = fmt.number(n);
      return atLeast ? l10n.tasksHeaderCountAtLeast(text) : text;
    }

    final overdue = stats.overdue ?? 0;
    final compact = MediaQuery.orientationOf(context) == Orientation.landscape;
    final condensed =
        compact ||
        MediaQuery.textScalerOf(context).scale(1) >= AppTextScale.largeTextMin;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!condensed) ...[
          Row(
            children: [
              Icon(
                AppIcons.calendar,
                size: AppSizes.iconSm,
                color: TaskGlass.mutedColor,
              ),
              AppGap.hXs,
              Flexible(
                child: Text(
                  fmt.weekdayDate(today),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: TaskGlass.mutedColor,
                  ),
                ),
              ),
            ],
          ),
          AppGap.sm,
        ],
        Semantics(
          header: true,
          child: Text(
            l10n.tasksTitle,
            style: theme.textTheme.headlineMedium?.copyWith(
              color: Colors.white,
            ),
          ),
        ),
        if (!condensed) ...[
          AppGap.xs,
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: TaskGlass.mutedColor,
            ),
          ),
        ],
        condensed ? AppGap.lg : AppGap.xl,
        _Counters(
          stats: [
            TaskGlassStat(
              icon: AppIcons.taskPending,
              value: count(stats.pending),
              label: l10n.tasksStatusPending,
            ),
            TaskGlassStat(
              icon: AppIcons.overdue,
              value: count(stats.overdue, atLeast: stats.overdueAtLeast),
              label: l10n.tasksStatusOverdue,
              highlight: overdue > 0,
            ),
            TaskGlassStat(
              icon: AppIcons.doneAll,
              value: count(stats.doneThisWeek, atLeast: stats.doneAtLeast),
              label: l10n.tasksHeaderDoneThisWeek,
            ),
          ],
        ),
        if (!compact) ...[
          AppGap.lg,
          TaskGlassProgress(
            label: l10n.tasksHeaderProgress,
            value: stats.weekProgress,
          ),
        ],
      ],
    );
  }
}

/// The three counters side by side (equal heights), or — when a label word
/// would not fit a third of the width (large text, long words) — stacked as
/// full-width rows.
class _Counters extends StatelessWidget {
  const _Counters({required this.stats});

  final List<TaskGlassStat> stats;

  @override
  Widget build(BuildContext context) {
    final style = TaskGlassStat.labelStyle(Theme.of(context));
    return LayoutBuilder(
      builder: (context, constraints) {
        final gaps = AppSpacing.sm * (stats.length - 1);
        final pill = (constraints.maxWidth - gaps) / stats.length;
        final word = longestWordWidth(context, [
          for (final s in stats) s.label,
        ], style);
        if (word + 2 * TaskGlassStat.padding <= pill) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < stats.length; i++) ...[
                  if (i > 0) AppGap.hSm,
                  Expanded(child: stats[i]),
                ],
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < stats.length; i++) ...[
              if (i > 0) AppGap.sm,
              TaskGlassStat(
                icon: stats[i].icon,
                value: stats[i].value,
                label: stats[i].label,
                highlight: stats[i].highlight,
                inline: true,
              ),
            ],
          ],
        );
      },
    );
  }
}
