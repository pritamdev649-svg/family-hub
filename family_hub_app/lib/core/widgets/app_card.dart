import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';

/// Borderless card used everywhere: card surface, [AppRadius.card] corners
/// and a very soft shadow in light mode (dark mode relies on the lighter
/// charcoal surface instead) — docs/12-DESIGN_LANGUAGE.md.
///
/// Has no outer margin — separate cards with `AppGap`s. When [onTap] is given
/// the whole card is an ink-splash button (and a button for screen readers).
/// Pass [accent] to give a highlighted / selected card the module's soft
/// tint as background.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.color,
    this.accent,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;

  /// Background override, e.g. `context.accent(AppAccents.sos).container`
  /// for an alert card.
  final Color? color;

  /// Optional module accent: the card uses the accent's soft container colour.
  final AppAccent? accent;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final background =
        color ??
        (accent == null ? semantic.card : context.accent(accent!).container);
    final content = Padding(padding: padding ?? AppSpacing.card, child: child);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: AppRadius.brCard,
        boxShadow: isLight
            ? const [
                BoxShadow(
                  color: AppColors.shadowLight,
                  blurRadius: AppSizes.cardShadowBlur,
                  offset: Offset(0, AppSpacing.xs),
                ),
              ]
            : null,
      ),
      child: Material(
        color: background,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.brCard),
        clipBehavior: Clip.antiAlias,
        child: onTap == null ? content : InkWell(onTap: onTap, child: content),
      ),
    );
  }
}
