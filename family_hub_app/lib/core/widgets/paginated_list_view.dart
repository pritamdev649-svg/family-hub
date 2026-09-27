import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';

import 'package:family_hub/core/widgets/app_button.dart';

/// List with "load more" pagination.
///
/// * Automatically asks for the next page when the user scrolls near the end
///   (once per page), and always shows a "Load more" button as an accessible
///   fallback (e.g. when the first page does not fill the screen or a page
///   failed to load).
/// * While [isLoadingMore] the footer shows a small spinner.
/// * Always scrollable, so it works inside [AppRefreshIndicator].
class PaginatedListView<T> extends StatefulWidget {
  const PaginatedListView({
    super.key,
    required this.items,
    required this.hasMore,
    required this.isLoadingMore,
    required this.onLoadMore,
    required this.itemBuilder,
    this.header,
    this.padding,
    this.separator,
    this.controller,
  });

  final List<T> items;
  final bool hasMore;
  final bool isLoadingMore;
  final VoidCallback onLoadMore;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final Widget? header;

  /// Defaults to [AppSpacing.screen].
  final EdgeInsetsGeometry? padding;

  /// Gap between rows; defaults to [AppGap.sm].
  final Widget? separator;
  final ScrollController? controller;

  @override
  State<PaginatedListView<T>> createState() => _PaginatedListViewState<T>();
}

class _PaginatedListViewState<T> extends State<PaginatedListView<T>> {
  /// How close (in logical pixels) to the end of the list the next page is
  /// requested — roughly two to three rows ahead.
  static const double _prefetchExtent = AppSpacing.xxxl * 6;

  /// Item count at which the next page was last auto-requested; prevents a
  /// burst of requests from consecutive scroll notifications.
  int? _requestedAt;

  @override
  void didUpdateWidget(PaginatedListView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The list was refreshed / reset: allow auto-loading again. (A failed page
    // keeps the count, so it is only retried via the button — no retry storm
    // while offline.)
    if (widget.items.length < oldWidget.items.length) _requestedAt = null;
  }

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical || n.depth != 0) return false;
    if (!widget.hasMore || widget.isLoadingMore) return false;
    if (n.metrics.extentAfter > _prefetchExtent) return false;
    final count = widget.items.length;
    if (_requestedAt == count) return false;
    _requestedAt = count;
    widget.onLoadMore();
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final header = widget.header;
    final headerCount = header == null ? 0 : 1;
    final showFooter = widget.hasMore || widget.isLoadingMore;
    final itemCount = headerCount + widget.items.length + (showFooter ? 1 : 0);

    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: ListView.separated(
        controller: widget.controller,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: widget.padding ?? AppSpacing.screen,
        itemCount: itemCount,
        separatorBuilder: (_, _) => widget.separator ?? AppGap.sm,
        itemBuilder: (context, index) {
          if (header != null && index == 0) return header;
          final i = index - headerCount;
          if (i < widget.items.length) {
            return widget.itemBuilder(context, widget.items[i]);
          }
          return _Footer(
            isLoading: widget.isLoadingMore,
            onLoadMore: widget.onLoadMore,
          );
        },
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.isLoading, required this.onLoadMore});

  final bool isLoading;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: ConstrainedBox(
        // Same height for spinner and button, so the list does not jump.
        constraints: const BoxConstraints(minHeight: AppSizes.minTapTarget),
        child: Center(
          child: isLoading
              ? Semantics(
                  label: context.l10n.commonLoading,
                  child: const SizedBox.square(
                    dimension: AppSizes.spinnerSm,
                    child: CircularProgressIndicator(
                      strokeWidth: AppSizes.spinnerStroke,
                    ),
                  ),
                )
              : AppButton(
                  label: context.l10n.commonLoadMore,
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
