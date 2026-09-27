import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/router/app_routes.dart';

/// What the member tried to do when the server answered `LAST_ADMIN`.
enum LastAdminAction { leave, delete }

/// Explains the `LAST_ADMIN` rule and offers to open the members list, where
/// another member can be made an admin.
Future<void> showLastAdminDialog(
  BuildContext context, {
  required LastAdminAction action,
}) async {
  final openMembers = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final l10n = dialogContext.l10n;
      return AlertDialog(
        scrollable: true,
        icon: Icon(
          AppIcons.admin,
          color: Theme.of(dialogContext).colorScheme.primary,
        ),
        title: Text(l10n.settingsLastAdminTitle),
        content: Text(switch (action) {
          LastAdminAction.leave => l10n.settingsLastAdminLeaveMessage,
          LastAdminAction.delete => l10n.settingsLastAdminDeleteMessage,
        }),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonClose),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.settingsLastAdminOpenMembers),
          ),
        ],
      );
    },
  );
  if (openMembers == true && context.mounted) {
    await context.push(AppRoutes.members);
  }
}
