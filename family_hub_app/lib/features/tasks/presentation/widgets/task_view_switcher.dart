import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/features/tasks/application/tasks_filter.dart';
import 'package:family_hub/features/tasks/presentation/task_text_measure.dart';
import 'package:family_hub/features/tasks/presentation/tasks_labels.dart';

/// My tasks / Family / Done segmented control of the Tasks tab: a
/// borderless track with a solid violet pill that slides to the selected
/// segment (white label and icon on it). With large text (or long words)
/// the icon moves above the label and labels wrap onto two lines; the pill
/// follows the row's height.
class TaskViewSwitcher extends StatelessWidget {
  const TaskViewSwitcher({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final TasksView selected;
  final ValueChanged<TasksView> onSelected;

  @override
  Widget build(BuildContext context) {
    const views = TasksView.values;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : AppDurations.normal;
    final index = views.indexOf(selected);

    return LayoutBuilder(
      builder: (context, constraints) {
        final slot = constraints.maxWidth / views.length;
        final word = longestWordWidth(context, [
          for (final v in views) v.label(context.l10n),
        ], Theme.of(context).textTheme.labelLarge);
        final stacked =
            word + AppSizes.iconSm + AppSpacing.xs > slot - 2 * AppSpacing.xs;
        return Stack(
          children: [
            AnimatedPositionedDirectional(
              duration: duration,
              curve: Curves.easeOutCubic,
              start: slot * index,
              width: slot,
              top: 0,
              bottom: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppAccents.tasks.dark,
                  borderRadius: AppRadius.brLg,
                ),
              ),
            ),
            // Equal-height segments, also when one label wraps.
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final view in views)
                    Expanded(
                      child: _Segment(
                        view: view,
                        selected: view == selected,
                        stacked: stacked,
                        duration: duration,
                        onTap: () => onSelected(view),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.view,
    required this.selected,
    required this.stacked,
    required this.duration,
    required this.onTap,
  });

  final TasksView view;
  final bool selected;

  /// Icon above the label instead of before it.
  final bool stacked;
  final Duration duration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected ? Colors.white : theme.colorScheme.onSurfaceVariant;

    return Semantics(
      container: true,
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: InkWell(
        onTap: selected ? null : onTap,
        borderRadius: AppRadius.brLg,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSizes.minTapTarget),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.sm,
            ),
            child: Flex(
              direction: stacked ? Axis.vertical : Axis.horizontal,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TweenAnimationBuilder<Color?>(
                  duration: duration,
                  tween: ColorTween(end: color),
                  builder: (context, c, _) =>
                      Icon(view.icon, size: AppSizes.iconSm, color: c),
                ),
                stacked ? AppGap.xxs : AppGap.hXs,
                Flexible(
                  child: AnimatedDefaultTextStyle(
                    duration: duration,
                    style: (theme.textTheme.labelLarge ?? const TextStyle())
                        .copyWith(color: color),
                    child: Text(
                      view.label(context.l10n),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
