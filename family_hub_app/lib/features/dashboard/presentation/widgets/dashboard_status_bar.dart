import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:family_hub/core/design/design.dart';

/// Where the dashboard page is scrolled, as far as the status bar cares.
/// Updated by the screen from its scroll notifications; the two widgets
/// below listen to it without rebuilding the page.
class DashboardScrollState {
  /// The page is scrolled down (the header is moving up under the status
  /// bar).
  final ValueNotifier<bool> scrolled = ValueNotifier(false);

  /// How far the page is pulled down past its top (iOS bounce while pulling
  /// to refresh), in logical pixels; `0` otherwise.
  final ValueNotifier<double> overscroll = ValueNotifier(0);

  /// Applies a vertical scroll position of the page.
  void update(double pixels) {
    scrolled.value = pixels > 0;
    overscroll.value = pixels < 0 ? -pixels : 0;
  }

  void dispose() {
    scrolled.dispose();
    overscroll.dispose();
  }
}

/// Strip of the header gradient behind the **transparent** status bar,
/// painted **above** the page while it is scrolled (at the top the header
/// itself is behind the status bar). Cards never slide under the clock and
/// the status-bar icons stay white on it: its own [AnnotatedRegion] wins
/// over the page's because it is painted on top.
///
/// Fades in and out ([AppDurations.fast], instant with reduced motion). No
/// strip when there is no top inset — a shell banner (SOS / offline) then
/// sits above the tab and owns the status bar. Never takes taps.
///
/// Place it as the last child of a `Stack` over the page:
/// `PositionedDirectional(top: 0, start: 0, end: 0, child: …)`.
class DashboardStatusBarStrip extends StatelessWidget {
  const DashboardStatusBarStrip({
    super.key,
    required this.scrolled,
    this.gradient = AppGradients.brandHeader,
  });

  final ValueListenable<bool> scrolled;

  /// The page header's (horizontal) gradient, so the strip always matches
  /// the header colour behind it.
  final Gradient gradient;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    if (topInset <= 0) return const SizedBox.shrink();
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : AppDurations.fast;
    return IgnorePointer(
      child: ValueListenableBuilder<bool>(
        valueListenable: scrolled,
        builder: (context, visible, _) => AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: duration,
          curve: Curves.easeOutCubic,
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: AppSystemUi.forBackground(Brightness.dark),
            child: SizedBox(
              height: topInset,
              width: double.infinity,
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: gradient),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fills the gap above the header with its gradient while the page is
/// pulled down past its top (iOS bounce, pull to refresh), so the
/// transparent status bar never shows the bare canvas above the header.
///
/// Painted **behind** the page (first child of the `Stack`), so the
/// pull-to-refresh spinner stays visible on top of it; the header covers it
/// everywhere else. Android's stretch overscroll never opens a gap, so it
/// stays empty there.
class DashboardOverscrollFill extends StatelessWidget {
  const DashboardOverscrollFill({
    super.key,
    required this.overscroll,
    this.gradient = AppGradients.brandHeader,
  });

  final ValueListenable<double> overscroll;
  final Gradient gradient;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ValueListenableBuilder<double>(
        valueListenable: overscroll,
        builder: (context, gap, _) => SizedBox(
          height: gap,
          width: double.infinity,
          child: gap <= 0
              ? null
              : DecoratedBox(decoration: BoxDecoration(gradient: gradient)),
        ),
      ),
    );
  }
}
