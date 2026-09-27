import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';

/// Single-choice chips that wrap onto multiple lines (categories,
/// priorities, filters). Selecting the current option again keeps it selected.
class ChoiceChipsField<T> extends StatelessWidget {
  const ChoiceChipsField({
    super.key,
    required this.options,
    required this.selected,
    required this.label,
    required this.onSelected,
    this.icon,
  });

  final List<T> options;
  final T? selected;
  final String Function(T) label;
  final ValueChanged<T> onSelected;
  final IconData Function(T)? icon;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final option in options)
          ChoiceChip(
            label: Text(label(option)),
            selected: option == selected,
            avatar: icon == null ? null : Icon(icon!(option)),
            onSelected: (_) => onSelected(option),
          ),
      ],
    );
  }
}
