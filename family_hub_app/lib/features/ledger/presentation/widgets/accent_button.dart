import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';

// Material's disabled-state opacities (same as the theme's buttons).
const double _disabledFillOpacity = 0.12;
const double _disabledTextOpacity = 0.38;

/// The screen's primary action painted with the module [accent]'s gradient
/// and a soft glow (Save income = emerald, Save expense = rose, Contribute =
/// pink). Behaves like `AppButton(variant: primary)`: full width by default,
/// spinner + disabled while [isLoading], wraps long / large-text labels.
///
/// `AppButton` only offers the brand gradient; this is the per-accent
/// variant (candidate for `AppButton(accent: …)` in core — see
/// docs/progress/rd-ledger.md).
class LedgerAccentButton extends StatelessWidget {
  const LedgerAccentButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.accent,
    this.icon,
    this.isLoading = false,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppAccent accent;
  final IconData? icon;
  final bool isLoading;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final callback = isLoading ? null : onPressed;
    final enabled = callback != null;

    final Widget? leading;
    if (isLoading) {
      leading = const SizedBox.square(
        dimension: AppSizes.spinnerSm,
        child: CircularProgressIndicator(
          strokeWidth: AppSizes.spinnerStroke,
          color: Colors.white,
        ),
      );
    } else if (icon != null) {
      leading = Icon(icon, size: AppSizes.iconSm);
    } else {
      leading = null;
    }

    final button = DecoratedBox(
      decoration: BoxDecoration(
        // While saving the button keeps its colour (with the spinner), so
        // the screen does not flash grey.
        gradient: enabled || isLoading ? AppGradients.of(accent) : null,
        color: enabled || isLoading
            ? null
            : scheme.onSurface.withValues(alpha: _disabledFillOpacity),
        borderRadius: AppRadius.brLg,
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: accent.base.withValues(alpha: AppColors.glowOpacity),
                  blurRadius: AppSizes.cardShadowBlur,
                  offset: const Offset(0, AppSpacing.xs),
                ),
              ]
            : null,
      ),
      child: FilledButton(
        onPressed: callback,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: Colors.white,
          disabledForegroundColor: isLoading
              ? Colors.white
              : scheme.onSurface.withValues(alpha: _disabledTextOpacity),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (leading != null) ...[leading, AppGap.hSm],
            Flexible(
              child: Text(label, textAlign: TextAlign.center, softWrap: true),
            ),
          ],
        ),
      ),
    );

    final semantic = Semantics(
      value: isLoading ? context.l10n.commonLoading : null,
      child: button,
    );
    if (!expand) return semantic;
    return SizedBox(width: double.infinity, child: semantic);
  }
}
