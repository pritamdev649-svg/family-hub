import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/network/api_exception.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/notices/application/notices_providers.dart';
import 'package:family_hub/features/notices/domain/notice.dart';
import 'package:family_hub/features/notices/presentation/widgets/notice_route_guard.dart';

/// Actions offered for one notice, depending on the member's permissions.
enum NoticeAction { edit, pin, unpin, copy, delete }

/// The actions [permissions] allow for [notice], in menu order.
List<NoticeAction> noticeActionsFor(
  Notice notice,
  NoticePermissions permissions,
) => [
  if (permissions.canEdit(notice)) NoticeAction.edit,
  if (permissions.canPin) notice.pinned ? NoticeAction.unpin : NoticeAction.pin,
  NoticeAction.copy,
  if (permissions.canDelete(notice)) NoticeAction.delete,
];

/// Shows the action sheet of [notice] (menu button and long-press) and runs
/// the chosen action with busy state, confirmation and localized feedback.
Future<void> showNoticeActions(
  BuildContext context,
  WidgetRef ref,
  Notice notice,
) async {
  if (!isNoticeRouteCurrent(context)) return;
  final permissions = ref.read(noticePermissionsProvider);
  final actions = noticeActionsFor(notice, permissions);
  final action = await showModalBottomSheet<NoticeAction>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => _NoticeActionSheet(
      notice: notice,
      actions: actions,
      onSelected: (a) => Navigator.of(sheetContext).pop(a),
    ),
  );
  if (action == null || !context.mounted) return;
  await runNoticeAction(context, ref, notice, action);
}

/// Runs one [action] for [notice].
Future<void> runNoticeAction(
  BuildContext context,
  WidgetRef ref,
  Notice notice,
  NoticeAction action,
) async {
  final l10n = context.l10n;
  // The card that started the action may be rebuilt elsewhere (re-sorted
  // after a pin) or disappear (deleted) while the request runs; feedback
  // then goes through the root navigator's context, which stays mounted.
  final feedback =
      Navigator.maybeOf(context, rootNavigator: true)?.context ?? context;
  final controller = ref.read(noticesControllerProvider.notifier);

  switch (action) {
    case NoticeAction.edit:
      await context.push(AppRoutes.noticeEdit(notice.id), extra: notice);

    case NoticeAction.copy:
      final text = [
        notice.title,
        notice.body,
      ].where((s) => s.trim().isNotEmpty).join('\n\n');
      try {
        await Clipboard.setData(ClipboardData(text: text));
        if (feedback.mounted) feedback.showSuccess(l10n.commonCopied);
      } catch (e) {
        // No clipboard access (some platforms / restricted profiles).
        if (feedback.mounted) feedback.showError(e);
      }

    case NoticeAction.pin:
    case NoticeAction.unpin:
      final pin = action == NoticeAction.pin;
      try {
        final updated = await controller.setPinned(notice, pin);
        if (updated == null || !feedback.mounted) return;
        feedback.showSuccess(
          pin ? l10n.noticesPinnedSuccess : l10n.noticesUnpinnedSuccess,
        );
      } on ApiException catch (e) {
        if (!feedback.mounted) return;
        // Deleted meanwhile: the card is already gone from the board.
        if (e.isNotFound) {
          feedback.showInfo(l10n.noticesGone);
        } else {
          feedback.showError(e);
        }
      } catch (e) {
        if (feedback.mounted) feedback.showError(e);
      }

    case NoticeAction.delete:
      final confirmed = await showConfirmDialog(
        context,
        title: l10n.noticesDeleteTitle,
        message: l10n.noticesDeleteMessage(notice.title),
        confirmLabel: l10n.commonDelete,
        destructive: true,
      );
      if (!confirmed) return;
      try {
        final deleted = await controller.delete(notice);
        if (deleted && feedback.mounted) {
          feedback.showSuccess(l10n.noticesDeleted);
        }
      } catch (e) {
        if (feedback.mounted) feedback.showError(e);
      }
  }
}

class _NoticeActionSheet extends StatelessWidget {
  const _NoticeActionSheet({
    required this.notice,
    required this.actions,
    required this.onSelected,
  });

  final Notice notice;
  final List<NoticeAction> actions;
  final ValueChanged<NoticeAction> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget tile(NoticeAction action) {
      final (IconData icon, String label) = switch (action) {
        NoticeAction.edit => (AppIcons.edit, l10n.commonEdit),
        NoticeAction.pin => (AppIcons.pin, l10n.noticesPin),
        NoticeAction.unpin => (AppIcons.unpin, l10n.noticesUnpin),
        NoticeAction.copy => (AppIcons.copy, l10n.noticesCopyText),
        NoticeAction.delete => (AppIcons.delete, l10n.commonDelete),
      };
      final color = action == NoticeAction.delete ? scheme.error : null;
      return ListTile(
        iconColor: color,
        textColor: color,
        leading: Icon(icon),
        title: Text(label),
        onTap: () => onSelected(action),
      );
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: AppSpacing.lg,
              ),
              child: Semantics(
                header: true,
                child: Text(
                  notice.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ),
            AppGap.sm,
            for (final action in actions) tile(action),
          ],
        ),
      ),
    );
  }
}
