import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/widgets/widgets.dart';

/// Friendly empty / info state of the tasks feature inside a borderless
/// card: a large solid [IconBadge] in the given [accent], a title, an
/// optional message and one optional action. Sized by its content, so it
/// works inside scroll views (unlike the full-area `EmptyState`).
class TaskStateCard extends StatelessWidget {
  const TaskStateCard({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.accent = AppAccents.tasks,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final AppAccent accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = message;
    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.xxl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: IconBadge(
              icon: icon,
              accent: accent,
              size: AppSizes.badgeLg,
            ),
          ),
          AppGap.lg,
          Semantics(
            header: true,
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
          ),
          if (text != null && text.isNotEmpty) ...[
            AppGap.sm,
            Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (action != null) ...[AppGap.xl, action!],
        ],
      ),
    );
  }
}
