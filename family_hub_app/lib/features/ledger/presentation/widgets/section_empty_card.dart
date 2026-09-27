import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/widgets/widgets.dart';

/// Compact empty state for one section of a scrolling screen (the full-area
/// `EmptyState` would dominate a section): a soft [IconBadge] in the
/// section's [accent], a friendly title, an optional message and action.
class SectionEmptyCard extends StatelessWidget {
  const SectionEmptyCard({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.accent = AppAccents.money,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final AppAccent accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: IconBadge(icon: icon, accent: accent, soft: true),
          ),
          AppGap.hMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                if (message != null) ...[
                  AppGap.xs,
                  Text(
                    message!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (action != null) ...[AppGap.md, action!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
