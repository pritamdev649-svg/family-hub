import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/utils/formatters.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/tasks/domain/family_task.dart';
import 'package:family_hub/features/tasks/presentation/tasks_labels.dart';

/// Whole calendar days from today to [day] (negative = in the past).
/// Computed on UTC dates, so daylight-saving changes never skew it.
int daysFromToday(DateTime day, {DateTime? now}) {
  final t = (now ?? DateTime.now()).toLocal();
  final d = day.toLocal();
  return DateTime.utc(
    d.year,
    d.month,
    d.day,
  ).difference(DateTime.utc(t.year, t.month, t.day)).inDays;
}

/// Short label of a due day: `Today` / `Tomorrow` / `Yesterday`, else the
/// weekday + date (`Sat, Sep 26`, with the year when not the current one).
String dueDayLabel(
  DateTime day,
  Fmt fmt,
  AppLocalizations l10n, {
  DateTime? now,
}) {
  return switch (daysFromToday(day, now: now)) {
    0 => l10n.commonToday,
    1 => l10n.commonTomorrow,
    -1 => l10n.commonYesterday,
    _ => fmt.weekdayDate(day),
  };
}

/// Relative distance of a due day: `Today`, `Tomorrow`, `Yesterday`,
/// `in 3 days`, `3 days ago`.
String dueDayRelative(DateTime day, AppLocalizations l10n, {DateTime? now}) {
  final days = daysFromToday(day, now: now);
  return switch (days) {
    0 => l10n.commonToday,
    1 => l10n.commonTomorrow,
    -1 => l10n.commonYesterday,
    > 1 => l10n.tasksDueInDays(days),
    _ => l10n.commonDaysAgo(-days),
  };
}

/// Display name of a person referenced by a task. The API sends `null`
/// (parsed as blank) for members who have left the family.
String taskPersonName(String? name, AppLocalizations l10n) {
  final trimmed = name?.trim() ?? '';
  return trimmed.isEmpty ? l10n.tasksFormerMember : trimmed;
}

/// Colour of a due date: error red when overdue, the tasks violet when due
/// today, secondary text otherwise.
Color dueColor(BuildContext context, FamilyTask task) {
  final scheme = Theme.of(context).colorScheme;
  if (task.isOverdue) return scheme.error;
  if (task.isPending && task.isDueToday) {
    return context.accent(AppAccents.tasks).foreground;
  }
  return scheme.onSurfaceVariant;
}

/// Icon and label of [task]'s state: Done, Overdue or Pending.
(IconData, String) taskStatusVisual(FamilyTask task, AppLocalizations l10n) {
  if (task.isDone) return (AppIcons.taskDone, task.status.label(l10n));
  if (task.isOverdue) return (AppIcons.overdue, l10n.tasksStatusOverdue);
  return (AppIcons.taskPending, task.status.label(l10n));
}

/// Calendar icon + due day of [task] (nothing without a due date). Overdue
/// dates are red with an "overdue" icon; screen readers hear "Overdue, was
/// due …" / "Due …".
class TaskDueLabel extends ConsumerWidget {
  const TaskDueLabel(this.task, {super.key});

  final FamilyTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = task.dueDay;
    if (day == null) return const SizedBox.shrink();
    final l10n = context.l10n;
    final fmt = ref.watch(fmtProvider);
    final label = dueDayLabel(day, fmt, l10n);
    final overdue = task.isOverdue;
    final color = dueColor(context, task);
    return Semantics(
      label: overdue
          ? l10n.tasksOverdueSemantics(label)
          : l10n.tasksDueSemantics(label),
      excludeSemantics: true,
      child: _IconText(
        icon: overdue ? AppIcons.overdue : AppIcons.dueDate,
        text: label,
        color: color,
      ),
    );
  }
}

/// Small coloured priority pill (high rose, medium amber, low sky) with
/// the priority icon; screen readers hear "High priority".
class TaskPriorityPill extends StatelessWidget {
  const TaskPriorityPill(this.priority, {super.key});

  final TaskPriority priority;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final label = priority.label(l10n);
    return Semantics(
      label: l10n.tasksPrioritySemantics(label),
      excludeSemantics: true,
      child: StatusChip(
        label: label,
        icon: priority.icon,
        color: priority.color(context),
      ),
    );
  }
}

/// Assignee avatar + name ("Former member" when they left the family).
class TaskAssigneeLabel extends StatelessWidget {
  const TaskAssigneeLabel({super.key, required this.name, this.avatarUrl});

  final String name;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final display = taskPersonName(name, l10n);
    final theme = Theme.of(context);
    return Semantics(
      label: l10n.tasksAssignedToSemantics(display),
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          MemberAvatar(
            name: display,
            avatarUrl: avatarUrl,
            radius: AppSizes.iconSm / 2,
          ),
          AppGap.hXs,
          Flexible(
            child: Text(
              display,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IconText extends StatelessWidget {
  const _IconText({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: AppSizes.iconXs, color: color),
        AppGap.hXs,
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}
