import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/features/sos/presentation/sos_style.dart';

/// Colour treatment of a [SosActionButton].
enum SosButtonTone {
  /// White fill with SOS-red text: the main action on a red gradient card
  /// ("I am okay", "Mark as helped").
  onGradient,

  /// No fill, white text: a secondary action on a red gradient card
  /// ("False alarm", "View alert details").
  onGradientText,

  /// Solid SOS red with white text, on the normal surface ("Send again").
  solid,
}

/// Button in the SOS colours. Behaves exactly like `AppButton` (theme size
/// and shape, spinner + disabled while [isLoading] so an action is never
/// sent twice, wrapping labels, busy state announced to screen readers) —
/// `AppButton` itself has no colour option.
class SosActionButton extends StatelessWidget {
  const SosActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.tone = SosButtonTone.solid,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final SosButtonTone tone;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final sos = context.semanticColors;
    final (Color background, Color foreground) = switch (tone) {
      // Red-700 on white: 6.5:1.
      SosButtonTone.onGradient => (Colors.white, SosStyle.accent.dark),
      SosButtonTone.onGradientText => (Colors.transparent, Colors.white),
      SosButtonTone.solid => (sos.sos, sos.onSos),
    };
    final callback = isLoading ? null : onPressed;

    final button = FilledButton(
      onPressed: callback,
      style: FilledButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        disabledBackgroundColor: background == Colors.transparent
            ? Colors.transparent
            : background.withValues(alpha: SosStyle.disabledOpacity),
        disabledForegroundColor: foreground.withValues(
          alpha: SosStyle.disabledOpacity,
        ),
        elevation: 0,
        shadowColor: Colors.transparent,
      ),
      child: _Content(label: label, icon: icon, isLoading: isLoading),
    );

    final semantic = Semantics(
      value: isLoading ? context.l10n.commonLoading : null,
      child: button,
    );
    if (!expand) return semantic;
    return SizedBox(width: double.infinity, child: semantic);
  }
}

class _Content extends StatelessWidget {
  const _Content({
    required this.label,
    required this.icon,
    required this.isLoading,
  });

  final String label;
  final IconData? icon;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final Widget? leading = isLoading
        ? SizedBox.square(
            dimension: AppSizes.spinnerSm,
            child: CircularProgressIndicator(
              strokeWidth: AppSizes.spinnerStroke,
              // The button's (disabled) foreground colour.
              color: IconTheme.of(context).color,
            ),
          )
        : (icon == null ? null : Icon(icon, size: AppSizes.iconSm));
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
