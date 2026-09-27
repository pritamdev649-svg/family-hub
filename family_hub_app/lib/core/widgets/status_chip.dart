import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';

/// Small, non-interactive pill for statuses and tags (e.g. "Overdue",
/// "Admin", "Achieved"). Text and icon use [color] on a soft tint of it.
///
/// Pass theme / semantic colours only, e.g. `context.semanticColors.warning`
/// or `Theme.of(context).colorScheme.primary` (the default).
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, this.color, this.icon});

  final String label;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.colorScheme.primary;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.withValues(alpha: AppColors.tintOpacity),
        borderRadius: AppRadius.brPill,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xxs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: AppSizes.iconXs, color: c),
              AppGap.hXs,
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(color: c),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
