import 'package:flutter/material.dart';

import 'package:family_hub/core/config/countries.dart';
import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/widgets/widgets.dart';

/// Mandatory guardian-consent checkbox for members younger than the family
/// country's digital age of consent (docs/08-COMPLIANCE.md §3 row 3). Names
/// the country's privacy law and blocks the enclosing [Form] until ticked.
class GuardianConsentField extends StatelessWidget {
  const GuardianConsentField({
    super.key,
    required this.country,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final CountryInfo country;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return FormField<bool>(
      initialValue: value,
      // Validate the controlled [value], not the field's internal copy.
      validator: (_) => value ? null : l10n.familyGuardianConsentRequired,
      builder: (field) {
        final error = field.errorText;
        // Soft amber card: a legal step that needs attention.
        return AppCard(
          accent: AppAccents.warning,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const ExcludeSemantics(
                    child: IconBadge(
                      icon: AppIcons.guardian,
                      accent: AppAccents.warning,
                      size: AppSizes.badgeSm,
                    ),
                  ),
                  AppGap.hMd,
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        l10n.familyGuardianConsentTitle,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                  ),
                ],
              ),
              AppGap.md,
              Text(
                l10n.familyGuardianConsentLaw(
                  country.privacyLaw,
                  country.consentAge,
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              AppGap.xs,
              CheckboxListTile(
                value: value,
                onChanged: enabled
                    ? (checked) {
                        final next = checked ?? false;
                        field.didChange(next);
                        onChanged(next);
                      }
                    : null,
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                isError: error != null,
                title: Text(
                  l10n.familyGuardianConsentCheckbox,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              if (error != null)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    error,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.error,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
