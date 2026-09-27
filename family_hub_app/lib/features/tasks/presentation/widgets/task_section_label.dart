import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/utils/formatters.dart';
import 'package:family_hub/features/tasks/domain/task_grouping.dart';
import 'package:family_hub/features/tasks/presentation/tasks_labels.dart';

/// Title of one group of the task list (Overdue / Due today / Upcoming /
/// No due date) with a dot in the section's accent and, when known, a soft
/// counter pill.
class TaskSectionLabel extends ConsumerWidget {
  const TaskSectionLabel(this.section, {super.key, this.count});

  /// Diameter of the coloured dot.
  static const double _dot = AppSpacing.sm + AppSpacing.xxs;

  final TaskSection section;

  /// Tasks in the section; `null` hides the counter (e.g. while more pages
  /// can still be loaded).
  final int? count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final shades = context.accent(section.accent);
    final n = count;

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          Container(
            width: _dot,
            height: _dot,
            decoration: BoxDecoration(
              color: shades.base,
              shape: BoxShape.circle,
            ),
          ),
          AppGap.hSm,
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                section.label(context.l10n),
                style: theme.textTheme.titleSmall,
              ),
            ),
          ),
          if (n != null) ...[
            AppGap.hSm,
            ExcludeSemantics(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: shades.container,
                  borderRadius: AppRadius.brPill,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xxs,
                  ),
                  child: Text(
                    ref.watch(fmtProvider).number(n),
                    style: theme.textTheme.labelMedium
                        ?.merge(AppTypography.tabularFigures)
                        .copyWith(color: shades.onContainer),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
