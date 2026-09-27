import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';

/// Dropdown form field styled like [AppTextField].
///
/// * Controlled by [value]; a value that is not in [items] is shown as empty
///   (instead of crashing) so stale selections are safe.
/// * [onChanged] `null` disables the field.
/// * Menu rows grow with large text (no fixed item height).
class AppDropdownField<T> extends StatelessWidget {
  const AppDropdownField({
    super.key,
    required this.label,
    this.value,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
    this.validator,
    this.leading,
  });

  final String label;
  final T? value;
  final List<T> items;
  final String Function(T) itemLabel;
  final ValueChanged<T?>? onChanged;
  final String? Function(T?)? validator;
  final Widget Function(T)? leading;

  @override
  Widget build(BuildContext context) {
    final selected = value != null && items.contains(value) ? value : null;

    Widget row(T item) {
      final text = Text(
        itemLabel(item),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
      if (leading == null) return text;
      return Row(
        children: [
          leading!(item),
          AppGap.hMd,
          Flexible(child: text),
        ],
      );
    }

    return DropdownButtonFormField<T>(
      initialValue: selected,
      isExpanded: true,
      itemHeight: null,
      borderRadius: AppRadius.brMd,
      icon: const Icon(AppIcons.expand),
      decoration: InputDecoration(labelText: label),
      validator: validator,
      onChanged: onChanged,
      items: [
        for (final item in items)
          DropdownMenuItem<T>(value: item, child: row(item)),
      ],
    );
  }
}
