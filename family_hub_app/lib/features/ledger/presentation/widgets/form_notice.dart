import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';

/// Informational box at the top of a form or detail screen (e.g. "this
/// entry is a goal contribution", "this goal is archived"): borderless soft
/// tint of [accent] with a thin icon.
class FormNotice extends StatelessWidget {
  const FormNotice({
    super.key,
    required this.icon,
    required this.message,
    this.accent = AppAccents.goals,
  });

  final IconData icon;
  final String message;
  final AppAccent accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shades = context.accent(accent);
    return Semantics(
      container: true,
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
              Icon(icon, size: AppSizes.iconSm, color: shades.onContainer),
              AppGap.hSm,
              Expanded(
                child: Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: shades.onContainer,
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
