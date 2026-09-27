import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/ledger/domain/ledger_entry.dart';
import 'package:family_hub/features/ledger/presentation/ledger_labels.dart';

/// Category picker of the entry form: a grid of [LedgerCategoryTile]s —
/// pale badges, the chosen one turns into a solid badge in the category's
/// colour on a soft tint. As many columns as fit (at least [minColumns]);
/// tiles grow with the text size so labels wrap between words, not inside
/// them.
class LedgerCategoryGrid extends StatelessWidget {
  const LedgerCategoryGrid({
    super.key,
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  final List<LedgerCategory> categories;
  final LedgerCategory? selected;

  /// Null makes the grid read-only (saving, goal contribution).
  final ValueChanged<LedgerCategory>? onSelected;

  static const int minColumns = 2;

  /// Narrowest a tile may get (at normal text size) before a column is
  /// dropped.
  static const double minTileWidth = AppSizes.badgeMd + AppSpacing.xxl;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = AppSpacing.sm;
        final width = constraints.maxWidth;
        final minWidth = MediaQuery.textScalerOf(context).scale(minTileWidth);
        final fit = ((width + spacing) / (minWidth + spacing)).floor();
        final columns = fit < minColumns ? minColumns : fit;
        final tileWidth = (width - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final category in categories)
              SizedBox(
                width: tileWidth,
                child: LedgerCategoryTile(
                  category: category,
                  selected: category == selected,
                  onTap: onSelected == null
                      ? null
                      : () => onSelected!(category),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// One category of [LedgerCategoryGrid]: badge above a short label, a
/// selectable ≥ 48 dp button ("Groceries, selected").
class LedgerCategoryTile extends StatelessWidget {
  const LedgerCategoryTile({
    super.key,
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final LedgerCategory category;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final shades = context.accent(category.accent);
    final animate = !MediaQuery.disableAnimationsOf(context);

    return Semantics(
      button: true,
      selected: selected,
      enabled: onTap != null,
      inMutuallyExclusiveGroup: true,
      child: AnimatedContainer(
        duration: animate ? AppDurations.fast : Duration.zero,
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: selected ? shades.container : Colors.transparent,
          borderRadius: AppRadius.brLg,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: AppRadius.brLg,
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: AppSizes.minTapTarget,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: AppSpacing.sm,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconBadge(
                      icon: category.icon,
                      accent: category.accent,
                      soft: !selected,
                    ),
                    AppGap.xs,
                    Text(
                      category.label(l10n),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: selected
                            ? shades.onContainer
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
