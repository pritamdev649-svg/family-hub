import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';

/// Asks the user to confirm an action. Resolves to `true` only when the
/// confirm button is pressed (dismissing / cancelling → `false`).
///
/// [destructive] paints the confirm button in the error colour and shows a
/// warning icon — use it for delete / remove / leave actions.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  String? confirmLabel,
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final l10n = dialogContext.l10n;
      final scheme = Theme.of(dialogContext).colorScheme;
      return AlertDialog(
        scrollable: true,
        icon: destructive ? Icon(AppIcons.warning, color: scheme.error) : null,
        title: Text(title),
        content: message == null ? null : Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                  )
                : null,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(confirmLabel ?? l10n.commonConfirm),
          ),
        ],
      );
    },
  );
  return result ?? false;
}
