import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/widgets/widgets.dart';

/// The family shortcuts at the top of the More tab: solid colourful
/// [ActionTile]s in each module's accent — members, notice board, emergency
/// cards and SOS history. Two by two on phones, one row of four when there
/// is room (tablets, landscape; large text needs proportionally more room).
class SettingsShortcuts extends StatelessWidget {
  const SettingsShortcuts({super.key});

  /// Content width (at 1× text) from which the four tiles share one row.
  static const double _wideMinWidth = AppSizes.maxContentWidth * 0.75;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tiles = [
      ActionTile(
        icon: AppIcons.members,
        label: l10n.settingsMembers,
        accent: AppAccents.family,
        onTap: () => context.push(AppRoutes.members),
      ),
      ActionTile(
        icon: AppIcons.notice,
        label: l10n.settingsNoticeBoard,
        accent: AppAccents.notices,
        onTap: () => context.push(AppRoutes.notices),
      ),
      ActionTile(
        icon: AppIcons.emergencyCard,
        label: l10n.settingsEmergencyCards,
        accent: AppAccents.emergency,
        onTap: () => context.push(AppRoutes.emergencyCards),
      ),
      ActionTile(
        icon: AppIcons.history,
        label: l10n.settingsSosHistory,
        accent: AppAccents.sos,
        onTap: () => context.push(AppRoutes.sosHistory),
      ),
    ];

    return Semantics(
      container: true,
      label: l10n.settingsSectionFamily,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final textScale =
              MediaQuery.textScalerOf(context).scale(AppSpacing.lg) /
              AppSpacing.lg;
          final columns = constraints.maxWidth >= _wideMinWidth * textScale
              ? tiles.length
              : 2;
          return _Grid(columns: columns, children: tiles);
        },
      ),
    );
  }
}

/// Rows of [columns] equally wide cells; the cells of a row share the
/// height of the tallest one, so tiles line up while long labels / large
/// text still grow them.
class _Grid extends StatelessWidget {
  const _Grid({required this.columns, required this.children});

  final int columns;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
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
  }
}
