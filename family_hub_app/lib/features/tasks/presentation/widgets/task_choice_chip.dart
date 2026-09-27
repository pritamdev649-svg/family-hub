import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';

/// Borderless, colourful single-choice chip of the tasks feature (due-date
/// and member filters, categories): a card-coloured pill with an
/// accent-coloured thin icon, turning into a solid [accent] pill with white
/// text and icon when [selected].
///
/// The solid colour is the accent's deep shade, so white text on it meets
/// WCAG AA for every accent.
class TaskChoiceChip extends StatelessWidget {
  const TaskChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    required this.accent,
    this.icon,
    this.avatar,
    this.tooltip,
  });

  final String label;
  final bool selected;

  /// `null` disables the chip.
  final VoidCallback? onSelected;
  final AppAccent accent;

  /// Thin leading icon (ignored when [avatar] is given).
  final IconData? icon;

  /// Custom leading widget, e.g. a member avatar.
  final Widget? avatar;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shades = context.accent(accent);
    final foreground = selected ? Colors.white : theme.colorScheme.onSurface;
    final select = onSelected;

    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: select == null ? null : (_) => select(),
      tooltip: tooltip,
      showCheckmark: false,
      avatar:
          avatar ??
          (icon == null
              ? null
              : Icon(
                  icon,
                  size: AppSizes.iconSm,
                  color: selected ? Colors.white : shades.foreground,
                )),
      selectedColor: accent.dark,
      backgroundColor: context.semanticColors.card,
      side: BorderSide.none,
      elevation: 0,
      pressElevation: 0,
      labelStyle: theme.textTheme.labelLarge?.copyWith(color: foreground),
    );
  }
}
