import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/tasks/presentation/widgets/task_state_card.dart';

/// State for a task that no longer exists for the caller: deleted (here or
/// by someone else), removed together with its assignee, another family's
/// task or a malformed link (e.g. an old push notification). Offers a way
/// back instead of a pointless "retry": the button goes to the Tasks tab
/// (closing every task screen above it, e.g. detail + edit).
class TaskGoneView extends StatelessWidget {
  const TaskGoneView({super.key, this.deletedHere = false});

  /// The signed-in member deleted it on this device (shorter wording).
  final bool deletedHere;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TaskStateCard(
      icon: deletedHere ? AppIcons.delete : AppIcons.task,
      accent: deletedHere ? AppAccent.rose : AppAccents.tasks,
      title: deletedHere ? l10n.tasksDeleted : l10n.tasksGoneTitle,
      message: deletedHere ? null : l10n.tasksGoneMessage,
      action: AppButton(
        label: l10n.tasksBackToTasks,
        icon: AppIcons.tasks,
        variant: AppButtonVariant.tonal,
        expand: false,
        onPressed: () => context.go(AppRoutes.tasks),
      ),
    );
  }
}
