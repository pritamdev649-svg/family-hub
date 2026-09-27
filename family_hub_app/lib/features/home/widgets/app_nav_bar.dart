import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';

/// One tab of [AppNavBar].
class AppNavDestination {
  const AppNavDestination({
    required this.icon,
    required this.label,
    this.tooltip,
    this.isSos = false,
  });

  final IconData icon;
  final String label;
  final String? tooltip;

  /// Rendered as the raised red gradient button in the middle of the bar.
  final bool isSos;
}

/// Modern floating bottom navigation: a borderless capsule that hovers above
/// the bottom edge with a soft shadow, a tinted indicator that **slides**
/// to the selected tab, gently scaling icons, and a raised glowing SOS
/// button in the middle so emergencies are always one tap away.
///
/// Animations are skipped when the platform asks for reduced motion.
class AppNavBar extends StatelessWidget {
  const AppNavBar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<AppNavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// Top margin above the floating capsule (room for the raised SOS glow).
  static const double _topMargin = AppSpacing.sm;

  /// Bottom margin below the capsule: the device's safe area, at least
  /// [AppSpacing.md].
  static double _bottomMargin(BuildContext context) =>
      math.max(MediaQuery.paddingOf(context).bottom, AppSpacing.md);

  /// Total vertical space the bar covers at the bottom of the screen
  /// (margins + capsule). The home shell passes it to tab screens as bottom
  /// padding so content, FABs and snack bars stay clear of the bar.
  static double occupiedHeight(BuildContext context) =>
      _topMargin + AppSizes.navBarHeight + _bottomMargin(context);

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    final scheme = Theme.of(context).colorScheme;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reduceMotion ? Duration.zero : AppDurations.slow;
    final selectedIsSos =
        selectedIndex >= 0 &&
        selectedIndex < destinations.length &&
        destinations[selectedIndex].isSos;

    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        AppSpacing.lg,
        _topMargin,
        AppSpacing.lg,
        _bottomMargin(context),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: semantic.card,
          borderRadius: AppRadius.brPill,
          boxShadow: [
            BoxShadow(
              color: isLight
                  ? AppColors.seed.withValues(alpha: 0.14)
                  : Colors.black.withValues(alpha: 0.45),
              blurRadius: AppSizes.glowBlur,
              offset: const Offset(0, AppSpacing.sm),
            ),
          ],
        ),
        child: SizedBox(
          height: AppSizes.navBarHeight,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final slot = constraints.maxWidth / destinations.length;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // Sliding selection indicator (hidden while SOS is open —
                  // the SOS button carries its own emphasis).
                  AnimatedPositionedDirectional(
                    duration: duration,
                    curve: Curves.easeOutCubic,
                    start: slot * selectedIndex + AppSpacing.xs,
                    top: AppSpacing.xs,
                    bottom: AppSpacing.xs,
                    width: slot - AppSpacing.sm,
                    child: AnimatedOpacity(
                      duration: duration,
                      opacity: selectedIsSos ? 0 : 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(
                            alpha: AppColors.tintOpacity,
                          ),
                          borderRadius: AppRadius.brPill,
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (var i = 0; i < destinations.length; i++)
                        Expanded(
                          child: destinations[i].isSos
                              ? _SosNavButton(
                                  destination: destinations[i],
                                  selected: i == selectedIndex,
                                  duration: duration,
                                  onTap: () => onSelected(i),
                                )
                              : _NavItem(
                                  destination: destinations[i],
                                  selected: i == selectedIndex,
                                  duration: duration,
                                  onTap: () => onSelected(i),
                                ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.duration,
    required this.onTap,
  });

  final AppNavDestination destination;
  final bool selected;
  final Duration duration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: color,
      fontWeight: selected ? AppTypography.bold : AppTypography.medium,
    );

    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: AppSizes.navBarHeight / 2,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedScale(
              duration: duration,
              curve: Curves.easeOutBack,
              scale: selected ? 1.12 : 1,
              child: TweenAnimationBuilder<Color?>(
                duration: duration,
                tween: ColorTween(end: color),
                builder: (context, c, _) =>
                    Icon(destination.icon, color: c, size: AppSizes.iconMd),
              ),
            ),
            AppGap.xxs,
            AnimatedDefaultTextStyle(
              duration: duration,
              style: labelStyle ?? const TextStyle(),
              child: Text(
                destination.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SosNavButton extends StatelessWidget {
  const _SosNavButton({
    required this.destination,
    required this.selected,
    required this.duration,
    required this.onTap,
  });

  final AppNavDestination destination;
  final bool selected;
  final Duration duration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sos = context.semanticColors;

    final button = Semantics(
      button: true,
      selected: selected,
      label: destination.tooltip ?? destination.label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            PositionedDirectional(
              top: -AppSizes.navSosRaise,
              child: AnimatedScale(
                duration: duration,
                curve: Curves.easeOutBack,
                scale: selected ? 1.08 : 1,
                child: Container(
                  width: AppSizes.navSosButton,
                  height: AppSizes.navSosButton,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppGradients.sos,
                    border: Border.all(color: sos.card, width: AppSpacing.xs),
                    boxShadow: [
                      BoxShadow(
                        color: sos.sos.withValues(
                          alpha: selected ? 0.55 : AppColors.glowOpacity,
                        ),
                        blurRadius: AppSizes.glowBlur,
                        offset: const Offset(0, AppSpacing.xs),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    destination.icon,
                    color: sos.onSos,
                    size: AppSizes.iconMd,
                  ),
                ),
              ),
            ),
            PositionedDirectional(
              bottom: AppSpacing.sm,
              start: 0,
              end: 0,
              child: Text(
                destination.label,
                maxLines: 1,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: sos.sos,
                  fontWeight: AppTypography.extraBold,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return destination.tooltip == null
        ? button
        : Tooltip(message: destination.tooltip!, child: button);
  }
}
