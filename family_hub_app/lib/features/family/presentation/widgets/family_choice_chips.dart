import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/features/family/presentation/family_style.dart';

/// Colourful single-choice chips for the family forms (gender, role,
/// designation suggestions). Borderless: unselected chips are a soft tint of
/// their accent, the selected chip is solid with white text and a check mark
/// (so the choice is not shown by colour alone). They stay visible inside
/// an `AppCard`, unlike the theme's card-coloured chips.
class FamilyChoiceChips<T> extends StatelessWidget {
  const FamilyChoiceChips({
    super.key,
    required this.options,
    required this.selected,
    required this.label,
    required this.onSelected,
    this.icon,
    this.accentOf,
    this.accent = FamilyStyle.accent,
    this.enabled = true,
    this.isSelected,
  });

  final List<T> options;
  final T? selected;
  final String Function(T option) label;
  final ValueChanged<T> onSelected;
  final IconData Function(T option)? icon;

  /// Per-option accent; defaults to [accent] for every option.
  final AppAccent Function(T option)? accentOf;
  final AppAccent accent;
  final bool enabled;

  /// Custom selection test (e.g. "the field's text equals this label");
  /// defaults to `option == selected`.
  final bool Function(T option)? isSelected;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final option in options)
          Builder(
            builder: (context) {
              final on = isSelected?.call(option) ?? option == selected;
              final a = accentOf?.call(option) ?? accent;
              final shades = context.accent(a);
              final fg = on ? Colors.white : shades.onContainer;
              final optionIcon = on ? AppIcons.check : icon?.call(option);
              return ChoiceChip(
                selected: on,
                onSelected: enabled ? (_) => onSelected(option) : null,
                showCheckmark: false,
                side: BorderSide.none,
                shape: const StadiumBorder(),
                color: WidgetStatePropertyAll<Color>(
                  on ? FamilyStyle.solid(a) : shades.container,
                ),
                avatar: optionIcon == null
                    ? null
                    : Icon(optionIcon, size: AppSizes.iconSm, color: fg),
                label: Text(
                  label(option),
                  style: textTheme.labelLarge?.copyWith(color: fg),
                ),
              );
            },
          ),
      ],
    );
  }
}
