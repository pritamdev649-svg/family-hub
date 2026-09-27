import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';

/// Visual weight of an [AppButton].
enum AppButtonVariant {
  /// Brand gradient with a soft glow — the main action of a screen.
  primary,

  /// Soft tinted fill — prominent but secondary actions.
  tonal,

  /// Outlined — secondary / alternative actions.
  secondary,

  /// Text only — low-emphasis actions (e.g. "See all", "Skip").
  text,

  /// Filled with the error colour — destructive actions (delete, remove).
  danger,
}

/// The one button used across the app.
///
/// * While [isLoading] is true it shows a spinner in place of the icon and is
///   disabled, so a mutation can never be submitted twice.
/// * [onPressed] `null` renders the disabled state.
/// * [expand] stretches the button to the available width (forms, sheets).
/// * Long / large-text labels wrap instead of overflowing.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.variant = AppButtonVariant.primary,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final AppButtonVariant variant;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final callback = isLoading ? null : onPressed;
    final child = _ButtonContent(
      label: label,
      icon: icon,
      isLoading: isLoading,
    );

    final Widget button = switch (variant) {
      AppButtonVariant.primary => _GradientFilledButton(
        onPressed: callback,
        child: child,
      ),
      AppButtonVariant.tonal => FilledButton.tonal(
        onPressed: callback,
        child: child,
      ),
      AppButtonVariant.secondary => OutlinedButton(
        onPressed: callback,
        child: child,
      ),
      AppButtonVariant.text => TextButton(onPressed: callback, child: child),
      AppButtonVariant.danger => FilledButton(
        onPressed: callback,
        style: FilledButton.styleFrom(
          backgroundColor: scheme.error,
          foregroundColor: scheme.onError,
        ),
        child: child,
      ),
    };

    final semantic = Semantics(
      // Announce the busy state; the label itself comes from the button text.
      value: isLoading ? context.l10n.commonLoading : null,
      child: button,
    );

    if (!expand) return semantic;
    return SizedBox(width: double.infinity, child: semantic);
  }
}

class _ButtonContent extends StatelessWidget {
  const _ButtonContent({
    required this.label,
    required this.icon,
    required this.isLoading,
  });

  final String label;
  final IconData? icon;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final Widget? leading;
    if (isLoading) {
      leading = SizedBox.square(
        dimension: AppSizes.spinnerSm,
        child: CircularProgressIndicator(
          strokeWidth: AppSizes.spinnerStroke,
          // Inherit the button's (disabled) foreground colour.
          color: IconTheme.of(context).color,
        ),
      );
    } else if (icon != null) {
      leading = Icon(icon, size: AppSizes.iconSm);
    } else {
      leading = null;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (leading != null) ...[leading, AppGap.hSm],
        Flexible(
          child: Text(label, textAlign: TextAlign.center, softWrap: true),
        ),
      ],
    );
  }
}

/// [FilledButton] painted with [AppGradients.brand] and a soft coloured glow.
/// Falls back to the theme's disabled colours when [onPressed] is null.
class _GradientFilledButton extends StatelessWidget {
  const _GradientFilledButton({required this.onPressed, required this.child});

  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: enabled ? AppGradients.brand : null,
        color: enabled ? null : scheme.onSurface.withValues(alpha: 0.12),
        borderRadius: AppRadius.brLg,
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: AppColors.seed.withValues(
                    alpha: AppColors.glowOpacity,
                  ),
                  blurRadius: AppSizes.cardShadowBlur,
                  offset: const Offset(0, AppSpacing.xs),
                ),
              ]
            : null,
      ),
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: Colors.white,
        ),
        child: child,
      ),
    );
  }
}
