import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/widgets/widgets.dart';

/// Compact empty state for one dashboard section (the full-area
/// `EmptyState` would dominate a section of a scrolling screen).
class DashboardEmptyCard extends StatelessWidget {
  const DashboardEmptyCard({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Icon(
                  icon,
                  size: AppSizes.iconMd,
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ),
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
                if (action != null) ...[
                  AppGap.md,
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: action,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
