import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/network/api_client.dart';
import 'package:family_hub/features/tasks/application/task_clock.dart';
import 'package:family_hub/features/tasks/data/task_repository.dart';
import 'package:family_hub/features/tasks/domain/family_task.dart';
import 'package:family_hub/features/tasks/domain/task_permissions.dart';
import 'package:family_hub/features/tasks/domain/task_query.dart';
import 'package:family_hub/shared/providers/shared_providers.dart';

export 'package:family_hub/features/tasks/application/task_clock.dart';
export 'package:family_hub/features/tasks/application/task_controller.dart';

/// Loaded pages of one task list plus the "load more" flag.
@immutable
class TaskListState {
  const TaskListState({required this.page, this.isLoadingMore = false});

  const TaskListState.empty()
    : page = const Paged<FamilyTask>.empty(limit: TaskRepository.pageSize),
      isLoadingMore = false;

  final Paged<FamilyTask> page;
  final bool isLoadingMore;

  List<FamilyTask> get items => page.items;
  bool get hasMore => page.hasMore;

  /// Total matching tasks on the server.
  int get total => page.total;

  TaskListState copyWith({Paged<FamilyTask>? page, bool? isLoadingMore}) {
    return TaskListState(
      page: page ?? this.page,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TaskListState &&
      other.page == page &&
      other.isLoadingMore == isLoadingMore;

  @override
  int get hashCode => Object.hash(page, isLoadingMore);
}

/// One paginated task list for a [TaskQuery]. Refetches (keeping the old
/// items on screen) on account switch and on
/// `markChanged({DataScope.tasks})`.
class TaskListController extends AsyncNotifier<TaskListState> {
  TaskListController(this.query);

  final TaskQuery query;

  @override
  Future<TaskListState> build() async {
    final userId = ref.watch(sessionUserIdProvider);
    ref.watch(dataRefreshProvider.select((m) => m[DataScope.tasks]));
    // "Overdue / today / this week" change at midnight.
    if (query.due != null) ref.watch(taskTodayProvider);
    if (userId == null) return const TaskListState.empty();
    final page = await ref.watch(taskRepositoryProvider).list(query);
    return TaskListState(page: page);
  }

  /// Loads the next page. No-op while loading, refreshing or at the end.
  /// Errors are rethrown (the list keeps its items; "Load more" retries).
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null ||
        state.isLoading ||
        current.isLoadingMore ||
        !current.hasMore) {
      return;
    }
    final repo = ref.read(taskRepositoryProvider);
    state = AsyncData(current.copyWith(isLoadingMore: true));
    try {
      final next = await repo.list(
        query,
        page: current.page.nextPage,
        limit: current.page.limit,
      );
      // A refresh rebuilt the list meanwhile: drop this stale page.
      if (!ref.mounted) return;
      state = AsyncData(
        TaskListState(page: current.page.append(next, identity: (t) => t.id)),
      );
    } catch (_) {
      if (ref.mounted) {
        state = AsyncData(current.copyWith(isLoadingMore: false));
      }
      rethrow;
    }
  }
}

/// Paginated task lists, one per filter combination.
final taskListProvider = AsyncNotifierProvider.autoDispose
    .family<TaskListController, TaskListState, TaskQuery>(
      TaskListController.new,
      retry: apiRetryPolicy,
    );

/// A single task (`GET /tasks/:id`). Show it through
/// `ref.watch(taskControllerProvider).resolve(task)` to include local
/// (optimistic) changes.
final taskByIdProvider = FutureProvider.autoDispose.family<FamilyTask, String>((
  ref,
  id,
) async {
  final userId = ref.watch(sessionUserIdProvider);
  ref.watch(dataRefreshProvider.select((m) => m[DataScope.tasks]));
  if (userId == null || id.trim().isEmpty) {
    throw const ApiException(code: ApiErrorCode.notFound, statusCode: 404);
  }
  return ref.watch(taskRepositoryProvider).get(id);
}, retry: apiRetryPolicy);

/// What the signed-in member may do with tasks (UI mirror of the backend
/// rules).
final taskPermissionsProvider = Provider<TaskPermissions>(
  (ref) => TaskPermissions(
    memberId: ref.watch(currentMemberProvider.select((m) => m?.id)),
    isAdmin: ref.watch(isAdminProvider),
  ),
);
