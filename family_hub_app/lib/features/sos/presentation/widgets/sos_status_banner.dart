import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/sos/application/sos_controller.dart';
import 'package:family_hub/features/sos/application/sos_providers.dart';
import 'package:family_hub/features/sos/presentation/sos_feedback.dart';
import 'package:family_hub/features/sos/presentation/sos_labels.dart';
import 'package:family_hub/features/sos/presentation/sos_navigation.dart';
import 'package:family_hub/features/sos/presentation/widgets/sos_pulsing_dot.dart';

/// Compact red banner above every tab (placed by `HomeShell`):
///
/// * the member's **own** alert is active → "Your SOS is active – sharing
///   live location" + "I am okay" (tap the banner for the SOS tab);
/// * else another member has an active alert → "Priya needs help" + "Open"
///   (`/sos/alert/:id`; several alerts → the SOS tab);
/// * otherwise nothing (`SizedBox.shrink`, zero height).
///
/// The status bar stays transparent: while the banner is the top-most
/// element, its red continues behind the status bar and the status-bar icons
/// switch to a contrasting colour ([_StatusBarBackdrop]). It never pads
/// itself for the status bar beyond its own `SafeArea` (the home shell's
/// `TopBannerSlot` places it below the status bar).
///
/// Watching it also keeps [sosControllerProvider] alive for the whole
/// signed-in session, so an active alert's live location tracking resumes
/// on app start.
class SosStatusBanner extends ConsumerWidget {
  const SosStatusBanner({super.key});

  Future<void> _imOkay(
    BuildContext context,
    WidgetRef ref,
    String alertId,
  ) async {
    try {
      final resolved = await ref
          .read(sosAlertActionsProvider.notifier)
          .resolve(alertId, SosResolution.safe);
      if (resolved != null && context.mounted) {
        showSosResolved(context, SosResolution.safe, result: resolved);
      }
    } catch (e) {
      if (context.mounted) context.showError(e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final own = ref.watch(sosControllerProvider);
    final mine = own.isActive ? own.alert : ref.watch(myActiveSosAlertProvider);

    if (mine != null) {
      final resolving = ref.watch(sosResolvingProvider(mine.id));
      final sharing = own.isActive
          ? own.sharing == SosSharing.live
          : mine.locationShared;
      return _BannerBar(
        text: sharing ? l10n.sosBannerSharing : l10n.sosBannerActive,
        onTap: () => context.go(AppRoutes.sos),
        actionLabel: l10n.sosImOkay,
        busy: resolving != null,
        onAction: resolving != null
            ? null
            : () => _imOkay(context, ref, mine.id),
      );
    }

    final others = ref.watch(otherActiveSosAlertsProvider).value;
    if (others == null || others.isEmpty) return const SizedBox.shrink();
    final single = others.length == 1 ? others.first : null;
    void open() => single != null
        ? openSosAlert(context, single.id)
        : context.go(AppRoutes.sos);
    return _BannerBar(
      text: single != null
          ? l10n.sosNeedsHelp(single.displayName(l10n))
          : l10n.sosManyNeedHelp(others.length),
      onTap: open,
      actionLabel: l10n.sosBannerOpen,
      onAction: open,
    );
  }
}

class _BannerBar extends StatelessWidget {
  const _BannerBar({
    required this.text,
    required this.onTap,
    required this.actionLabel,
    required this.onAction,
    this.busy = false,
  });

  final String text;
  final VoidCallback onTap;
  final String actionLabel;
  final VoidCallback? onAction;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sos = context.semanticColors;
    final view = View.of(context);

    return _StatusBarBackdrop(
      color: sos.sos,
      // Status-bar icons in the banner's text colour (white on red).
      lightIcons:
          ThemeData.estimateBrightnessForColor(sos.onSos) == Brightness.light,
      // The raw status-bar height: `TopBannerSlot` removes the top inset
      // from the banner's `MediaQuery`.
      statusBarHeight: view.viewPadding.top / view.devicePixelRatio,
      child: Semantics(
        container: true,
        liveRegion: true,
        child: Material(
          color: sos.sos,
          child: InkWell(
            onTap: onTap,
            // `top: true` only matters if the banner is ever laid out under
            // the status bar with the inset still in its `MediaQuery`.
            child: SafeArea(
              bottom: false,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: AppSizes.minTapTarget,
                ),
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: AppSpacing.lg,
                    end: AppSpacing.sm,
                    top: AppSpacing.xs,
                    bottom: AppSpacing.xs,
                  ),
                  child: Row(
                    children: [
                      SosPulsingDot(color: sos.onSos),
                      AppGap.hSm,
                      Expanded(
                        child: Text(
                          text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: sos.onSos,
                          ),
                        ),
                      ),
                      AppGap.hSm,
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: sos.onSos,
                          foregroundColor: sos.sos,
                          disabledBackgroundColor: sos.onSos,
                          disabledForegroundColor: sos.sos,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                          ),
                        ),
                        onPressed: onAction,
                        child: busy
                            ? SizedBox.square(
                                dimension: AppSizes.spinnerSm,
                                child: CircularProgressIndicator(
                                  strokeWidth: AppSizes.spinnerStroke,
                                  color: sos.sos,
                                ),
                              )
                            : Text(actionLabel),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Makes the (transparent) status bar match the banner below it:
///
/// * fills the gap between the top of the screen and the banner — at most
///   [statusBarHeight] — with [color], so the strip above a red banner is
///   not the page background;
/// * annotates the strip and the banner with a [SystemUiOverlayStyle] with
///   [lightIcons] (white on red), whatever the screen below chose.
///
/// Only the status-bar fields are set, so the system navigation bar is left
/// to the screens. Nothing is painted when the banner starts at the top of
/// the screen or lower than the status bar would reach.
class _StatusBarBackdrop extends SingleChildRenderObjectWidget {
  const _StatusBarBackdrop({
    required this.color,
    required this.lightIcons,
    required this.statusBarHeight,
    required super.child,
  });

  final Color color;
  final bool lightIcons;
  final double statusBarHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderStatusBarBackdrop(
        color: color,
        lightIcons: lightIcons,
        statusBarHeight: statusBarHeight,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderStatusBarBackdrop renderObject,
  ) {
    renderObject
      ..color = color
      ..lightIcons = lightIcons
      ..statusBarHeight = statusBarHeight;
  }
}

class _RenderStatusBarBackdrop extends RenderProxyBox {
  _RenderStatusBarBackdrop({
    required Color color,
    required bool lightIcons,
    required double statusBarHeight,
  }) : _color = color,
       _lightIcons = lightIcons,
       _statusBarHeight = statusBarHeight;

  Color _color;
  set color(Color value) {
    if (value == _color) return;
    _color = value;
    markNeedsPaint();
  }

  bool _lightIcons;
  set lightIcons(bool value) {
    if (value == _lightIcons) return;
    _lightIcons = value;
    markNeedsPaint();
  }

  double _statusBarHeight;
  set statusBarHeight(double value) {
    if (value == _statusBarHeight) return;
    _statusBarHeight = value;
    markNeedsPaint();
  }

  SystemUiOverlayStyle get _style => SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    // Android: icon colour; iOS: brightness of what is behind the icons.
    statusBarIconBrightness: _lightIcons ? Brightness.light : Brightness.dark,
    statusBarBrightness: _lightIcons ? Brightness.dark : Brightness.light,
  );

  /// Distance from the top of the screen to the banner, when the banner is
  /// the element right below the status bar (else 0).
  double _gapAbove() {
    if (_statusBarHeight <= 0 || !attached) return 0;
    final top = localToGlobal(Offset.zero).dy;
    if (top <= 0 || top > _statusBarHeight + precisionErrorTolerance) return 0;
    return top;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (size.isEmpty) return super.paint(context, offset);
    final gap = _gapAbove();
    if (gap > 0) {
      context.canvas.drawRect(
        Rect.fromLTWH(offset.dx, offset.dy - gap, size.width, gap),
        Paint()..color = _color,
      );
    }
    final region = AnnotatedRegionLayer<SystemUiOverlayStyle>(
      _style,
      size: Size(size.width, size.height + gap),
      offset: offset.translate(0, -gap),
    );
    context.pushLayer(region, super.paint, offset);
  }
}
