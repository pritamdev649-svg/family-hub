import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/utils/formatters.dart';

/// Rounded linear progress bar (goals, task completion).
///
/// [value] is clamped to 0–1 (NaN / infinity → 0) and animates smoothly when
/// it changes. Screen readers hear a localised percentage ([Fmt.percent]).
class AppProgressBar extends ConsumerWidget {
  const AppProgressBar({
    super.key,
    required this.value,
    this.color,
    this.height = AppSizes.progressBar,
  });

  final double value;
  final Color? color;
  final double height;

  static double _clamp(double v) => v.isFinite ? v.clamp(0.0, 1.0) : 0.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = ref.watch(fmtProvider);
    final scheme = Theme.of(context).colorScheme;
    final target = _clamp(value);

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: target),
      duration: AppDurations.slow,
      curve: Curves.easeOutCubic,
      builder: (context, animated, _) => ClipRRect(
        borderRadius: AppRadius.brPill,
        child: LinearProgressIndicator(
          value: animated,
          minHeight: height,
          color: color ?? scheme.primary,
          backgroundColor: scheme.surfaceContainerHighest,
          borderRadius: AppRadius.brPill,
          semanticsValue: context.l10n.widgetProgressLabel(fmt.percent(target)),
        ),
      ),
    );
  }
}
