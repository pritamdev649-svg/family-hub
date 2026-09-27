import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/features/family/presentation/family_style.dart';

// Frosted white building blocks for content on the family screens' blue
// gradient header (same look as the dashboard header's glass stats).

/// Top row of a gradient header: a frosted back button (only when there is
/// a page to go back to, like an `AppBar`) and optional trailing [actions].
/// Renders nothing when there is neither.
class FamilyHeaderBar extends StatelessWidget {
  const FamilyHeaderBar({super.key, this.actions = const []});

  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final canGoBack = ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
    if (!canGoBack && actions.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        if (canGoBack)
          FamilyGlassIconButton(
            icon: AppIcons.back,
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            // `maybePop` respects `PopScope` like the app bar's back button.
            onPressed: () => Navigator.maybePop(context),
          ),
        const Spacer(),
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) AppGap.hSm,
          actions[i],
        ],
      ],
    );
  }
}

/// Round frosted icon button with a white thin icon (48 dp target).
class FamilyGlassIconButton extends StatelessWidget {
  const FamilyGlassIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: FamilyStyle.glassFill),
        foregroundColor: Colors.white,
        disabledForegroundColor: Colors.white.withValues(
          alpha: FamilyStyle.glassDisabled,
        ),
        minimumSize: const Size.square(AppSizes.minTapTarget),
      ),
      icon: Icon(icon, size: AppSizes.iconMd),
    );
  }
}

/// Frosted pill with a big number and a short label (header statistics).
class FamilyGlassStat extends StatelessWidget {
  const FamilyGlassStat({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: FamilyStyle.glassFill),
          borderRadius: AppRadius.brLg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: AppSizes.iconXs, color: Colors.white),
                AppGap.hXs,
                Flexible(
                  child: Text(
                    value,
                    maxLines: 1,
                    style: theme.textTheme.titleLarge
                        ?.merge(AppTypography.tabularFigures)
                        .copyWith(color: Colors.white),
                  ),
                ),
              ],
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: FamilyStyle.mutedOnGradient,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small frosted pill with an optional thin icon (role, age, "You" on the
/// member header). Wraps its label onto several lines with large text.
class FamilyGlassPill extends StatelessWidget {
  const FamilyGlassPill({super.key, required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: FamilyStyle.glassFillStrong),
        borderRadius: AppRadius.brPill,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: AppSizes.iconXs, color: Colors.white),
              AppGap.hXs,
            ],
            Flexible(
              child: Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Wraps [child] so that `AppButton`s with the `tonal` variant inside it
/// render as frosted white buttons (white label and icon) — for actions on
/// a gradient card. Keeps AppButton's busy / disabled handling.
class FamilyFrostedButtons extends StatelessWidget {
  const FamilyFrostedButtons({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final frosted = FilledButton.styleFrom(
      backgroundColor: Colors.white.withValues(
        alpha: FamilyStyle.glassFillStrong,
      ),
      foregroundColor: Colors.white,
      overlayColor: Colors.white,
      disabledBackgroundColor: Colors.white.withValues(
        alpha: FamilyStyle.glassFill,
      ),
      disabledForegroundColor: Colors.white.withValues(
        alpha: FamilyStyle.glassDisabled,
      ),
      elevation: 0,
    );
    return Theme(
      data: theme.copyWith(
        filledButtonTheme: FilledButtonThemeData(
          style: frosted.merge(theme.filledButtonTheme.style),
        ),
      ),
      child: child,
    );
  }
}
