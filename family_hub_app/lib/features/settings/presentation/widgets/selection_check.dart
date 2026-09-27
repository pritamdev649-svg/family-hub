import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';

/// Marker of the chosen option in a single-choice list (language, theme,
/// location sharing): a solid [accent] circle with a thin white check.
/// Renders an empty, equally sized box when not [selected] so rows keep the
/// same layout. Purely visual — the row carries the selected semantics.
class SelectionCheck extends StatelessWidget {
  const SelectionCheck({
    super.key,
    required this.selected,
    this.accent = AppAccents.brand,
    this.size = AppSizes.iconMd,
  });

  final bool selected;
  final AppAccent accent;
  final double size;

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : AppDurations.fast;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: AnimatedSwitcher(
          duration: duration,
          switchInCurve: Curves.easeOutCubic,
          transitionBuilder: (child, animation) =>
              ScaleTransition(scale: animation, child: child),
          child: selected
              ? DecoratedBox(
                  key: const ValueKey(true),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppGradients.of(accent),
                  ),
                  child: Center(
                    child: Icon(
                      AppIcons.check,
                      size: size * 0.6,
                      color: Colors.white,
                    ),
                  ),
                )
              : const SizedBox.shrink(key: ValueKey(false)),
        ),
      ),
    );
  }
}
