import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/features/tasks/domain/family_task.dart';
import 'package:family_hub/features/tasks/presentation/tasks_labels.dart';

/// Colourful Low / Medium / High segmented picker: each option is a soft
/// tile in its priority accent (sky, amber, rose) with a thin icon; the
/// selected one turns solid with white text. Icons sit above the labels so
/// three segments fit side by side even with large text.
class TaskPrioritySelector extends StatelessWidget {
  const TaskPrioritySelector({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final TaskPriority selected;

  /// `null` disables the picker.
  final ValueChanged<TaskPriority>? onSelected;

  @override
  Widget build(BuildContext context) {
    final select = onSelected;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, p) in TaskPriority.values.indexed) ...[
            if (i > 0) AppGap.hSm,
            Expanded(
              child: _PrioritySegment(
                priority: p,
                selected: p == selected,
                onTap: select == null ? null : () => select(p),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PrioritySegment extends StatelessWidget {
  const _PrioritySegment({
    required this.priority,
    required this.selected,
    required this.onTap,
  });

  final TaskPriority priority;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final accent = priority.accent;
    final shades = context.accent(accent);
    final foreground = selected ? Colors.white : shades.onContainer;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : AppDurations.normal;

    return Semantics(
      container: true,
      button: true,
      selected: selected,
      enabled: onTap != null,
      inMutuallyExclusiveGroup: true,
      label: l10n.tasksPrioritySemantics(priority.label(l10n)),
      onTap: onTap,
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: duration,
        curve: Curves.easeOutCubic,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: selected ? accent.dark : shades.container,
          borderRadius: AppRadius.brLg,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: AppSizes.minTapTarget,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: AppSpacing.md,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      priority.icon,
                      size: AppSizes.iconSm,
                      color: selected ? Colors.white : shades.foreground,
                    ),
                    AppGap.xs,
                    Text(
                      priority.label(l10n),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: foreground,
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
