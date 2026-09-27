import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/utils/formatters.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/tasks/application/task_providers.dart';
import 'package:family_hub/features/tasks/domain/family_task.dart';
import 'package:family_hub/features/tasks/domain/task_failure.dart';
import 'package:family_hub/features/tasks/presentation/task_errors.dart';
import 'package:family_hub/features/tasks/presentation/task_navigation.dart';
import 'package:family_hub/features/tasks/presentation/tasks_labels.dart';
import 'package:family_hub/features/tasks/presentation/widgets/task_glass.dart';
import 'package:family_hub/features/tasks/presentation/widgets/task_gone_view.dart';
import 'package:family_hub/features/tasks/presentation/widgets/task_meta.dart';
import 'package:family_hub/shared/models/member.dart';
import 'package:family_hub/shared/providers/shared_providers.dart';

/// `/tasks/:id` — every field of a task, its status, complete / reopen
/// (assignee or admin), edit / delete (admin or creator), who created and
/// completed it and when.
///
/// Opens with a violet gradient header behind the transparent status bar
/// (back / edit / delete, category, title and status pills); the details
/// follow in borderless cards with colourful icon badges, then the complete
/// / reopen action.
///
/// A task that no longer exists (`404` — deleted by someone else, e.g. when
/// opened from an old notification — or a malformed link, `400`) shows
/// [TaskGoneView] with a way back, also when the detail was already on
/// screen and a refresh discovers the deletion.
class TaskDetailScreen extends ConsumerWidget {
  const TaskDetailScreen({super.key, required this.taskId});

  final String taskId;

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    FamilyTask task,
  ) async {
    final l10n = context.l10n;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.tasksDeleteTitle,
      message: l10n.tasksDeleteMessage(task.title),
      confirmLabel: l10n.commonDelete,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    // A second dialog (double tap) or a change already in flight.
    final mutations = ref.read(taskControllerProvider);
    if (mutations.isBusy(task.id) || mutations.isDeleted(task.id)) return;
    try {
      await ref.read(taskControllerProvider.notifier).delete(task.id);
      if (!context.mounted) return;
      context.showSuccess(l10n.tasksDeleted);
      closeTaskScreen(context);
    } catch (e) {
      if (context.mounted) context.showTaskError(e, TaskAction.delete);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = taskByIdProvider(taskId);
    final async = ref.watch(provider);
    final mutations = ref.watch(taskControllerProvider);
    final base = async.value;
    final busy = mutations.isBusy(taskId);
    final deleted = mutations.isDeleted(taskId);
    // A refresh can discover the deletion while old data is still shown.
    final error = async.error;
    final gone =
        !async.isLoading &&
        error != null &&
        TaskFailure.of(error) == TaskFailure.gone;
    final task = base == null || deleted || gone
        ? null
        : mutations.resolve(base);
    // The task the signed-in member may edit / delete, if any.
    final editable =
        task != null &&
            ref.watch(taskPermissionsProvider.select((p) => p.canEdit(task)))
        ? task
        : null;

    return Scaffold(
      body: GradientHeaderScrollView(
        gradient: AppGradients.headerOf(AppAccents.tasks),
        onRefresh: () => ref.refresh(provider.future),
        header: _DetailHeader(
          task: task,
          busy: busy,
          onEdit: editable == null
              ? null
              : () => openTaskRoute(context, AppRoutes.taskEdit(taskId)),
          onDelete: editable == null
              ? null
              : () => _delete(context, ref, editable),
        ),
        children: [
          if (deleted || gone)
            TaskGoneView(deletedHere: deleted && !gone)
          else
            AsyncValueView<FamilyTask>(
              value: async,
              onRetry: () => ref.invalidate(provider),
              loading: const AppCard(child: LoadingView()),
              data: (base) => _TaskDetailBody(task: mutations.resolve(base)),
            ),
        ],
      ),
    );
  }
}

// ── Header ──────────────────────────────────────────────────────────────────

/// Back / edit / delete, then the category square, the title and the
/// status, priority and category pills (white on the violet gradient).
/// Without a [task] (loading, error, gone) only the back button and the
/// screen title show.
class _DetailHeader extends StatelessWidget {
  const _DetailHeader({
    required this.task,
    required this.busy,
    required this.onEdit,
    required this.onDelete,
  });

  final FamilyTask? task;
  final bool busy;

  /// `null` hides the edit / delete buttons (not allowed).
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final t = task;
    final edit = onEdit;
    final delete = onDelete;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            TaskGlassIconButton(
              icon: AppIcons.back,
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: () => closeTaskScreen(context),
            ),
            AppGap.hMd,
            Expanded(
              child: Text(
                l10n.tasksDetailTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: TaskGlass.mutedColor,
                ),
              ),
            ),
            if (edit != null) ...[
              AppGap.hSm,
              TaskGlassIconButton(
                icon: AppIcons.edit,
                tooltip: l10n.commonEdit,
                onPressed: busy ? null : edit,
              ),
            ],
            if (delete != null) ...[
              AppGap.hSm,
              TaskGlassIconButton(
                icon: AppIcons.delete,
                tooltip: l10n.commonDelete,
                onPressed: busy ? null : delete,
              ),
            ],
          ],
        ),
        if (t != null) ...[
          AppGap.xl,
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: Container(
                  width: AppSizes.badgeLg,
                  height: AppSizes.badgeLg,
                  decoration: BoxDecoration(
                    color: TaskGlass.fillColor,
                    borderRadius: AppRadius.brLg,
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    t.category.icon,
                    size: AppSizes.iconMd,
                    color: Colors.white,
                  ),
                ),
              ),
              AppGap.hMd,
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    t.title,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      decoration: t.isDone ? TextDecoration.lineThrough : null,
                      decorationColor: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
          AppGap.lg,
          _StatusPills(task: t),
          AppGap.md,
          // The slot is always there, so the header does not jump while
          // saving (the indicator only exists while busy: it animates
          // forever).
          SizedBox(
            height: AppSizes.refreshBar,
            child: busy
                ? LinearProgressIndicator(
                    minHeight: AppSizes.refreshBar,
                    color: Colors.white,
                    backgroundColor: TaskGlass.fillColor,
                    borderRadius: AppRadius.brPill,
                  )
                : null,
          ),
        ],
      ],
    );
  }
}

class _StatusPills extends StatelessWidget {
  const _StatusPills({required this.task});

  final FamilyTask task;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final (statusIcon, statusLabel) = taskStatusVisual(task, l10n);
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        TaskGlassPill(
          icon: statusIcon,
          label: statusLabel,
          emphasis: task.isOverdue,
          emphasisColor: AppAccent.rose.dark,
        ),
        TaskGlassPill(
          icon: task.priority.icon,
          label: l10n.tasksPrioritySemantics(task.priority.label(l10n)),
        ),
        TaskGlassPill(
          icon: task.category.icon,
          label: task.category.label(l10n),
        ),
      ],
    );
  }
}

// ── Body ────────────────────────────────────────────────────────────────────

class _TaskDetailBody extends ConsumerWidget {
  const _TaskDetailBody({required this.task});

  final FamilyTask task;

  static Member? _member(List<Member>? members, String? id) {
    if (members == null || id == null) return null;
    for (final m in members) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// Display name of member [id] as known by the task or the members list
  /// ("Former member" for someone who left the family).
  static String _nameOf(
    String? id,
    FamilyTask task,
    List<Member>? members,
    AppLocalizations l10n,
  ) {
    if (id == null || id.isEmpty) return l10n.commonUnknown;
    if (id == task.assigneeId && task.assigneeName.trim().isNotEmpty) {
      return task.assigneeName.trim();
    }
    if (id == task.createdById && task.createdByName.trim().isNotEmpty) {
      return task.createdByName.trim();
    }
    return taskPersonName(_member(members, id)?.name, l10n);
  }

  Future<void> _toggle(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final done = !task.isDone;
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
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final fmt = ref.watch(fmtProvider);
    final members = ref.watch(membersProvider).value;
    final myId = ref.watch(currentMemberProvider.select((m) => m?.id));
    final canComplete = ref.watch(
      taskPermissionsProvider.select((p) => p.canComplete(task)),
    );
    final busy = ref.watch(
      taskControllerProvider.select((m) => m.isBusy(task.id)),
    );
    final assignee = _member(members, task.assigneeId);
    final assigneeName = _nameOf(task.assigneeId, task, members, l10n);
    // The server refuses to reopen a task whose assignee left the family
    // (`422 details.assigneeId`); say so up front instead of failing. The API
    // sends no name for removed members, which (unlike a possibly stale
    // member list) is a reliable signal.
    final assigneeLeft =
        task.isDone && task.assigneeName.trim().isEmpty && assignee == null;
    final dueDay = task.dueDay;
    final createdAt = task.createdAt;
    final completedAt = task.completedAt;
    final updatedAt = task.updatedAt;
    // "Last updated" only when it adds information (an edit after creation
    // that is not just the completion).
    DateTime? editedAt;
    if (updatedAt != null &&
        (createdAt == null || updatedAt.difference(createdAt).inMinutes >= 1) &&
        (completedAt == null ||
            updatedAt.difference(completedAt).inMinutes.abs() >= 1)) {
      editedAt = updatedAt;
    }

    String personAt(String name, DateTime? at) => at == null
        ? name
        : l10n.tasksPersonAtTime(name, fmt.relative(at, l10n));

    final rows = <Widget>[
      _InfoRow(
        icon: AppIcons.member,
        accent: AppAccents.family,
        label: l10n.tasksInfoAssignee,
        leading: MemberAvatar(
          name: assigneeName,
          avatarUrl: assignee?.avatarUrl,
          radius: AppSizes.avatarSm,
        ),
        value: task.assigneeId == myId
            ? l10n.tasksAssigneeMe(assigneeName)
            : assigneeName,
      ),
      _InfoRow(
        icon: task.isOverdue ? AppIcons.overdue : AppIcons.dueDate,
        accent: task.isOverdue ? AppAccent.rose : AppAccents.tasks,
        label: l10n.tasksInfoDue,
        value: dueDay == null
            ? l10n.tasksInfoNoDueDate
            : fmt.weekdayDate(dueDay),
        detail: dueDay == null ? null : dueDayRelative(dueDay, l10n),
        valueColor: dueDay == null ? null : dueColor(context, task),
      ),
      _InfoRow(
        icon: AppIcons.edit,
        accent: AppAccents.brand,
        label: l10n.tasksInfoCreatedBy,
        value: personAt(
          _nameOf(task.createdById, task, members, l10n),
          createdAt,
        ),
        detail: createdAt == null ? null : fmt.dateTime(createdAt),
      ),
      if (task.isDone)
        _InfoRow(
          icon: AppIcons.taskDone,
          accent: AppAccents.success,
          label: l10n.tasksInfoCompletedBy,
          value: personAt(
            _nameOf(task.completedById, task, members, l10n),
            completedAt,
          ),
          detail: completedAt == null ? null : fmt.dateTime(completedAt),
        ),
      if (editedAt != null)
        _InfoRow(
          icon: AppIcons.history,
          accent: AppAccents.settings,
          label: l10n.tasksInfoUpdated,
          value: fmt.relative(editedAt, l10n),
          detail: fmt.dateTime(editedAt),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The first card overlaps the header's rounded bottom edge.
        if (task.description case final description?) ...[
          AppCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ExcludeSemantics(
                  child: IconBadge(
                    icon: AppIcons.notes,
                    accent: AppAccents.tasks,
                    size: AppSizes.badgeSm,
                    soft: true,
                  ),
                ),
                AppGap.hMd,
                Expanded(
                  child: SelectableText(
                    description,
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
              ],
            ),
          ),
          AppGap.md,
        ],
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: AppSizes.hairline,
                    thickness: AppSizes.hairline,
                    indent: AppSpacing.lg + AppSizes.badgeSm + AppSpacing.md,
                    endIndent: AppSpacing.lg,
                    color: context.semanticColors.border,
                  ),
                rows[i],
              ],
            ],
          ),
        ),
        AppGap.xl,
        if (canComplete && assigneeLeft)
          _Explanation(l10n.tasksReopenAssigneeGone)
        else if (canComplete)
          AppButton(
            label: task.isDone ? l10n.tasksReopen : l10n.tasksMarkDone,
            icon: task.isDone ? AppIcons.reopen : AppIcons.check,
            variant: task.isDone
                ? AppButtonVariant.tonal
                : AppButtonVariant.primary,
            isLoading: busy,
            onPressed: () => _toggle(context, ref),
          )
        else
          _Explanation(l10n.tasksCompleteNotAllowed(assigneeName)),
      ],
    );
  }
}

/// Soft violet note with an info icon, shown where an action is not
/// available.
class _Explanation extends StatelessWidget {
  const _Explanation(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shades = context.accent(AppAccents.tasks);
    return AppCard(
      accent: AppAccents.tasks,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(AppIcons.info, size: AppSizes.iconSm, color: shades.foreground),
          AppGap.hSm,
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: shades.onContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Icon badge + label + value (+ optional secondary line) row of the
/// detail card.
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.accent,
    required this.label,
    required this.value,
    this.detail,
    this.leading,
    this.valueColor,
  });

  final IconData icon;
  final AppAccent accent;
  final String label;
  final String value;
  final String? detail;

  /// Shown before [value] (e.g. an avatar).
  final Widget? leading;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: IconBadge(
                icon: icon,
                accent: accent,
                size: AppSizes.badgeSm,
              ),
            ),
            AppGap.hMd,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.labelMedium?.copyWith(color: muted),
                  ),
                  AppGap.xxs,
                  Row(
                    children: [
                      if (leading != null) ...[
                        ExcludeSemantics(child: leading!),
                        AppGap.hSm,
                      ],
                      Flexible(
                        child: Text(
                          value,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: valueColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (detail != null) ...[
                    AppGap.xxs,
                    Text(
                      detail!,
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
