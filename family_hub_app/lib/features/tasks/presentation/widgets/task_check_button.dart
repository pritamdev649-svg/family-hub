import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';

/// Round, violet "done" checkbox of a task (48 dp target).
///
/// Built on the Material [Checkbox] (checkbox semantics, keyboard / switch
/// access and the animated check mark come for free), painted as a circle:
/// a thin neutral ring while pending, a solid tasks-violet disc with a white
/// check once done. Ticking it off plays a short "pop" (skipped when the
/// platform asks for reduced motion). [onChanged] `null` renders the
/// disabled state (e.g. while the change is being saved).
class TaskCheckButton extends StatefulWidget {
  const TaskCheckButton({
    super.key,
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  /// What a tap does, e.g. "Mark as done".
  final String semanticLabel;

  @override
  State<TaskCheckButton> createState() => _TaskCheckButtonState();
}

class _TaskCheckButtonState extends State<TaskCheckButton>
    with SingleTickerProviderStateMixin {
  /// Material's checkbox is [Checkbox.width] wide; draw it icon-sized.
  static const double _scale = AppSizes.iconMd / Checkbox.width;

  /// Peak of the "pop" when a task is ticked off (relative scale).
  static const double _popPeak = 1.25;

  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: AppDurations.normal,
  );

  late final Animation<double> _popScale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 1,
        end: _popPeak,
      ).chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 1,
    ),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: _popPeak,
        end: 1,
      ).chain(CurveTween(curve: Curves.easeInCubic)),
      weight: 1,
    ),
  ]).animate(_pop);

  @override
  void didUpdateWidget(TaskCheckButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.value &&
        widget.value &&
        !MediaQuery.disableAnimationsOf(context)) {
      _pop.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final violet = context.accent(AppAccents.tasks).base;
    final onChanged = widget.onChanged;

    // The fixed box keeps the tap target at 48 dp: the scaled checkbox must
    // not steal taps from the tile around it.
    return SizedBox.square(
      dimension: AppSizes.minTapTarget,
      child: AnimatedBuilder(
        animation: _popScale,
        builder: (context, child) =>
            Transform.scale(scale: _scale * _popScale.value, child: child),
        child: Checkbox(
          value: widget.value,
          semanticLabel: widget.semanticLabel,
          onChanged: onChanged == null
              ? null
              : (value) => onChanged(value ?? !widget.value),
          shape: const CircleBorder(),
          materialTapTargetSize: MaterialTapTargetSize.padded,
          checkColor: Colors.white,
          fillColor: WidgetStateProperty.resolveWith((states) {
            if (!states.contains(WidgetState.selected)) {
              return Colors.transparent;
            }
            return states.contains(WidgetState.disabled)
                ? violet.withValues(alpha: AppColors.scrimOpacity)
                : violet;
          }),
          overlayColor: WidgetStatePropertyAll(
            violet.withValues(alpha: AppColors.tintOpacity),
          ),
          side: WidgetStateBorderSide.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return BorderSide.none;
            return BorderSide(
              color: states.contains(WidgetState.disabled)
                  ? scheme.outlineVariant
                  : scheme.outline,
              // Stays a thin line after scaling.
              width: AppSizes.checkboxBorder / _scale,
            );
          }),
        ),
      ),
    );
  }
}

/// Read-only counterpart of [TaskCheckButton] for members who may not
/// change the task: a violet disc with a check when done, a neutral ring
/// while pending.
class TaskStatusMark extends StatelessWidget {
  const TaskStatusMark({
    super.key,
    required this.done,
    required this.semanticLabel,
  });

  final bool done;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: AppSizes.minTapTarget,
      child: Center(
        child: done
            ? Container(
                width: AppSizes.iconMd,
                height: AppSizes.iconMd,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.accent(AppAccents.tasks).base,
                ),
                alignment: Alignment.center,
                child: Icon(
                  AppIcons.check,
                  size: AppSizes.iconXs,
                  color: Colors.white,
                  semanticLabel: semanticLabel,
                ),
              )
            : Icon(
                AppIcons.taskPending,
                size: AppSizes.iconMd,
                color: scheme.outline,
                semanticLabel: semanticLabel,
              ),
      ),
    );
  }
}
