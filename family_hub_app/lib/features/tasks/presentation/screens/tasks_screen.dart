import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/tasks/application/task_providers.dart';
import 'package:family_hub/features/tasks/application/tasks_filter.dart';
import 'package:family_hub/features/tasks/domain/family_task.dart';
import 'package:family_hub/features/tasks/domain/task_grouping.dart';
import 'package:family_hub/features/tasks/domain/task_query.dart';
import 'package:family_hub/features/tasks/presentation/task_navigation.dart';
import 'package:family_hub/features/tasks/presentation/tasks_header_stats.dart';
import 'package:family_hub/features/tasks/presentation/tasks_labels.dart';
import 'package:family_hub/features/tasks/presentation/widgets/task_choice_chip.dart';
import 'package:family_hub/features/tasks/presentation/widgets/task_state_card.dart';
import 'package:family_hub/features/tasks/presentation/widgets/task_section_label.dart';
import 'package:family_hub/features/tasks/presentation/widgets/task_tile.dart';
import 'package:family_hub/features/tasks/presentation/widgets/task_view_switcher.dart';
import 'package:family_hub/features/tasks/presentation/widgets/tasks_header.dart';
import 'package:family_hub/shared/models/member.dart';
import 'package:family_hub/shared/providers/shared_providers.dart';

/// The Tasks tab.
///
/// A full-bleed violet header behind the transparent status bar (date,
/// title, pending / overdue / done-this-week counters and the weekly
/// progress), then — overlapping the header — a card with the list's count
/// and the **My tasks** / **Family** / **Done** switcher, sideways-scrolling
/// due-date chips (All / Overdue / Today / This week) and member chips
/// (Family and Done), and the tasks grouped into Overdue / Today / Upcoming /
/// No due date (coloured dots) with "load more" pagination. Header, filters
/// and list scroll together; pull to refresh; a violet "New task" button
/// floats above the navigation bar.
class TasksScreen extends ConsumerWidget {
  const TasksScreen({super.key});

  /// Unique hero tag: every tab of the shell may have its own FAB.
  static const _fabHeroTag = 'tasks-screen-fab';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myId = ref.watch(currentMemberProvider.select((m) => m?.id));
    final canCreate = ref.watch(
      taskPermissionsProvider.select((p) => p.canCreate),
    );
    final members = ref.watch(membersProvider).value;
    var filter = ref.watch(tasksFilterProvider);
    // A member filter for someone who left the family falls back to everyone.
    final memberId = filter.memberId;
    if (memberId != null &&
        members != null &&
        !members.any((m) => m.id == memberId)) {
      filter = filter.copyWith(memberId: () => null);
    }

    return _ForegroundRefresh(
      child: Scaffold(
        floatingActionButton: canCreate
            ? _NewTaskButton(
                heroTag: _fabHeroTag,
                onPressed: () => _openNewTask(context, filter),
              )
            : null,
        // The gradient header replaces the app bar and runs behind the
        // transparent status bar.
        body: _TasksBody(
          filter: filter,
          members: members,
          myId: myId,
          canCreate: canCreate,
        ),
      ),
    );
  }
}

/// Keeps the Tasks tab current when the app returns to the foreground:
/// re-checks the day (timers can fire late after the phone slept) and
/// refetches task data other members may have changed meanwhile, at most once
/// per [taskResumeRefreshInterval].
class _ForegroundRefresh extends ConsumerStatefulWidget {
  const _ForegroundRefresh({required this.child});

  final Widget child;

  @override
  ConsumerState<_ForegroundRefresh> createState() => _ForegroundRefreshState();
}

class _ForegroundRefreshState extends ConsumerState<_ForegroundRefresh> {
  late final AppLifecycleListener _lifecycle;
  late DateTime _lastRefresh;

  @override
  void initState() {
    super.initState();
    _lastRefresh = ref.read(taskClockProvider)();
    _lifecycle = AppLifecycleListener(onResume: _onResume);
  }

  void _onResume() {
    if (!mounted) return;
    ref.invalidate(taskTodayProvider);
    final now = ref.read(taskClockProvider)();
    final elapsed = now.difference(_lastRefresh);
    // A clock that jumped backwards counts as due.
    if (elapsed.isNegative || elapsed >= taskResumeRefreshInterval) {
      _lastRefresh = now;
      ref.markChanged({DataScope.tasks});
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Opens the new-task form, pre-selecting the filtered member.
void _openNewTask(BuildContext context, TasksFilter filter) {
  final assigneeId = filter.view == TasksView.mine ? null : filter.memberId;
  openTaskRoute(context, AppRoutes.taskNew(assigneeId: assigneeId));
}

Member? _memberById(List<Member>? members, String? id) {
  if (members == null || id == null) return null;
  for (final m in members) {
    if (m.id == id) return m;
  }
  return null;
}

/// Extended FAB painted with the tasks gradient and a soft violet glow.
class _NewTaskButton extends StatelessWidget {
  const _NewTaskButton({required this.heroTag, required this.onPressed});

  final Object heroTag;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: AppGradients.of(AppAccents.tasks),
        borderRadius: AppRadius.brLg,
        boxShadow: [
          BoxShadow(
            color: AppAccents.tasks.base.withValues(
              alpha: AppColors.glowOpacity,
            ),
            blurRadius: AppSizes.cardShadowBlur,
            offset: const Offset(0, AppSpacing.xs),
          ),
        ],
      ),
      child: FloatingActionButton.extended(
        heroTag: heroTag,
        onPressed: onPressed,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        icon: const Icon(AppIcons.add),
        label: Text(context.l10n.tasksNewTask),
      ),
    );
  }
}

// ── Body ────────────────────────────────────────────────────────────────────

class _TasksBody extends ConsumerStatefulWidget {
  const _TasksBody({
    required this.filter,
    required this.members,
    required this.myId,
    required this.canCreate,
  });

  final TasksFilter filter;
  final List<Member>? members;
  final String? myId;
  final bool canCreate;

  @override
  ConsumerState<_TasksBody> createState() => _TasksBodyState();
}

/// How far the first card slides over the header.
const double _overlap = AppSpacing.xxl;

class _TasksBodyState extends ConsumerState<_TasksBody> {
  /// How close (in logical pixels) to the end of the list the next page is
  /// requested — roughly two to three rows ahead.
  static const double _prefetchExtent = AppSpacing.xxxl * 6;

  /// Page the next one was last auto-requested for: at most one automatic
  /// request per loaded page (a failed page is only retried via the button,
  /// so there is no retry storm while offline).
  Object? _autoLoadedFor;

  TaskQuery get _query => widget.filter.toQuery(widget.myId);

  Future<void> _loadMore() async {
    try {
      await ref.read(taskListProvider(_query).notifier).loadMore();
    } catch (e) {
      if (mounted) context.showError(e);
    }
  }

  bool _onScroll(ScrollNotification n, TaskListState? state) {
    if (state == null || n.depth != 0 || n.metrics.axis != Axis.vertical) {
      return false;
    }
    if (!state.hasMore || state.isLoadingMore) return false;
    if (n.metrics.extentAfter > _prefetchExtent) return false;
    if (identical(_autoLoadedFor, state.page)) return false;
    _autoLoadedFor = state.page;
    _loadMore();
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final filter = widget.filter;
    final query = _query;
    final listProvider = taskListProvider(query);
    final listAsync = ref.watch(listProvider);
    final mutations = ref.watch(taskControllerProvider);
    // Regroup (Overdue / Due today / Upcoming) when the day rolls over.
    final today = ref.watch(taskTodayProvider);

    // Header counters of the same scope (me / family / one member). The
    // lists are shared with the visible list whenever the queries match.
    final pendingProvider = taskListProvider(
      TaskQuery(assigneeId: query.assigneeId),
    );
    final doneProvider = taskListProvider(
      TaskQuery(assigneeId: query.assigneeId, status: TaskListStatus.done),
    );
    final stats = TasksHeaderStats.compute(
      pendingList: ref.watch(pendingProvider).value,
      doneList: ref.watch(doneProvider).value,
      mutations: mutations,
      today: today,
    );
    final providers = {listProvider, pendingProvider, doneProvider};

    // Refetch and keep the indicator until the new pages arrived (errors are
    // shown by AsyncValueView, AppRefreshIndicator swallows them).
    Future<void> refresh() =>
        Future.wait([for (final p in providers) ref.refresh(p.future)]);
    void retry() {
      for (final p in providers) {
        ref.invalidate(p);
      }
    }

    final member = _memberById(widget.members, filter.memberId);
    final String subtitle;
    if (filter.view == TasksView.mine ||
        (member != null && member.id == widget.myId)) {
      subtitle = l10n.tasksHeaderSubtitleMine;
    } else if (member != null) {
      subtitle = l10n.tasksHeaderSubtitleMember(member.name);
    } else {
      subtitle = l10n.tasksHeaderSubtitleFamily;
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (n) => _onScroll(n, listAsync.value),
      child: GradientHeaderScrollView(
        gradient: AppGradients.headerOf(AppAccents.tasks),
        overlap: _overlap,
        onRefresh: refresh,
        header: TasksHeader(stats: stats, subtitle: subtitle, today: today),
        children: [
          // Overlaps the header's rounded bottom edge.
          _ViewCard(
            view: filter.view,
            total: listAsync.value?.total,
            onSelected: ref.read(tasksFilterProvider.notifier).setView,
          ),
          _TasksFilters(
            filter: filter,
            members: widget.members,
            myId: widget.myId,
          ),
          AppGap.lg,
          AsyncValueView<TaskListState>(
            value: listAsync,
            onRetry: retry,
            isEmpty: (s) => !s.hasMore && mutations.apply(s.items).isEmpty,
            loading: const _TaskListSkeleton(),
            empty: _TasksEmptyState(filter: filter, member: member),
            data: (s) => _GroupedTaskList(
              state: s,
              tasks: mutations.apply(s.items),
              filter: filter,
              today: today,
              onLoadMore: _loadMore,
            ),
          ),
          // Room for the floating "New task" button above the last row.
          if (widget.canCreate)
            const SizedBox(height: AppSpacing.xxxl + AppSpacing.xxl),
        ],
      ),
    );
  }
}

// ── Filters ─────────────────────────────────────────────────────────────────

/// The card that slides over the header: the visible list's count on top,
/// the My tasks / Family / Done switcher below.
///
/// The count row is at least [_overlap] tall on purpose: that strip of the
/// card lies over the header, where taps currently reach the header instead
/// of the card (see docs/progress/rd-tasks.md), so only non-interactive
/// content goes there.
class _ViewCard extends StatelessWidget {
  const _ViewCard({
    required this.view,
    required this.total,
    required this.onSelected,
  });

  final TasksView view;

  /// Matching tasks of the visible list; `null` while loading.
  final int? total;
  final ValueChanged<TasksView> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final n = total;
    final isDone = view == TasksView.done;

    return AppCard(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.xs,
        0,
        AppSpacing.xs,
        AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _overlap),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Icon(
                    isDone ? AppIcons.doneAll : AppIcons.task,
                    size: AppSizes.iconXs,
                    color: context.accent(AppAccents.tasks).foreground,
                  ),
                  AppGap.hSm,
                  Expanded(
                    child: Text(
                      n == null
                          ? ''
                          : isDone
                          ? l10n.tasksDoneCount(n)
                          : l10n.tasksPendingCount(n),
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          TaskViewSwitcher(selected: view, onSelected: onSelected),
        ],
      ),
    );
  }
}

class _TasksFilters extends ConsumerWidget {
  const _TasksFilters({
    required this.filter,
    required this.members,
    required this.myId,
  });

  final TasksFilter filter;
  final List<Member>? members;
  final String? myId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final notifier = ref.read(tasksFilterProvider.notifier);
    final memberList = members ?? const <Member>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (filter.showsDueFilter) ...[
          AppGap.md,
          Semantics(
            container: true,
            label: l10n.tasksFilterDueLabel,
            child: _ChipRow(
              children: [
                for (final choice in TaskDueChoice.values)
                  TaskChoiceChip(
                    label: choice.label(l10n),
                    icon: choice.icon,
                    accent: choice.accent,
                    selected: filter.due == choice,
                    onSelected: () => notifier.setDue(choice),
                  ),
              ],
            ),
          ),
        ],
        if (filter.showsMemberFilter && memberList.isNotEmpty) ...[
          AppGap.md,
          _MemberFilter(
            members: memberList,
            selectedId: filter.memberId,
            myId: myId,
            onSelected: notifier.setMember,
          ),
        ],
      ],
    );
  }
}

/// Horizontally scrolling member chips ("Everyone" + each member).
class _MemberFilter extends StatelessWidget {
  const _MemberFilter({
    required this.members,
    required this.selectedId,
    required this.myId,
    required this.onSelected,
  });

  final List<Member> members;
  final String? selectedId;
  final String? myId;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Semantics(
      container: true,
      label: l10n.tasksFilterMemberLabel,
      child: _ChipRow(
        children: [
          TaskChoiceChip(
            icon: AppIcons.members,
            label: l10n.tasksFilterEveryone,
            accent: AppAccents.family,
            selected: selectedId == null,
            onSelected: () => onSelected(null),
          ),
          for (final m in members)
            TaskChoiceChip(
              avatar: ExcludeSemantics(
                child: MemberAvatar(
                  name: m.name,
                  avatarUrl: m.avatarUrl,
                  radius: AppSizes.iconSm / 2,
                ),
              ),
              label: m.id == myId ? l10n.commonMe : m.name,
              accent: AppAccents.family,
              selected: selectedId == m.id,
              onSelected: () => onSelected(m.id),
            ),
        ],
      ),
    );
  }
}

/// One horizontally scrolling row of chips. The chips scroll out to the
/// screen edges (no clipping at the content padding) for an edge-to-edge
/// look.
class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) AppGap.hSm,
            children[i],
          ],
        ],
      ),
    );
  }
}

// ── List ────────────────────────────────────────────────────────────────────

class _GroupedTaskList extends StatelessWidget {
  const _GroupedTaskList({
    required this.state,
    required this.tasks,
    required this.filter,
    required this.today,
    required this.onLoadMore,
  });

  final TaskListState state;

  /// [state]'s items with local changes applied.
  final List<FamilyTask> tasks;
  final TasksFilter filter;

  /// Local midnight of today (sections are relative to it).
  final DateTime today;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final isDoneView = filter.view == TasksView.done;
    final showAssignee = filter.view != TasksView.mine;
    // Section counters only once every page is here (else they would be
    // partial).
    final complete = !state.hasMore;

    Widget tile(FamilyTask t) =>
        TaskTile(t, key: ValueKey(t.id), showAssignee: showAssignee);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isDoneView)
          for (var i = 0; i < tasks.length; i++) ...[
            if (i > 0) AppGap.sm,
            tile(tasks[i]),
          ]
        else
          for (final group in groupTasks(tasks, now: today)) ...[
            TaskSectionLabel(
              group.section,
              count: complete ? group.tasks.length : null,
            ),
            AppGap.xs,
            for (var i = 0; i < group.tasks.length; i++) ...[
              if (i > 0) AppGap.sm,
              tile(group.tasks[i]),
            ],
            AppGap.sm,
          ],
        if (state.hasMore || state.isLoadingMore)
          _LoadMoreFooter(
            isLoading: state.isLoadingMore,
            onLoadMore: onLoadMore,
          ),
      ],
    );
  }
}

/// "Load more" button (accessible fallback for the automatic loading near
/// the end of the list) or a small spinner while the next page loads.
class _LoadMoreFooter extends StatelessWidget {
  const _LoadMoreFooter({required this.isLoading, required this.onLoadMore});

  final bool isLoading;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: ConstrainedBox(
        // Same height for spinner and button, so the list does not jump.
        constraints: const BoxConstraints(minHeight: AppSizes.minTapTarget),
        child: Center(
          child: isLoading
              ? Semantics(
                  label: l10n.commonLoading,
                  child: SizedBox.square(
                    dimension: AppSizes.spinnerSm,
                    child: CircularProgressIndicator(
                      strokeWidth: AppSizes.spinnerStroke,
                      color: context.accent(AppAccents.tasks).base,
                    ),
                  ),
                )
              : AppButton(
                  label: l10n.commonLoadMore,
                  icon: AppIcons.expand,
                  onPressed: onLoadMore,
                  variant: AppButtonVariant.text,
                  expand: false,
                ),
        ),
      ),
    );
  }
}

/// First-load placeholder: three task-shaped cards (static, so it never
/// keeps the frame scheduler busy).
class _TaskListSkeleton extends StatelessWidget {
  const _TaskListSkeleton();

  @override
  Widget build(BuildContext context) {
    final fill = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: AppColors.tintOpacity / 2);
    Widget bar(double widthFactor) => FractionallySizedBox(
      alignment: AlignmentDirectional.centerStart,
      widthFactor: widthFactor,
      child: Container(
        height: AppSpacing.md,
        decoration: BoxDecoration(color: fill, borderRadius: AppRadius.brPill),
      ),
    );

    return Semantics(
      label: context.l10n.commonLoading,
      liveRegion: true,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) AppGap.sm,
              AppCard(
                child: Row(
                  children: [
                    Container(
                      width: AppSizes.badgeMd,
                      height: AppSizes.badgeMd,
                      decoration: BoxDecoration(
                        color: fill,
                        borderRadius: AppRadius.brMd,
                      ),
                    ),
                    AppGap.hMd,
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [bar(0.7), AppGap.sm, bar(0.4)],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Empty states ────────────────────────────────────────────────────────────

class _TasksEmptyState extends ConsumerWidget {
  const _TasksEmptyState({required this.filter, required this.member});

  final TasksFilter filter;

  /// The filtered member (Family / Done views), if any.
  final Member? member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final canCreate = ref.watch(
      taskPermissionsProvider.select((p) => p.canCreate),
    );
    final name = member?.name;

    final (
      IconData icon,
      AppAccent accent,
      String title,
      String message,
    ) = switch (filter) {
      TasksFilter(view: TasksView.done) => (
        AppIcons.doneAll,
        AppAccent.emerald,
        name == null
            ? l10n.tasksEmptyDoneTitle
            : l10n.tasksEmptyDoneMemberTitle(name),
        l10n.tasksEmptyDoneMessage,
      ),
      TasksFilter(due: TaskDueChoice.overdue) => (
        AppIcons.taskDone,
        AppAccent.emerald,
        l10n.tasksEmptyOverdueTitle,
        l10n.tasksEmptyOverdueMessage,
      ),
      TasksFilter(due: TaskDueChoice.today) => (
        AppIcons.dueDate,
        AppAccents.tasks,
        l10n.tasksEmptyTodayTitle,
        l10n.tasksEmptyTodayMessage,
      ),
      TasksFilter(due: TaskDueChoice.week) => (
        AppIcons.calendar,
        AppAccent.blue,
        l10n.tasksEmptyWeekTitle,
        l10n.tasksEmptyWeekMessage,
      ),
      TasksFilter(view: TasksView.mine) => (
        AppIcons.confetti,
        AppAccents.tasks,
        l10n.tasksEmptyMineTitle,
        l10n.tasksEmptyMineMessage,
      ),
      _ => (
        AppIcons.task,
        AppAccents.tasks,
        name == null
            ? l10n.tasksEmptyFamilyTitle
            : l10n.tasksEmptyMemberTitle(name),
        l10n.tasksEmptyFamilyMessage,
      ),
    };

    final showAction = canCreate && filter.view != TasksView.done;
    return TaskStateCard(
      icon: icon,
      accent: accent,
      title: title,
      message: message,
      action: showAction
          ? AppButton(
              label: l10n.tasksNewTask,
              icon: AppIcons.add,
              variant: AppButtonVariant.tonal,
              expand: false,
              onPressed: () => _openNewTask(context, filter),
            )
          : null,
    );
  }
}
