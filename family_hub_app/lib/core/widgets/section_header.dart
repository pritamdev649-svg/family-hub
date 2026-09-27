import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';

/// Title above a group of content, with an optional trailing action
/// (e.g. "See all") rendered as a small tinted pill with a chevron.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
    this.icon,
    this.accent,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Optional thin icon shown before the title in the [accent] colour.
  final IconData? icon;
  final AppAccent? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasAction = actionLabel != null && onAction != null;
    final shades = context.accent(accent ?? AppAccents.brand);

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppSizes.minTapTarget),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: AppSizes.iconSm, color: shades.foreground),
            AppGap.hSm,
          ],
          Expanded(
            child: Semantics(
              header: true,
              child: Text(title, style: theme.textTheme.titleMedium),
            ),
          ),
          if (hasAction) ...[
            AppGap.hSm,
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: shades.foreground,
                backgroundColor: shades.container,
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(actionLabel!),
                  AppGap.hXxs,
                  const Icon(AppIcons.chevron, size: AppSizes.iconXs),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
