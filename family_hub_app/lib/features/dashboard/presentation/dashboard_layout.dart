import 'package:flutter/widgets.dart';

import 'package:family_hub/core/design/design.dart';

/// Responsive rules of the dashboard.
abstract final class DashboardLayout {
  /// Content width from which the dashboard uses its wide layout (family
  /// board in two columns, quick actions in one row): tablets and landscape
  /// phones. Derived from the content width cap so it scales with the
  /// design system.
  static const double wideMinWidth = AppSizes.maxContentWidth * 0.75;

  /// Whether [width] is wide enough for the wide layout at the current text
  /// size: large text needs proportionally more room, so at 1.4× text a
  /// phone keeps the single-column layout.
  static bool isWide(BuildContext context, double width) {
    final textScale =
        MediaQuery.textScalerOf(context).scale(AppSpacing.lg) / AppSpacing.lg;
    return width >= wideMinWidth * textScale;
  }

  /// Lays out [children] in rows of [columns] equally wide cells; the cells
  /// of a row share the height of the tallest one (so cards line up while
  /// long names / large text still grow them).
  static Widget grid({
    required List<Widget> children,
    required int columns,
    double spacing = AppSpacing.sm,
  }) {
    if (columns <= 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(height: spacing),
            children[i],
          ],
        ],
      );
    }
    final rows = <Widget>[];
    for (var start = 0; start < children.length; start += columns) {
      final cells = <Widget>[];
      for (var c = 0; c < columns; c++) {
        final index = start + c;
        if (c > 0) cells.add(SizedBox(width: spacing));
        cells.add(
          Expanded(
            child: index < children.length
                ? children[index]
                : const SizedBox.shrink(),
          ),
        );
      }
      if (rows.isNotEmpty) rows.add(SizedBox(height: spacing));
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: cells,
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}
