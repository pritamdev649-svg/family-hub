import 'package:flutter/material.dart';

import 'package:family_hub/features/dashboard/domain/dashboard_data.dart';
import 'package:family_hub/features/dashboard/presentation/dashboard_layout.dart';
import 'package:family_hub/features/dashboard/presentation/widgets/dashboard_member_tile.dart';

/// The "Family board": every member with their task progress, one column on
/// phones and two on wide screens (rows share the height of their tallest
/// card). While the caller is alone in the family the getting-started card
/// invites them to add members instead.
class DashboardMembersBoard extends StatelessWidget {
  const DashboardMembersBoard({super.key, required this.data});

  final DashboardData data;

  @override
  Widget build(BuildContext context) {
    final meId = data.me.id;
    final tiles = [
      for (final s in data.members)
        DashboardMemberTile(
          key: ValueKey('dashboard-member-${s.member.id}'),
          stats: s,
          isMe: s.member.id == meId,
        ),
    ];
    if (tiles.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) => DashboardLayout.grid(
        columns: DashboardLayout.isWide(context, constraints.maxWidth) ? 2 : 1,
        children: tiles,
      ),
    );
  }
}
