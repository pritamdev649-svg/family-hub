import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/dashboard/application/dashboard_providers.dart';
import 'package:family_hub/features/dashboard/presentation/dashboard_navigation.dart';
import 'package:family_hub/features/dashboard/presentation/widgets/dashboard_empty_card.dart';
import 'package:family_hub/features/dashboard/presentation/widgets/dashboard_getting_started.dart';
import 'package:family_hub/features/dashboard/presentation/widgets/dashboard_header.dart';
import 'package:family_hub/features/dashboard/presentation/widgets/dashboard_members_board.dart';
import 'package:family_hub/features/dashboard/presentation/widgets/dashboard_offline_notice.dart';
import 'package:family_hub/features/dashboard/presentation/widgets/dashboard_quick_actions.dart';
import 'package:family_hub/features/dashboard/presentation/widgets/dashboard_skeleton.dart';
import 'package:family_hub/features/dashboard/presentation/widgets/dashboard_status_bar.dart';
import 'package:family_hub/features/ledger/presentation/widgets/goal_progress_card.dart';
import 'package:family_hub/features/ledger/presentation/widgets/month_summary_card.dart';
import 'package:family_hub/features/notices/presentation/widgets/notice_card.dart';
import 'package:family_hub/features/sos/domain/sos_alert.dart';
import 'package:family_hub/features/sos/presentation/widgets/sos_alert_tile.dart';
import 'package:family_hub/features/tasks/presentation/widgets/task_tile.dart';

/// The Home tab: the family at a glance (docs/01-PRODUCT_SCOPE.md #5).
///
/// Top to bottom: greeting, active SOS alerts (only while there are any),
/// quick actions, the getting-started checklist for new families, my
/// pending tasks, the family board (members' task progress), savings goals,
/// this month's money and the latest notices.
///
/// Data comes from one `GET /dashboard` ([dashboardViewProvider]), which
/// refetches after every change anywhere in the app, at midnight and when
/// the app returns after a while in the background
/// ([dashboardResumeRefreshAfter]). Pull to refresh refreshes everything;
/// offline, the copy saved on the phone is shown with a notice.
///
/// Status bar (docs/12-DESIGN_LANGUAGE.md §3b): the gradient header is on
/// screen in **every** state (loading, error, data), so the transparent
/// status bar always sits on the brand gradient with white icons — no
/// canvas-coloured status bar during the first load and no flash when the
/// data arrives. Loading / error / refresh indicators render below the
/// header, never under the status bar. Once the page scrolls, a strip of
/// the header gradient covers the status bar ([DashboardStatusBarStrip]);
/// pulling past the top fills the gap with it ([DashboardOverscrollFill]).
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  final _scroll = DashboardScrollState();
  late final AppLifecycleListener _lifecycle;

  /// When the app went to the background (not just a system dialog or the
  /// notification shade covering it); `null` while in the foreground.
  DateTime? _hiddenAt;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onHide: _onHide, onResume: _onResume);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onHide() => _hiddenAt ??= ref.read(dashboardClockProvider)();

  void _onResume() {
    final hiddenAt = _hiddenAt;
    _hiddenAt = null;
    if (!mounted) return;
    // Timers do not run while the phone sleeps: catch up on a greeting
    // period or a day that changed meanwhile (midnight refetches).
    ref.read(dashboardNowProvider.notifier).sync();
    if (hiddenAt == null) return;
    final away = ref.read(dashboardClockProvider)().difference(hiddenAt);
    // A clock that jumped backwards counts as "a while".
    if (away.isNegative || away >= dashboardResumeRefreshAfter) {
      ref.invalidate(dashboardProvider);
    }
  }

  /// Only the page itself (not a nested horizontal list) moves the header.
  static bool _isPage(ScrollMetrics metrics, int depth) =>
      depth == 0 && metrics.axis == Axis.vertical;

  bool _onScroll(ScrollNotification n) {
    if (_isPage(n.metrics, n.depth)) _scroll.update(n.metrics.pixels);
    return false;
  }

  bool _onMetrics(ScrollMetricsNotification n) {
    // E.g. the page got shorter after a reload and the offset was clamped.
    if (_isPage(n.metrics, n.depth)) _scroll.update(n.metrics.pixels);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final value = ref.watch(dashboardViewProvider);
    final snapshot = value.value;
    final alerts = snapshot == null
        ? const <SosAlert>[]
        : dashboardActiveSos(
            snapshot: snapshot,
            live: ref.watch(dashboardLiveSosAlertsProvider),
            now: ref.watch(dashboardClockProvider)(),
          );

    return Scaffold(
      // The full-bleed gradient header replaces the app bar; keep a
      // screen-reader title for the tab.
      body: Semantics(
        label: l10n.navHome,
        explicitChildNodes: true,
        child: Stack(
          children: [
            PositionedDirectional(
              top: 0,
              start: 0,
              end: 0,
              child: DashboardOverscrollFill(overscroll: _scroll.overscroll),
            ),
            NotificationListener<ScrollMetricsNotification>(
              onNotification: _onMetrics,
              child: NotificationListener<ScrollNotification>(
                onNotification: _onScroll,
                child: GradientHeaderScrollView(
                  onRefresh: () => refreshDashboard(ref),
                  header: DashboardHeader(
                    data: snapshot?.data,
                    sosAlerts: alerts.length,
                  ),
                  children: [
                    // The first card overlaps the header's rounded bottom
                    // edge; so do the loading placeholder and the error.
                    AsyncValueView<DashboardSnapshot>(
                      value: value,
                      onRetry: () => ref.invalidate(dashboardProvider),
                      loading: const DashboardSkeleton(),
                      data: (snapshot) => _DashboardSections(
                        snapshot: snapshot,
                        alerts: alerts,
                        isRefreshing: value.isLoading,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            PositionedDirectional(
              top: 0,
              start: 0,
              end: 0,
              child: DashboardStatusBarStrip(scrolled: _scroll.scrolled),
            ),
          ],
        ),
      ),
    );
  }
}

/// Everything below the header, for a loaded [snapshot].
class _DashboardSections extends ConsumerWidget {
  const _DashboardSections({
    required this.snapshot,
    required this.alerts,
    required this.isRefreshing,
  });

  final DashboardSnapshot snapshot;

  /// Active SOS alerts to show first ([dashboardActiveSos]).
  final List<SosAlert> alerts;
  final bool isRefreshing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final data = snapshot.data;
    final savedAt = snapshot.savedAt;
    final myTasks = data.myTasks.take(DashboardData.myTasksLimit).toList();
    final hiddenTasks = data.hiddenMyTasksCount;
    final goals = data.goals.take(DashboardData.goalsLimit).toList();
    final notices = data.latestNotices
        .take(DashboardData.noticesLimit)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Active SOS alerts always come first.
        for (final alert in alerts) ...[
          SosAlertTile(alert, key: ValueKey('dashboard-sos-${alert.id}')),
          AppGap.sm,
        ],
        if (alerts.isNotEmpty) AppGap.sm,
        const DashboardQuickActions(),

        if (savedAt != null) ...[
          AppGap.lg,
          DashboardOfflineNotice(
            savedAt: savedAt,
            isRetrying: isRefreshing,
            onRetry: () => ref.invalidate(dashboardProvider),
          ),
        ],

        if (DashboardGettingStarted.isVisibleFor(data)) ...[
          AppGap.xl,
          DashboardGettingStarted(data: data),
        ],

        AppGap.xl,
        SectionHeader(
          title: l10n.dashboardMyTasksTitle,
          icon: AppIcons.task,
          accent: AppAccents.tasks,
          actionLabel: l10n.commonSeeAll,
          onAction: () => context.goToTab(AppRoutes.tasks),
        ),
        if (myTasks.isEmpty)
          DashboardEmptyCard(
            icon: AppIcons.doneAll,
            title: l10n.dashboardMyTasksEmptyTitle,
            message: l10n.dashboardMyTasksEmptyMessage,
          )
        else ...[
          for (var i = 0; i < myTasks.length; i++) ...[
            if (i > 0) AppGap.sm,
            TaskTile(
              myTasks[i],
              key: ValueKey('dashboard-task-${myTasks[i].id}'),
              showAssignee: false,
            ),
          ],
          if (hiddenTasks > 0)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: AppButton(
                label: l10n.dashboardMyTasksMore(hiddenTasks),
                icon: AppIcons.forward,
                variant: AppButtonVariant.text,
                expand: false,
                onPressed: () => context.goToTab(AppRoutes.tasks),
              ),
            ),
        ],

        if (data.members.isNotEmpty) ...[
          AppGap.xl,
          SectionHeader(
            title: l10n.dashboardFamilyBoardTitle,
            icon: AppIcons.family,
            accent: AppAccents.family,
            actionLabel: l10n.commonSeeAll,
            onAction: () => context.openFromDashboard(AppRoutes.members),
          ),
          DashboardMembersBoard(data: data),
        ],

        AppGap.xl,
        SectionHeader(
          title: l10n.dashboardGoalsTitle,
          icon: AppIcons.goal,
          accent: AppAccents.goals,
          actionLabel: l10n.commonSeeAll,
          onAction: () => context.goToTab(AppRoutes.money),
        ),
        if (goals.isEmpty)
          DashboardEmptyCard(
            icon: AppIcons.goalOutlined,
            title: l10n.dashboardGoalsEmptyTitle,
            message: data.isAdmin
                ? l10n.dashboardGoalsEmptyAdmin
                : l10n.dashboardGoalsEmptyMember,
            action: data.isAdmin
                ? AppButton(
                    label: l10n.dashboardNewGoal,
                    icon: AppIcons.add,
                    variant: AppButtonVariant.secondary,
                    expand: false,
                    onPressed: () =>
                        context.openFromDashboard(AppRoutes.goalNew),
                  )
                : null,
          )
        else
          for (var i = 0; i < goals.length; i++) ...[
            if (i > 0) AppGap.sm,
            GoalProgressCard(
              goals[i],
              key: ValueKey('dashboard-goal-${goals[i].id}'),
            ),
          ],

        AppGap.xl,
        SectionHeader(
          title: l10n.dashboardMonthTitle,
          icon: AppIcons.summary,
          accent: AppAccents.money,
        ),
        MonthSummaryCard(
          data.monthSummary,
          onTap: () => context.goToTab(AppRoutes.money),
        ),

        AppGap.xl,
        SectionHeader(
          title: l10n.dashboardNoticesTitle,
          icon: AppIcons.notice,
          accent: AppAccents.notices,
          actionLabel: l10n.commonSeeAll,
          onAction: () => context.openFromDashboard(AppRoutes.notices),
        ),
        if (notices.isEmpty)
          DashboardEmptyCard(
            icon: AppIcons.noticeOutlined,
            title: l10n.dashboardNoticesEmptyTitle,
            message: l10n.dashboardNoticesEmptyMessage,
            action: AppButton(
              label: l10n.dashboardActionPostNotice,
              icon: AppIcons.add,
              variant: AppButtonVariant.secondary,
              expand: false,
              onPressed: () => context.openFromDashboard(AppRoutes.noticeNew),
            ),
          )
        else
          for (var i = 0; i < notices.length; i++) ...[
            if (i > 0) AppGap.sm,
            NoticeCard(
              notices[i],
              key: ValueKey('dashboard-notice-${notices[i].id}'),
              compact: true,
              showActions: false,
              onTap: () => context.openFromDashboard(AppRoutes.notices),
            ),
          ],
      ],
    );
  }
}
