import 'package:flutter/widgets.dart';

import 'package:family_hub/core/l10n/error_messages.dart'
    show unwrapProviderError;
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/network/api_exception.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/tasks/domain/task_failure.dart';

/// The task request that failed; picks the most helpful message.
enum TaskAction {
  /// `POST /tasks`.
  create,

  /// `PATCH /tasks/:id` without moving the task to someone else.
  update,

  /// `PATCH /tasks/:id` that moves the task to another member.
  reassign,

  /// `POST /tasks/:id/complete`.
  complete,

  /// `POST /tasks/:id/reopen`.
  reopen,

  /// `DELETE /tasks/:id`.
  delete,
}

/// Task-specific, localised text for failures whose generic message would
/// be misleading here (e.g. "check the highlighted fields" on the detail
/// screen), or `null` to use the app-wide `localizedErrorMessage`.
String? taskErrorMessage(
  Object error,
  TaskAction action,
  AppLocalizations l10n,
) {
  return switch (TaskFailure.of(error)) {
    TaskFailure.gone when action != TaskAction.create => l10n.tasksErrorGone,
    TaskFailure.notAllowed => switch (action) {
      TaskAction.create || TaskAction.reassign => l10n.tasksErrorAssignSelfOnly,
      TaskAction.update || TaskAction.delete => l10n.tasksErrorEditNotAllowed,
      TaskAction.complete ||
      TaskAction.reopen => l10n.tasksErrorCompleteNotAllowed,
    },
    TaskFailure.assigneeUnavailable => switch (action) {
      TaskAction.complete ||
      TaskAction.reopen => l10n.tasksErrorAssigneeRemoved,
      _ => l10n.tasksErrorAssigneeNotInFamily,
    },
    _ => null,
  };
}

extension TaskErrorSnackX on BuildContext {
  /// Error snackbar for a failed task [action]: the task-specific message
  /// when there is one, else the app-wide one (`showError`).
  void showTaskError(Object error, TaskAction action) {
    final message = taskErrorMessage(error, action, l10n);
    // `localizedErrorMessage` shows the message of an ApiException whose
    // code it does not know, so the snackbar keeps the standard error style.
    showError(
      message == null
          ? error
          : ApiException(
              code: _localizedTaskError,
              message: message,
              statusCode: _statusOf(error),
            ),
    );
  }
}

/// Client-side code of an already localised task error message.
const _localizedTaskError = 'TASKS_LOCALIZED_ERROR';

int _statusOf(Object error) {
  final e = unwrapProviderError(error);
  return e is ApiException ? e.statusCode ?? 0 : 0;
}
