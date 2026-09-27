import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/tasks/application/task_providers.dart';
import 'package:family_hub/features/tasks/domain/family_task.dart';
import 'package:family_hub/features/tasks/presentation/task_errors.dart';
import 'package:family_hub/features/tasks/presentation/task_navigation.dart';
import 'package:family_hub/features/tasks/presentation/tasks_labels.dart';
import 'package:family_hub/features/tasks/presentation/widgets/task_check_button.dart';
import 'package:family_hub/features/tasks/presentation/widgets/task_meta.dart';
import 'package:family_hub/shared/models/member.dart';
import 'package:family_hub/shared/providers/shared_providers.dart';

/// One task row (public widget, also used by the dashboard), styled like a
/// modern transaction list:
///
/// * a solid [IconBadge] in the category's accent (soft once done),
/// * the title (struck through and muted when done),
/// * a meta line: due day with a thin calendar icon (red when overdue),
///   assignee avatar + name, and a small coloured priority pill,
/// * a round violet checkbox ([TaskCheckButton]) to complete / reopen when
///   the signed-in member may (assignee or admin) — optimistic, rolled back
///   with an error snackbar; otherwise a read-only status mark.
///
/// Tapping opens the task detail. Local changes of this session (optimistic
/// toggles, edits, deletions — also deletions discovered through a `404`) are
/// applied on top of [task]. Members who left the family show as "Former
/// member".
class TaskTile extends ConsumerWidget {
  const TaskTile(this.task, {super.key, this.showAssignee = true, this.onTap});

  final FamilyTask task;

  /// Hide the assignee where it is obvious (e.g. "My tasks").
  final bool showAssignee;

  /// Defaults to opening the task detail.
  final VoidCallback? onTap;

  static Member? _member(List<Member>? members, String id) {
    if (members == null) return null;
    for (final m in members) {
      if (m.id == id) return m;
    }
    return null;
  }

  Future<void> _toggle(BuildContext context, WidgetRef ref, bool done) async {
    final l10n = context.l10n;
    try {
      await ref.read(taskControllerProvider.notifier).setDone(task, done: done);
      if (!context.mounted) return;
      context.showSuccess(done ? l10n.tasksMarkedDone : l10n.tasksReopened);
    } catch (e) {
      if (context.mounted) {
        context.showTaskError(
          e,
          done ? TaskAction.complete : TaskAction.reopen,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (local, busy, deleted) = ref.watch(
      taskControllerProvider.select(
        (m) => (m.latest[task.id], m.isBusy(task.id), m.isDeleted(task.id)),
      ),
    );
    if (deleted) return const SizedBox.shrink();

    final t = TaskMutations.pick(task, local);
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final canToggle = ref.watch(
      taskPermissionsProvider.select((p) => p.canComplete(t)),
    );
    final avatarUrl = showAssignee
        ? ref.watch(
            membersProvider.select(
              (a) => _member(a.value, t.assigneeId)?.avatarUrl,
            ),
          )
        : null;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : AppDurations.normal;

    final titleStyle = (theme.textTheme.titleSmall ?? const TextStyle())
        .copyWith(
          color: t.isDone ? scheme.onSurfaceVariant : scheme.onSurface,
          decoration: t.isDone ? TextDecoration.lineThrough : null,
          decorationColor: scheme.onSurfaceVariant,
        );

    return AppCard(
      onTap: onTap ?? () => openTaskRoute(context, AppRoutes.taskDetail(t.id)),
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          IconBadge(
            icon: t.category.icon,
            accent: t.category.accent,
            soft: t.isDone,
            semanticLabel: t.category.label(l10n),
          ),
          AppGap.hMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedDefaultTextStyle(
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  style: titleStyle,
                  child: Text(
                    t.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                AppGap.xs,
                Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (t.hasDueDate) TaskDueLabel(t),
                    if (showAssignee)
                      TaskAssigneeLabel(
                        name: t.assigneeName,
                        avatarUrl: avatarUrl,
                      ),
                    TaskPriorityPill(t.priority),
                  ],
                ),
              ],
            ),
          ),
          AppGap.hXs,
          if (canToggle)
            TaskCheckButton(
              value: t.isDone,
              semanticLabel: t.isDone
                  ? l10n.tasksMarkNotDone
                  : l10n.tasksMarkDone,
              onChanged: busy ? null : (done) => _toggle(context, ref, done),
            )
          else
            TaskStatusMark(done: t.isDone, semanticLabel: t.status.label(l10n)),
        ],
      ),
    );
  }
}
