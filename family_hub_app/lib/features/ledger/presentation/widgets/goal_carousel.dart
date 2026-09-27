import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/features/ledger/domain/savings_goal.dart';
import 'package:family_hub/features/ledger/presentation/ledger_labels.dart';
import 'package:family_hub/features/ledger/presentation/widgets/goal_progress_card.dart';

/// Savings goals as a horizontal row of gradient cards ("My cards" in a
/// wallet app) in pink / violet / teal. Each goal keeps its own colour
/// ([SavingsGoalStyle.cardAccent], the same as on the dashboard) unless it
/// would repeat its neighbour's, then it takes the next colour.
///
/// * One goal fills the width (nothing to scroll to).
/// * Several goals: each card takes [cardWidthFactor] of the width so the
///   next one peeks in; all cards share the height of the tallest one
///   (no fixed height, so large text just makes the row taller).
/// * The row is not clipped, so cards scroll out to the screen edge and
///   their coloured glow is not cut off. It scrolls in reading direction
///   (right-to-left in RTL locales).
class GoalCarousel extends StatelessWidget {
  const GoalCarousel({super.key, required this.goals});

  final List<SavingsGoal> goals;

  /// Share of the available width one card takes when there are several.
  static const double cardWidthFactor = 0.78;

  /// Card colours for [goals]: each goal's own colour, shifted to the next
  /// one when it equals the previous card's.
  static List<AppAccent> accentsFor(List<SavingsGoal> goals) {
    final result = <AppAccent>[];
    for (final goal in goals) {
      var accent = goal.cardAccent;
      if (result.isNotEmpty && result.last == accent) {
        final i = goalCardAccents.indexOf(accent);
        accent = goalCardAccents[(i + 1) % goalCardAccents.length];
      }
      result.add(accent);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    if (goals.isEmpty) return const SizedBox.shrink();
    if (goals.length == 1) {
      return GoalProgressCard(
        goals.first,
        key: ValueKey('goal-card-${goals.first.id}'),
      );
    }
    final accents = accentsFor(goals);
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth * cardWidthFactor;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < goals.length; i++) ...[
                  if (i > 0) AppGap.hMd,
                  SizedBox(
                    width: cardWidth,
                    child: GoalProgressCard(
                      goals[i],
                      key: ValueKey('goal-card-${goals[i].id}'),
                      accent: accents[i],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
