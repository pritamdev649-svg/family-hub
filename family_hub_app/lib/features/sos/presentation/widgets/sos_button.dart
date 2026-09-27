import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/features/sos/application/sos_controller.dart';

/// The huge round red SOS button.
///
/// * idle: "SOS" — tapping starts the countdown ([onPressed]);
/// * countdown: the seconds left (3, 2, 1) — the Cancel button lives next
///   to it on the screen;
/// * sending: a spinner.
///
/// Its diameter is [AppSizes.sosButton], shrunk to fit narrow screens; the
/// content scales down inside the circle, so large text never overflows.
/// Screen readers get a descriptive label and the countdown as a live
/// region.
class SosButton extends StatelessWidget {
  const SosButton({super.key, required this.state, required this.onPressed});

  final SosState state;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final sos = context.semanticColors;
    final counting = state.isCountingDown;
    final sending = state.isSending;
    final busy = counting || sending;

    final Widget content;
    if (counting) {
      content = Text(
        '${state.secondsLeft}',
        key: ValueKey<int>(state.secondsLeft),
        style: theme.textTheme.displayLarge?.copyWith(
          color: sos.onSos,
          fontWeight: AppTypography.bold,
        ),
      );
    } else if (sending) {
      content = SizedBox.square(
        key: const ValueKey<String>('sending'),
        dimension: AppSizes.spinnerLg,
        child: CircularProgressIndicator(
          strokeWidth: AppSizes.spinnerStroke,
          color: sos.onSos,
        ),
      );
    } else {
      content = Column(
        key: const ValueKey<String>('idle'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(AppIcons.sosAlert, size: AppSizes.iconXl, color: sos.onSos),
          Text(
            l10n.sosButtonLabel,
            style: theme.textTheme.displaySmall?.copyWith(
              color: sos.onSos,
              fontWeight: AppTypography.bold,
            ),
          ),
        ],
      );
    }

    final semanticsLabel = counting
        ? l10n.sosSendingIn(state.secondsLeft)
        : sending
        ? l10n.sosSending
        : l10n.sosButtonSemantics;

    return LayoutBuilder(
      builder: (context, constraints) {
        const halo = AppSpacing.md * 2;
        final available = constraints.hasBoundedWidth
            ? constraints.maxWidth - halo
            : AppSizes.sosButton;
        final diameter = math.max(
          AppSizes.minTapTarget,
          math.min(AppSizes.sosButton, available),
        );
        return Center(
          child: Semantics(
            container: true,
            button: true,
            enabled: onPressed != null && !busy,
            liveRegion: busy,
            label: semanticsLabel,
            excludeSemantics: true,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: sos.sosContainer,
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Material(
                  color: sos.sos,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: busy ? null : onPressed,
                    customBorder: const CircleBorder(),
                    child: SizedBox.square(
                      dimension: diameter,
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: AnimatedSwitcher(
                            duration: AppDurations.fast,
                            child: content,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
