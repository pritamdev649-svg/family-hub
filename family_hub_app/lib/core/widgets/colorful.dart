import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';

/// Thin white outline icon on a solid rounded square in a module [accent] —
/// the app's signature colourful element (list leading icons, quick actions,
/// category markers). With `soft: true` the badge is a pale tint with an
/// accent-coloured icon instead (for dense lists or secondary markers).
class IconBadge extends StatelessWidget {
  const IconBadge({
    super.key,
    required this.icon,
    this.accent = AppAccents.brand,
    this.size = AppSizes.badgeMd,
    this.soft = false,
    this.semanticLabel,
  });

  final IconData icon;
  final AppAccent accent;
  final double size;
  final bool soft;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final shades = context.accent(accent);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: soft ? shades.container : null,
        gradient: soft ? null : AppGradients.of(accent),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      alignment: Alignment.center,
      child: Icon(
        icon,
        size: size * 0.5,
        color: soft ? shades.foreground : Colors.white,
        semanticLabel: semanticLabel,
      ),
    );
  }
}

/// Hero container painted with a [gradient], decorative translucent circles
/// and a soft coloured glow. Text inside should be white
/// (`Colors.white` / `onPrimary`). Used for the dashboard greeting, money
/// balance, SOS state and other "headline" cards.
class GradientCard extends StatelessWidget {
  const GradientCard({
    super.key,
    required this.child,
    this.gradient = AppGradients.brand,
    this.glowColor = AppColors.seed,
    this.padding,
    this.onTap,
  });

  final Widget child;
  final Gradient gradient;
  final Color glowColor;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: padding ?? const EdgeInsets.all(AppSpacing.xl),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: Colors.white),
        child: IconTheme.merge(
          data: const IconThemeData(color: Colors.white),
          child: child,
        ),
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: AppRadius.brCard,
        boxShadow: [
          BoxShadow(
            color: glowColor.withValues(alpha: AppColors.glowOpacity),
            blurRadius: AppSizes.glowBlur,
            offset: const Offset(0, AppSpacing.sm),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: AppRadius.brCard,
        child: Material(
          type: MaterialType.transparency,
          child: Ink(
            decoration: BoxDecoration(gradient: gradient),
            child: InkWell(
              onTap: onTap,
              child: Stack(
                children: [
                  const PositionedDirectional(
                    top: -AppSpacing.xxxl,
                    end: -AppSpacing.xxl,
                    child: _Bubble(size: AppSpacing.xxxl * 3),
                  ),
                  const PositionedDirectional(
                    bottom: -AppSpacing.xxxl,
                    end: AppSpacing.xxxl,
                    child: _Bubble(size: AppSpacing.xxxl * 2),
                  ),
                  content,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.10),
        ),
      ),
    );
  }
}

/// Colourful quick-action tile: a solid gradient card in the module [accent]
/// with white text and a frosted icon square (like a payment card). Used in
/// grids (dashboard quick actions, More screen shortcuts).
class ActionTile extends StatelessWidget {
  const ActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final AppAccent accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: AppRadius.brCard,
          boxShadow: [
            BoxShadow(
              color: accent.base.withValues(alpha: AppColors.glowOpacity * 0.6),
              blurRadius: AppSizes.cardShadowBlur,
              offset: const Offset(0, AppSpacing.xs),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: AppRadius.brCard,
          child: Material(
            type: MaterialType.transparency,
            child: Ink(
              decoration: BoxDecoration(gradient: AppGradients.of(accent)),
              child: InkWell(
                onTap: onTap,
                child: Stack(
                  children: [
                    PositionedDirectional(
                      bottom: -AppSpacing.lg,
                      end: -AppSpacing.md,
                      child: Icon(
                        icon,
                        size: AppSizes.iconHero + AppSpacing.lg,
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: AppSizes.badgeSm,
                            height: AppSizes.badgeSm,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: AppRadius.brMd,
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              icon,
                              size: AppSizes.iconSm,
                              color: Colors.white,
                            ),
                          ),
                          AppGap.lg,
                          Text(
                            label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: Colors.white,
                            ),
                          ),
                          if (subtitle != null) ...[
                            AppGap.xxs,
                            Text(
                              subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.white.withValues(alpha: 0.85),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
