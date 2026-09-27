import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/utils/formatters.dart';

/// Frosted-white elements that sit on the tasks gradient headers (Tasks tab,
/// task detail). Text and icons are white; the frosted fill is a translucent
/// white so the header gradient shows through.
abstract final class TaskGlass {
  /// Opacity of the frosted fill of pills and buttons on a gradient.
  static const double fill = 0.16;

  /// Opacity of secondary white text on a gradient.
  static const double muted = 0.85;

  /// Opacity of the empty track of a progress bar on a gradient.
  static const double track = 0.25;

  static Color get fillColor => Colors.white.withValues(alpha: fill);
  static Color get mutedColor => Colors.white.withValues(alpha: muted);
}

/// Frosted pill with a big number and a label (header counters). While
/// [value] is `null` (loading) only the label shows; the number fades in.
///
/// Stacked (number above label) by default; [inline] lays icon, number and
/// label out in one full-width row for narrow screens / large text.
class TaskGlassStat extends StatelessWidget {
  const TaskGlassStat({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.highlight = false,
    this.inline = false,
  });

  /// Style of the label (used to measure whether pills fit side by side).
  static TextStyle? labelStyle(ThemeData theme) =>
      theme.textTheme.labelSmall?.copyWith(color: TaskGlass.mutedColor);

  /// Horizontal padding inside a pill.
  static const double padding = AppSpacing.md;

  final IconData icon;

  /// Formatted number, `null` while unknown.
  final String? value;
  final String label;

  /// Draws attention (e.g. overdue tasks): a slightly brighter fill.
  final bool highlight;

  /// One row instead of number-above-label.
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final known = value != null;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : AppDurations.normal;

    final number = ExcludeSemantics(
      excluding: !known,
      child: AnimatedOpacity(
        duration: duration,
        opacity: known ? 1 : 0,
        child: Text(
          // An invisible stand-in keeps the height while loading, so the
          // header does not jump.
          value ?? '0',
          maxLines: 1,
          overflow: TextOverflow.fade,
          softWrap: false,
          style: theme.textTheme.titleLarge
              ?.merge(AppTypography.tabularFigures)
              .copyWith(color: Colors.white),
        ),
      ),
    );
    final text = Text(
      label,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: labelStyle(theme),
    );
    final glyph = Icon(icon, size: AppSizes.iconXs, color: Colors.white);

    return MergeSemantics(
      child: AnimatedContainer(
        duration: duration,
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(
          horizontal: padding,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: Colors.white.withValues(
            alpha: highlight ? TaskGlass.fill * 2 : TaskGlass.fill,
          ),
          borderRadius: AppRadius.brLg,
        ),
        child: inline
            ? Row(
                children: [
                  glyph,
                  AppGap.hSm,
                  number,
                  AppGap.hMd,
                  Expanded(child: text),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      glyph,
                      AppGap.hXs,
                      Flexible(child: number),
                    ],
                  ),
                  text,
                ],
              ),
      ),
    );
  }
}

/// Small frosted pill with a thin icon and a label (status, priority,
/// category on the detail header). [emphasis] renders it solid white with
/// [emphasisColor] text instead, for states that need attention (overdue).
class TaskGlassPill extends StatelessWidget {
  const TaskGlassPill({
    super.key,
    required this.icon,
    required this.label,
    this.emphasis = false,
    this.emphasisColor,
  });

  final IconData icon;
  final String label;
  final bool emphasis;
  final Color? emphasisColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = emphasis
        ? (emphasisColor ?? theme.colorScheme.error)
        : Colors.white;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: emphasis ? Colors.white : TaskGlass.fillColor,
        borderRadius: AppRadius.brPill,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: AppSizes.iconXs, color: foreground),
            AppGap.hXs,
            Flexible(
              child: Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(color: foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// White rounded progress bar on a gradient with a label and the
/// percentage. [value] `null` shows an empty track without a percentage.
class TaskGlassProgress extends ConsumerWidget {
  const TaskGlassProgress({
    super.key,
    required this.label,
    required this.value,
  });

  final String label;

  /// 0–1, `null` when there is nothing to measure yet.
  final double? value;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final fmt = ref.watch(fmtProvider);
    final v = value;
    final target = v == null || !v.isFinite ? 0.0 : v.clamp(0.0, 1.0);
    final percent = v == null ? null : fmt.percent(target);

    return Semantics(
      container: true,
      label: label,
      value: percent == null ? null : context.l10n.widgetProgressLabel(percent),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: TaskGlass.mutedColor,
                    ),
                  ),
                ),
                if (percent != null) ...[
                  AppGap.hSm,
                  Text(
                    percent,
                    style: theme.textTheme.labelLarge
                        ?.merge(AppTypography.tabularFigures)
                        .copyWith(color: Colors.white),
                  ),
                ],
              ],
            ),
            AppGap.xs,
            TweenAnimationBuilder<double>(
              tween: Tween<double>(end: target),
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : AppDurations.slow,
              curve: Curves.easeOutCubic,
              builder: (context, animated, _) => LinearProgressIndicator(
                value: animated,
                minHeight: AppSizes.progressBar,
                color: Colors.white,
                backgroundColor: Colors.white.withValues(
                  alpha: TaskGlass.track,
                ),
                borderRadius: AppRadius.brPill,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Round frosted icon button for gradient headers (back, edit, delete).
class TaskGlassIconButton extends StatelessWidget {
  const TaskGlassIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: TaskGlass.fillColor,
        disabledForegroundColor: Colors.white.withValues(
          alpha: TaskGlass.muted / 2,
        ),
        disabledBackgroundColor: Colors.white.withValues(
          alpha: TaskGlass.fill / 2,
        ),
      ),
    );
  }
}
