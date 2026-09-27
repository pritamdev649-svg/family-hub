import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/error_messages.dart';
import 'package:family_hub/core/l10n/l10n.dart';

/// Error line for bottom sheets, where a snackbar would be hidden behind the
/// sheet. Announced to screen readers when it appears.
class LedgerInlineError extends StatelessWidget {
  const LedgerInlineError({super.key, required this.error, this.message});

  /// Mapped with `localizedErrorMessage` unless [message] is given.
  final Object error;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = message ?? localizedErrorMessage(error, context.l10n);
    return Semantics(
      liveRegion: true,
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: AppRadius.brMd,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                AppIcons.error,
                size: AppSizes.iconSm,
                color: scheme.onErrorContainer,
              ),
              AppGap.hSm,
              Expanded(
                child: Text(
                  text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
