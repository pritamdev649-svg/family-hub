import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';

/// Compliance caption on money screens: FamilyHub only records amounts and
/// never moves real money (docs/08-COMPLIANCE.md #18).
class RecordsOnlyNote extends StatelessWidget {
  const RecordsOnlyNote({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(AppIcons.info, size: AppSizes.iconXs, color: color),
          AppGap.hXs,
          Flexible(
            child: Text(
              context.l10n.ledgerRecordsOnlyNote,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
