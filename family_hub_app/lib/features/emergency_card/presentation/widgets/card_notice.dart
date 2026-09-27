import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';

/// Borderless tinted inline notice (offline copy, disclaimer, permission
/// hints): the [accent]'s soft container with its icon colour; the text
/// keeps the normal on-surface colour for contrast.
class CardNotice extends StatelessWidget {
  const CardNotice({
    super.key,
    required this.icon,
    required this.accent,
    required this.text,
    this.liveRegion = false,
  });

  final IconData icon;
  final AppAccent accent;
  final String text;

  /// Announce changes to screen readers (e.g. the offline hint).
  final bool liveRegion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shades = context.accent(accent);
    return Semantics(
      container: true,
      liveRegion: liveRegion,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: shades.container,
          borderRadius: AppRadius.brLg,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: AppSizes.iconSm, color: shades.foreground),
              AppGap.hMd,
              Expanded(
                child: Text(
                  text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
