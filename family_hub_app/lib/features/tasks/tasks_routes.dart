import 'package:go_router/go_router.dart';

import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/features/tasks/presentation/screens/task_detail_screen.dart';
import 'package:family_hub/features/tasks/presentation/screens/task_form_screen.dart';

/// Full-screen routes of the tasks feature (registered top-level by
/// `goRouterProvider`, so they cover the navigation bar). The Tasks tab
/// itself (`/tasks` → `TasksScreen`) is a shell branch.
///
/// * `/tasks/new?assigneeId=` → [TaskFormScreen] (create)
/// * `/tasks/:id/edit` → [TaskFormScreen] (edit)
/// * `/tasks/:id` → [TaskDetailScreen] (also the push-notification route)
List<RouteBase> get taskRoutes => [
  // Static segment before the `:id` routes.
  GoRoute(
    path: AppRoutes.taskNewPath,
    builder: (context, state) => TaskFormScreen(
      initialAssigneeId: state.uri.queryParameters[AppRoutes.assigneeIdQuery],
    ),
  ),
  GoRoute(
    path: AppRoutes.taskEditPath,
    builder: (context, state) =>
        TaskFormScreen(taskId: state.pathParameters[AppRoutes.idParam] ?? ''),
  ),
  GoRoute(
    path: AppRoutes.taskDetailPath,
    builder: (context, state) =>
        TaskDetailScreen(taskId: state.pathParameters[AppRoutes.idParam] ?? ''),
  ),
];
