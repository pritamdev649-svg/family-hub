import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/notices/application/notices_providers.dart';
import 'package:family_hub/features/notices/presentation/widgets/notice_card.dart';
import 'package:family_hub/features/notices/presentation/widgets/notice_route_guard.dart';
import 'package:family_hub/features/notices/presentation/widgets/notice_style.dart';
import 'package:family_hub/features/notices/presentation/widgets/notices_header.dart';

/// `/notices` — the family notice board: pinned notices first (with a pin
/// badge), then newest first; pull to refresh, "load more", and a FAB to post
/// a new notice. Card actions (edit / pin / delete / copy) live in
/// [NoticeCard].
///
/// Layout (docs/12-DESIGN_LANGUAGE.md §3b): an amber full-bleed header that
/// starts behind the **transparent** status bar ([GradientHeaderScrollView]),
/// with the cards sliding over its rounded bottom edge. Once the board is
/// scrolled, a strip of the same (horizontal) gradient fades in behind the
/// status bar, so the clock and icons always sit on the header colour
/// instead of on top of scrolling cards.
///
/// Other members post and edit notices on their own phones and there is no
/// live channel, so besides pull-to-refresh the board reloads when the app
/// comes back from the background while it is the visible screen (e.g.
/// after tapping a `notice` push notification).
class NoticesScreen extends ConsumerStatefulWidget {
  const NoticesScreen({super.key});

  @override
  ConsumerState<NoticesScreen> createState() => _NoticesScreenState();
}

class _NoticesScreenState extends ConsumerState<NoticesScreen> {
  /// How close (in logical pixels) to the end of the board the next page is
  /// requested — roughly two to three cards ahead.
  static const double _prefetchExtent = AppSpacing.xxxl * 6;

  late final AppLifecycleListener _lifecycle;

  /// The app went to the background (not just a system dialog or the
  /// notification shade covering it, which would refetch far too often).
  bool _wasHidden = false;

  /// The board is scrolled away from the top (status-bar strip visible).
  bool _scrolled = false;

  /// Number of loaded notices when the next page was last auto-requested;
  /// prevents a burst of requests from consecutive scroll notifications and
  /// a retry storm after a failed page (that one is retried via the button).
  int? _requestedAt;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onHide: () => _wasHidden = true,
      onResume: _onResume,
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _onResume() {
    if (!_wasHidden) return;
    _wasHidden = false;
    if (!mounted || !isNoticeRouteCurrent(context)) return;
    ref.invalidate(noticeListProvider);
  }

  void _create() {
    if (!isNoticeRouteCurrent(context)) return;
    context.push(AppRoutes.noticeNew);
  }

  Future<void> _loadMore() async {
    try {
      await ref.read(noticeListProvider.notifier).loadMore();
    } catch (e) {
      if (mounted) context.showError(e);
    }
  }

  static bool _isBoardScroll(ScrollMetrics metrics, int depth) =>
      depth == 0 && metrics.axis == Axis.vertical;

  void _updateScrolled(ScrollMetrics metrics) {
    final scrolled = metrics.pixels > 0;
    if (scrolled != _scrolled) setState(() => _scrolled = scrolled);
  }

  bool _onScroll(ScrollNotification n) {
    if (!_isBoardScroll(n.metrics, n.depth)) return false;
    _updateScrolled(n.metrics);
    if (n is ScrollUpdateNotification) _maybeLoadMore(n.metrics);
    return false;
  }

  bool _onMetrics(ScrollMetricsNotification n) {
    // E.g. the board got shorter after a delete and the offset was clamped.
    if (_isBoardScroll(n.metrics, n.depth)) _updateScrolled(n.metrics);
    return false;
  }

  void _maybeLoadMore(ScrollMetrics metrics) {
    final board = ref.read(noticeListProvider).value;
    if (board == null || !board.hasMore || board.isLoadingMore) return;
    if (metrics.extentAfter > _prefetchExtent) return;
    final count = board.items.length;
    if (_requestedAt == count) return;
    _requestedAt = count;
    _loadMore();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final board = ref.watch(noticeListProvider);
    final canCreate = ref.watch(
      noticePermissionsProvider.select((p) => p.canCreate),
    );
    final topInset = MediaQuery.paddingOf(context).top;

    final empty = _NoticesEmptyCard(
      title: l10n.noticesEmptyTitle,
      message: l10n.noticesEmptyMessage,
      action: canCreate
          ? AppButton(
              label: l10n.noticesNew,
              icon: AppIcons.add,
              variant: AppButtonVariant.tonal,
              expand: false,
              onPressed: _create,
            )
          : null,
    );

    return Scaffold(
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              heroTag: null,
              backgroundColor: NoticeStyle.solid,
              foregroundColor: Colors.white,
              onPressed: _create,
              icon: const Icon(AppIcons.add),
              label: Text(l10n.noticesNew),
            )
          : null,
      body: Stack(
        children: [
          NotificationListener<ScrollMetricsNotification>(
            onNotification: _onMetrics,
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: GradientHeaderScrollView(
                gradient: NoticeStyle.header,
                onRefresh: () => ref.refresh(noticeListProvider.future),
                header: NoticesHeader(board: board.value),
                children: [
                  // The first card overlaps the header's rounded bottom edge.
                  AsyncValueView<NoticeListState>(
                    value: board,
                    onRetry: () => ref.invalidate(noticeListProvider),
                    loading: const AppCard(child: LoadingView()),
                    isEmpty: (state) => state.isEmpty,
                    empty: empty,
                    data: (state) =>
                        _NoticeList(state: state, onLoadMore: _loadMore),
                  ),
                  // Room below the last card for the FAB.
                  if (canCreate) ...[AppGap.xxxl, AppGap.xxl],
                ],
              ),
            ),
          ),
          PositionedDirectional(
            top: 0,
            start: 0,
            end: 0,
            height: topInset,
            child: _StatusBarBackdrop(visible: _scrolled),
          ),
        ],
      ),
    );
  }
}

/// The loaded notices as cards, then the "load more" footer.
class _NoticeList extends StatelessWidget {
  const _NoticeList({required this.state, required this.onLoadMore});

  final NoticeListState state;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final items = state.items;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) AppGap.sm,
          NoticeCard(items[i], key: ValueKey(items[i].id)),
        ],
        if (state.hasMore || state.isLoadingMore) ...[
          AppGap.sm,
          _LoadMoreFooter(
            isLoading: state.isLoadingMore,
            onLoadMore: onLoadMore,
          ),
        ],
      ],
    );
  }
}

/// Spinner while the next page loads, otherwise an accessible "Load more"
/// button (also the fallback when a page failed or the first page does not
/// fill the screen). Same height in both states, so the board does not jump.
class _LoadMoreFooter extends StatelessWidget {
  const _LoadMoreFooter({required this.isLoading, required this.onLoadMore});

  final bool isLoading;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppSizes.minTapTarget),
      child: Center(
        child: isLoading
            ? Semantics(
                label: l10n.commonLoading,
                child: SizedBox.square(
                  dimension: AppSizes.spinnerSm,
                  child: CircularProgressIndicator(
                    strokeWidth: AppSizes.spinnerStroke,
                    color: context.accent(NoticeStyle.accent).base,
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
    );
  }
}

/// Empty board: a borderless card with the amber notice badge, friendly
/// copy and the call to action (it overlaps the header like the cards).
class _NoticesEmptyCard extends StatelessWidget {
  const _NoticesEmptyCard({
    required this.title,
    required this.message,
    this.action,
  });

  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.xxl,
      ),
      child: Column(
        children: [
          const ExcludeSemantics(
            child: IconBadge(
              icon: AppIcons.noticeOutlined,
              accent: NoticeStyle.accent,
              size: AppSizes.badgeLg,
            ),
          ),
          AppGap.lg,
          Semantics(
            header: true,
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
          ),
          AppGap.sm,
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (action != null) ...[AppGap.xl, action!],
        ],
      ),
    );
  }
}

/// Strip of the header gradient behind the status bar, shown once the board
/// is scrolled (at the top the header itself is behind the status bar). Keeps
/// the status-bar icons white on it — this region is painted above the
/// scroll view, so its style wins over the scroll view's own.
class _StatusBarBackdrop extends StatelessWidget {
  const _StatusBarBackdrop({required this.visible});

  final bool visible;

  /// Transparent status bar with white icons, no system scrim. Only the
  /// status-bar fields: the navigation bar keeps the style of the region at
  /// the bottom of the screen.
  static const SystemUiOverlayStyle overlayStyle = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemStatusBarContrastEnforced: false,
  );

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: reduceMotion ? Duration.zero : AppDurations.fast,
        curve: Curves.easeOutCubic,
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: overlayStyle,
          child: DecoratedBox(
            decoration: BoxDecoration(gradient: NoticeStyle.header),
          ),
        ),
      ),
    );
  }
}
