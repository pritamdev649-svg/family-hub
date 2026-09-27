import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';

/// Helper line under a form field (the shared text / dropdown fields have no
/// helper text of their own). Aligned with the field's text, RTL-safe.
class FieldHelpText extends StatelessWidget {
  const FieldHelpText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: AppSpacing.lg,
        end: AppSpacing.lg,
        top: AppSpacing.xs,
      ),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
