import 'package:flutter/widgets.dart';

import 'package:family_hub/core/design/design.dart';

/// Lays out colourful action tiles (`ActionTile`) in rows of equally wide
/// cells: two per row on phones, up to four on wide screens (fewer at large
/// text sizes). The tiles of a row share the height of the tallest one, so
/// they line up while long labels / large text still grow them.
class FamilyActionGrid extends StatelessWidget {
  const FamilyActionGrid({super.key, required this.children});

  final List<Widget> children;

  /// Content width per column from which another column fits, at 1× text.
  static const double _minCellWidth = AppSizes.maxContentWidth / 4;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale =
            MediaQuery.textScalerOf(context).scale(AppSpacing.lg) /
            AppSpacing.lg;
        final fit = (constraints.maxWidth / (_minCellWidth * textScale))
            .floor();
        final count = children.length;
        final columns = fit >= count ? count : (count < 2 ? count : 2);
        final rows = <Widget>[];
        for (var start = 0; start < children.length; start += columns) {
          if (rows.isNotEmpty) rows.add(AppGap.sm);
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var c = 0; c < columns; c++) ...[
                    if (c > 0) AppGap.hSm,
                    Expanded(
                      child: start + c < children.length
                          ? children[start + c]
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        );
      },
    );
  }
}
