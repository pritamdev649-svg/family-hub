import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/utils/formatters.dart';

/// Date form field: shows the localised date ([Fmt.date]) and opens the
/// Material date picker (in the app locale) on tap.
///
/// Controlled: the displayed date is always [value]; the picked date is
/// reported through [onChanged] as a local date at midnight. [validator]
/// participates in the enclosing [Form].
class DatePickerField extends ConsumerWidget {
  const DatePickerField({
    super.key,
    required this.label,
    this.value,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
    this.allowClear = true,
    this.validator,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final bool allowClear;
  final String? Function(DateTime?)? validator;

  /// Earliest selectable date when [firstDate] is not given.
  static final DateTime defaultFirstDate = DateTime(1900);

  Future<void> _pick(
    BuildContext context,
    FormFieldState<DateTime> field,
  ) async {
    final now = DateTime.now();
    final first = DateUtils.dateOnly((firstDate ?? defaultFirstDate).toLocal());
    var last = DateUtils.dateOnly(
      (lastDate ?? DateTime(now.year + 50, 12, 31)).toLocal(),
    );
    if (last.isBefore(first)) last = first;

    var initial = DateUtils.dateOnly((value ?? now).toLocal());
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: label,
    );
    if (picked == null) return;
    field.didChange(picked);
    onChanged(picked);
  }

  void _clear(FormFieldState<DateTime> field) {
    field.didChange(null);
    onChanged(null);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = ref.watch(fmtProvider);
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final current = value;
    final display = current == null ? null : fmt.date(current);

    return FormField<DateTime>(
      initialValue: current,
      // Always validate the controlled [value], not the field's internal copy.
      validator: validator == null ? null : (_) => validator!(value),
      builder: (field) {
        final enabled = field.widget.enabled;
        return Semantics(
          button: true,
          enabled: enabled,
          label: label,
          value: display,
          child: InkWell(
            borderRadius: AppRadius.brMd,
            onTap: enabled ? () => _pick(context, field) : null,
            child: InputDecorator(
              isEmpty: display == null,
              decoration: InputDecoration(
                labelText: label,
                errorText: field.errorText,
                enabled: enabled,
                prefixIcon: const Icon(AppIcons.calendar),
                suffixIcon: allowClear && current != null && enabled
                    ? IconButton(
                        tooltip: l10n.widgetClearDate,
                        icon: const Icon(AppIcons.clear),
                        onPressed: () => _clear(field),
                      )
                    : null,
              ),
              child: Text(display ?? '', style: theme.textTheme.bodyLarge),
            ),
          ),
        );
      },
    );
  }
}
