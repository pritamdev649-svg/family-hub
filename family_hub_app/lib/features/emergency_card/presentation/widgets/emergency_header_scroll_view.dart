import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/widgets/widgets.dart';

/// Same layout as core [GradientHeaderScrollView] — a full-bleed
/// [GradientHeader] behind the **transparent** status bar (white status-bar
/// icons while it is behind them), content overlapping the header's rounded
/// bottom edge by [overlap], optional pull-to-refresh, bottom padding for the
/// system / floating navigation bar — with one fix: the part of the content
/// that overlaps the header **receives taps**.
///
/// Core puts the header and the (translated) content in two separate list
/// items; the content item's box ends at the header's bottom, so taps on its
/// top [overlap] pixels hit the header instead (e.g. the upper third of the
/// "Show to responder" card did nothing). Here both live in one list item,
/// whose `Column` hit-tests the content first.
// TODO(visual-qa): apply the fix to core `GradientHeaderScrollView` and use
// it here again (handoff in docs/progress/rd-emergency.md).
class EmergencyHeaderScrollView extends StatefulWidget {
  const EmergencyHeaderScrollView({
    super.key,
    required this.header,
    required this.children,
    required this.gradient,
    this.onRefresh,
    this.overlap = AppSpacing.xxl,
  });

  final Widget header;
  final List<Widget> children;
  final Gradient gradient;
  final Future<void> Function()? onRefresh;
  final double overlap;

  @override
  State<EmergencyHeaderScrollView> createState() =>
      _EmergencyHeaderScrollViewState();
}

class _EmergencyHeaderScrollViewState extends State<EmergencyHeaderScrollView> {
  final _controller = ScrollController();
  final _headerKey = GlobalKey();
  bool _headerUnderStatusBar = true;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    final box = _headerKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final topInset = MediaQuery.paddingOf(context).top;
    // The header is "behind the status bar" until its bottom edge scrolls
    // above the status bar.
    final visible =
        _controller.offset < box.size.height - widget.overlap - topInset;
    if (visible != _headerUnderStatusBar) {
      setState(() => _headerUnderStatusBar = visible);
    }
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget list = ListView(
      controller: _controller,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(bottom: bottomInset + AppSpacing.lg),
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GradientHeader(
              key: _headerKey,
              gradient: widget.gradient,
              bottomSpace: widget.overlap,
              child: widget.header,
            ),
            Transform.translate(
              offset: Offset(0, -widget.overlap),
              child: ResponsiveCenter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: widget.children,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
    final refresh = widget.onRefresh;
    if (refresh != null) {
      list = AppRefreshIndicator(
        onRefresh: refresh,
        edgeOffset: topInset,
        child: list,
      );
    }

    // Transparent status bar; white icons over the gradient (or in dark
    // mode), the theme's normal dark icons once the header scrolled away.
    final darkBehindStatusBar = _headerUnderStatusBar || isDark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppSystemUi.forBackground(
        darkBehindStatusBar ? Brightness.dark : Brightness.light,
      ),
      child: list,
    );
  }
}
