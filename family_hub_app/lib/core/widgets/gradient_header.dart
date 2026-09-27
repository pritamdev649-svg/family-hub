import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/widgets/app_refresh_indicator.dart';
import 'package:family_hub/core/widgets/responsive_center.dart';

/// Full-bleed gradient header that starts at the very top of the screen
/// (behind the status bar), with rounded bottom corners and soft decorative
/// bubbles. Text and icons inside default to white.
///
/// Usually used through [GradientHeaderScrollView], which also pins a strip
/// of the same gradient behind the status bar and lets the content overlap
/// the header's bottom edge.
class GradientHeader extends StatelessWidget {
  const GradientHeader({
    super.key,
    required this.child,
    this.gradient = AppGradients.brandHeader,
    this.bottomSpace = AppSpacing.xxl,
  });

  final Widget child;
  final Gradient gradient;

  /// Extra space below [child] that the overlapping content covers.
  final double bottomSpace;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        bottom: Radius.circular(AppRadius.hero),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: gradient),
        child: Stack(
          children: [
            const PositionedDirectional(
              top: -AppSpacing.xxxl,
              end: -AppSpacing.xxl,
              child: _HeaderBubble(size: AppSpacing.xxxl * 4),
            ),
            const PositionedDirectional(
              bottom: -AppSpacing.xxxl,
              start: -AppSpacing.xxl,
              child: _HeaderBubble(size: AppSpacing.xxxl * 3),
            ),
            ResponsiveCenter(
              child: Padding(
                padding: EdgeInsetsDirectional.fromSTEB(
                  AppSpacing.xl,
                  topInset + AppSpacing.lg,
                  AppSpacing.xl,
                  AppSpacing.xl + bottomSpace,
                ),
                child: DefaultTextStyle.merge(
                  style: const TextStyle(color: Colors.white),
                  child: IconTheme.merge(
                    data: const IconThemeData(color: Colors.white),
                    child: child,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderBubble extends StatelessWidget {
  const _HeaderBubble({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.08),
        ),
      ),
    );
  }
}

/// Scrollable tab-screen layout with a full-bleed [GradientHeader] on top:
///
/// * the header extends behind a **transparent** status bar,
/// * status-bar icons are white while the header is behind them and switch to
///   the theme's normal contrast once it has scrolled away,
/// * [children] are laid out in a centred column that overlaps the header's
///   rounded bottom edge by [overlap] (the "card sliding over the header"
///   look),
/// * content scrolls behind the floating navigation bar,
/// * optional pull-to-refresh.
class GradientHeaderScrollView extends StatefulWidget {
  const GradientHeaderScrollView({
    super.key,
    required this.header,
    required this.children,
    this.gradient = AppGradients.brandHeader,
    this.onRefresh,
    this.overlap = AppSpacing.xxl,
  });

  final Widget header;
  final List<Widget> children;
  final Gradient gradient;
  final Future<void> Function()? onRefresh;
  final double overlap;

  @override
  State<GradientHeaderScrollView> createState() =>
      _GradientHeaderScrollViewState();
}

class _GradientHeaderScrollViewState extends State<GradientHeaderScrollView> {
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
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: widget.children,
              ),
            ),
          ),
        ),
      ],
    );
    if (widget.onRefresh != null) {
      list = AppRefreshIndicator(
        onRefresh: widget.onRefresh!,
        edgeOffset: topInset,
        child: list,
      );
    }

    // Transparent status bar; white icons over the gradient (or in dark
    // mode), the theme's normal dark icons once the header scrolled away.
    final darkBehindStatusBar = _headerUnderStatusBar || isDark;
    final style = AppSystemUi.forBackground(
      darkBehindStatusBar ? Brightness.dark : Brightness.light,
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(value: style, child: list);
  }
}
