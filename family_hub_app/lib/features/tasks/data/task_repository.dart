import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/providers/core_providers.dart';
import 'package:family_hub/features/tasks/domain/family_task.dart';
import 'package:family_hub/features/tasks/domain/task_query.dart';
import 'package:family_hub/features/tasks/domain/task_requests.dart';
import 'package:family_hub/shared/data/repository_utils.dart';

/// `/tasks` endpoints (docs/03-API_CONTRACT.md §7). Throws only
/// [ApiException].
class TaskRepository {
  TaskRepository(this._api);

  final ApiClient _api;

  /// Default page size of task lists.
  static const pageSize = 20;

  static const _base = '/tasks';

  /// `GET /tasks?assigneeId=&status=&due=&page=&limit=`. Items without an id
  /// (malformed) are dropped.
  Future<Paged<FamilyTask>> list(
    TaskQuery query, {
    int page = 1,
    int limit = pageSize,
  }) async {
    final paged = await _api.getPaged<FamilyTask>(
      _base,
      FamilyTask.fromJson,
      query: query.toQueryParameters(),
      page: page,
      limit: limit,
    );
    if (paged.items.every((t) => t.id.isNotEmpty)) return paged;
    return paged.copyWith(
      items: [
        for (final t in paged.items)
          if (t.id.isNotEmpty) t,
      ],
    );
  }

  /// `GET /tasks/:id`.
  Future<FamilyTask> get(String id) async =>
      _task(await _api.get('$_base/${pathId(id)}'));

  /// `POST /tasks` → `201 Task`.
  Future<FamilyTask> create(TaskDraft draft) async =>
      _task(await _api.post(_base, body: draft.toJson()));

  /// `PATCH /tasks/:id`. An empty [patch] sends nothing and returns the
  /// current task.
  Future<FamilyTask> update(String id, TaskPatch patch) async {
    if (patch.isEmpty) return get(id);
    return _task(
      await _api.patch('$_base/${pathId(id)}', body: patch.toJson()),
    );
  }

  /// `POST /tasks/:id/complete` (idempotent).
  Future<FamilyTask> complete(String id) async =>
      _task(await _api.post('$_base/${pathId(id)}/complete'));

  /// `POST /tasks/:id/reopen` (idempotent).
  Future<FamilyTask> reopen(String id) async =>
      _task(await _api.post('$_base/${pathId(id)}/reopen'));

  /// `DELETE /tasks/:id`.
  Future<void> delete(String id) async {
    await _api.delete('$_base/${pathId(id)}');
  }

  static FamilyTask _task(Object? data) {
    final task = FamilyTask.fromJson(requireObject(data));
    if (task.id.isEmpty) {
      throw const ApiException.unknown('Malformed response: task without id');
    }
    return task;
  }
}

final taskRepositoryProvider = Provider<TaskRepository>(
  (ref) => TaskRepository(ref.watch(apiClientProvider)),
);
