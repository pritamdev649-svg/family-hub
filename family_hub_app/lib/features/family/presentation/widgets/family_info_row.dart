import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/family/presentation/family_style.dart';

/// Read-only "label / value" row led by a solid [IconBadge] in [accent]
/// (like a fintech transaction row), with an optional trailing action
/// (e.g. [FamilyRowAction] "Change", "Open map"). Wraps with large text.
class FamilyInfoRow extends StatelessWidget {
  const FamilyInfoRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.accent = FamilyStyle.accent,
    this.detail,
    this.valueColor,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String value;
  final AppAccent accent;

  /// Optional second line under [value] (e.g. "Updated 5 minutes ago").
  final String? detail;
  final Color? valueColor;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: [
            ExcludeSemantics(
              child: IconBadge(
                icon: icon,
                accent: accent,
                size: AppSizes.badgeSm,
              ),
            ),
            AppGap.hMd,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.labelMedium?.copyWith(color: muted),
                  ),
                  AppGap.xxs,
                  Text(
                    value,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: valueColor,
                    ),
                  ),
                  if (detail != null) ...[
                    AppGap.xxs,
                    Text(
                      detail!,
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[AppGap.hSm, trailing!],
          ],
        ),
      ),
    );
  }
}

/// Small tinted pill button for the trailing action of a [FamilyInfoRow]
/// (borderless, in the row's accent, 48 dp target).
class FamilyRowAction extends StatelessWidget {
  const FamilyRowAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.accent = FamilyStyle.accent,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppAccent accent;

  @override
  Widget build(BuildContext context) {
    final shades = context.accent(accent);
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: shades.onContainer,
        backgroundColor: shades.container,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      ),
      child: Text(label),
    );
  }
}
