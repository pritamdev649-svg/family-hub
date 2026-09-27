import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/utils/validators.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/family/domain/family_limits.dart';
import 'package:family_hub/features/family/domain/member_designation.dart';
import 'package:family_hub/features/family/presentation/family_labels.dart';
import 'package:family_hub/features/family/presentation/family_style.dart';
import 'package:family_hub/features/family/presentation/widgets/family_choice_chips.dart';

/// Free-text designation ("company title") with age-appropriate, colourful
/// suggestion chips; tapping a chip fills the field with its localised label.
class DesignationField extends StatelessWidget {
  const DesignationField({
    super.key,
    required this.controller,
    required this.suggestions,
    this.enabled = true,
    this.validator,
  });

  final TextEditingController controller;
  final List<DesignationSuggestion> suggestions;
  final bool enabled;

  /// Extra check after the length limit (e.g. an error the server reported
  /// for this field).
  final FormFieldValidator<String>? validator;

  void _pick(String label) {
    controller.value = TextEditingValue(
      text: label,
      selection: TextSelection.collapsed(offset: label.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          controller: controller,
          label: l10n.familyInfoDesignation,
          hint: l10n.familyDesignationHint,
          prefixIcon: AppIcons.designation,
          maxLength: FamilyLimits.designation,
          enabled: enabled,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          validator: Validators.compose([
            Validators.maxLength(l10n, FamilyLimits.designation),
            ?validator,
          ]),
        ),
        if (suggestions.isNotEmpty) ...[
          AppGap.sm,
          Row(
            children: [
              Icon(
                AppIcons.sparkle,
                size: AppSizes.iconXs,
                color: context.accent(FamilyStyle.accent).foreground,
              ),
              AppGap.hXs,
              Expanded(
                child: Text(
                  l10n.familyDesignationSuggestions,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          AppGap.sm,
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              final current = value.text.trim();
              return FamilyChoiceChips<DesignationSuggestion>(
                options: suggestions,
                selected: null,
                isSelected: (s) => s.label(l10n) == current,
                label: (s) => s.label(l10n),
                // Each suggestion keeps its own colour.
                accentOf: (s) => FamilyStyle.cycle(s.index),
                enabled: enabled,
                onSelected: (s) => _pick(s.label(l10n)),
              );
            },
          ),
        ],
      ],
    );
  }
}
