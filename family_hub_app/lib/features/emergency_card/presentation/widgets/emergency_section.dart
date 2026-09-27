import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/widgets/widgets.dart';

/// Title row of an emergency card section: a solid [IconBadge] in the
/// section's [accent], the [title] and an optional small [trailing] text
/// (e.g. "2 of 20").
class EmergencySectionTitle extends StatelessWidget {
  const EmergencySectionTitle({
    super.key,
    required this.icon,
    required this.accent,
    required this.title,
    this.trailing,
    this.trailingColor,
  });

  final IconData icon;
  final AppAccent accent;
  final String title;
  final String? trailing;

  /// Colour of [trailing]; defaults to `onSurfaceVariant`.
  final Color? trailingColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        IconBadge(icon: icon, accent: accent, size: AppSizes.badgeSm),
        AppGap.hMd,
        Expanded(
          child: Semantics(
            header: true,
            child: Text(title, style: theme.textTheme.titleSmall),
          ),
        ),
        if (trailing != null) ...[
          AppGap.hSm,
          Text(
            trailing!,
            style: theme.textTheme.labelMedium?.copyWith(
              color: trailingColor ?? theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// Borderless [AppCard] with an [EmergencySectionTitle] above [child].
class EmergencySectionCard extends StatelessWidget {
  const EmergencySectionCard({
    super.key,
    required this.icon,
    required this.accent,
    required this.title,
    required this.child,
    this.trailing,
    this.trailingColor,
  });

  final IconData icon;
  final AppAccent accent;
  final String title;
  final String? trailing;
  final Color? trailingColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          EmergencySectionTitle(
            icon: icon,
            accent: accent,
            title: title,
            trailing: trailing,
            trailingColor: trailingColor,
          ),
          AppGap.md,
          child,
        ],
      ),
    );
  }
}

/// Empty / unavailable / no-permission state as a card: a large solid
/// [IconBadge] in the module accent, a title, an optional message and one
/// action. Sits in the content column below a gradient header, or — with
/// [centered] — in the middle of a plain screen (scrolls with large text).
// TODO(visual-qa): core `EmptyState` has no accent; once it gets one this can
// become `EmptyState(accent: …)` (handoff in docs/progress/rd-emergency.md).
class EmergencyStateCard extends StatelessWidget {
  const EmergencyStateCard({
    super.key,
    required this.icon,
    required this.title,
    required this.accent,
    this.message,
    this.action,
    this.centered = false,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final AppAccent accent;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final card = AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconBadge(icon: icon, accent: accent, size: AppSizes.badgeLg),
          AppGap.lg,
          Semantics(
            header: true,
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
          ),
          if (message != null && message!.isNotEmpty) ...[
            AppGap.sm,
            Text(
              message!,
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
    if (!centered) return card;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Center(
      child: SingleChildScrollView(
        padding: AppSpacing.screen.copyWith(bottom: AppSpacing.lg + bottom),
        child: card,
      ),
    );
  }
}
