import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/features/dashboard/presentation/dashboard_layout.dart';

/// Placeholder in the shape of the dashboard's content (quick-action tiles,
/// then a few sections of cards) shown during the first load below the
/// real gradient header, so neither the status bar nor the page jumps when
/// the data arrives. Static on purpose: no shimmer animation (calmer,
/// respects reduced-motion settings, cheap on low-end phones).
///
/// Not scrollable itself: it is one of the children of the dashboard's
/// `GradientHeaderScrollView` (pull to refresh keeps working meanwhile).
class DashboardSkeleton extends StatelessWidget {
  const DashboardSkeleton({super.key});

  /// Height of a quick-action tile: padding, icon badge, gap, one label line.
  static const double _tileHeight =
      AppSpacing.lg * 3 + AppSizes.badgeSm + AppSpacing.xl;

  /// Height of a list card (task, goal, notice).
  static const double _cardHeight = AppSizes.thumbnail + AppSpacing.xl;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Semantics(
      liveRegion: true,
      label: l10n.dashboardLoading,
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = DashboardLayout.isWide(context, constraints.maxWidth);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DashboardLayout.grid(
                  columns: wide ? 4 : 2,
                  children: [
                    for (var i = 0; i < 4; i++)
                      const _Bone(
                        height: _tileHeight,
                        borderRadius: AppRadius.brCard,
                      ),
                  ],
                ),
                for (var i = 0; i < 3; i++) ...[
                  AppGap.xl,
                  const FractionallySizedBox(
                    alignment: AlignmentDirectional.centerStart,
                    widthFactor: 0.4,
                    child: _Bone(height: AppSpacing.xl),
                  ),
                  AppGap.md,
                  const _Bone(
                    height: _cardHeight,
                    borderRadius: AppRadius.brCard,
                  ),
                  AppGap.sm,
                  const _Bone(
                    height: _cardHeight,
                    borderRadius: AppRadius.brCard,
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// One placeholder shape in the surface colour.
class _Bone extends StatelessWidget {
  const _Bone({required this.height, this.borderRadius = AppRadius.brMd});

  final double height;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: borderRadius,
        ),
      ),
    );
  }
}
