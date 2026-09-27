import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/features/tasks/data/task_repository.dart';
import 'package:family_hub/features/tasks/domain/family_task.dart';
import 'package:family_hub/features/tasks/domain/task_failure.dart';
import 'package:family_hub/features/tasks/domain/task_requests.dart';
import 'package:family_hub/shared/providers/shared_providers.dart';

/// Re-reads the signed-in session (`GET /auth/me`) after the server refused a
/// task action with `403 FORBIDDEN` / `NO_FAMILY`: the member's role or
/// membership changed while the screen was open, and the refreshed session
/// updates every permission-dependent control (or sends a removed member to
/// the family-setup screen). Overridable in tests.
final taskSessionRefreshProvider = Provider<Future<void> Function()>(
  (ref) =>
      () => ref.read(sessionControllerProvider.notifier).refreshMe(),
);

/// Local knowledge about task mutations of this session, applied on top of
/// whatever server data a screen shows (lists, detail, the dashboard's
/// `TaskTile`s):
///
/// * [latest] — the newest local version of a task: the optimistic version
///   while a complete / reopen is in flight, then the server's answer.
///   A server copy with a newer `updatedAt` wins (see [resolve]).
/// * [deleted] — tasks deleted here (hidden until lists refetch).
/// * [busy] — tasks with a mutation in flight (their controls are disabled,
///   which prevents double submits).
@immutable
class TaskMutations {
  const TaskMutations({
    this.latest = const {},
    this.deleted = const {},
    this.busy = const {},
  });

  final Map<String, FamilyTask> latest;
  final Set<String> deleted;
  final Set<String> busy;

  bool isBusy(String id) => busy.contains(id);
  bool isDeleted(String id) => deleted.contains(id);

  /// The version of [base] to display.
  FamilyTask resolve(FamilyTask base) => pick(base, latest[base.id]);

  /// [local] unless [base] was changed on the server after it (newer
  /// `updatedAt`), else [base].
  static FamilyTask pick(FamilyTask base, FamilyTask? local) {
    if (local == null) return base;
    final serverAt = base.updatedAt;
    final localAt = local.updatedAt;
    if (serverAt != null && localAt != null && serverAt.isAfter(localAt)) {
      return base;
    }
    return local;
  }

  /// [tasks] without deleted ones, each [resolve]d.
  List<FamilyTask> apply(Iterable<FamilyTask> tasks) => [
    for (final t in tasks)
      if (!deleted.contains(t.id)) resolve(t),
  ];

  TaskMutations copyWith({
    Map<String, FamilyTask>? latest,
    Set<String>? deleted,
    Set<String>? busy,
  }) {
    return TaskMutations(
      latest: latest ?? this.latest,
      deleted: deleted ?? this.deleted,
      busy: busy ?? this.busy,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaskMutations &&
          mapEquals(other.latest, latest) &&
          setEquals(other.deleted, deleted) &&
          setEquals(other.busy, busy);

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(latest.values),
    Object.hashAllUnordered(deleted),
    Object.hashAllUnordered(busy),
  );
}

/// Create / update / complete / reopen / delete tasks.
///
/// Every successful mutation calls `markChanged({DataScope.tasks})`, so all
/// task lists, task details and the dashboard refetch. Complete / reopen are
/// **optimistic**: the new status shows immediately and is rolled back when
/// the request fails (the error is rethrown for the UI to show).
///
/// Failures that reveal stale data are repaired here (see [TaskFailure]):
///
/// * gone (`404`) — someone else deleted the task: it is hidden everywhere
///   and every list refetches. Deleting a task that is already gone counts
///   as success.
/// * not allowed / no family (`403`) — the caller's role or membership
///   changed: the session and the task lists are re-read so the UI shows the
///   right controls (or the family-setup screen).
/// * assignee unavailable (`422 details.assigneeId`) — the member list is
///   stale: members and tasks refetch.
///
/// The state resets when the signed-in user changes.
class TaskController extends Notifier<TaskMutations> {
  @override
  TaskMutations build() {
    ref.watch(sessionUserIdProvider);
    return const TaskMutations();
  }

  TaskRepository get _repo => ref.read(taskRepositoryProvider);

  /// `POST /tasks`.
  Future<FamilyTask> create(TaskDraft draft) async {
    final repo = _repo;
    final FamilyTask task;
    try {
      task = await repo.create(draft);
    } catch (e) {
      _recover(null, e);
      rethrow;
    }
    if (ref.mounted) {
      state = state.copyWith(latest: {...state.latest, task.id: task});
      markChanged(ref, {DataScope.tasks});
    }
    return task;
  }

  /// `PATCH /tasks/:id`. An empty [patch] is not sent.
  Future<FamilyTask> update(String id, TaskPatch patch) async {
    return _guard(id, () async {
      final FamilyTask task;
      try {
        task = await _repo.update(id, patch);
      } catch (e) {
        _recover(id, e);
        rethrow;
      }
      if (ref.mounted) {
        state = state.copyWith(latest: {...state.latest, task.id: task});
        if (!patch.isEmpty) markChanged(ref, {DataScope.tasks});
      }
      return task;
    });
  }

  /// Completes ([done] `true`) or reopens [task], optimistically.
  ///
  /// While a mutation of the same task is in flight the call is ignored and
  /// returns the current local version.
  Future<FamilyTask> setDone(FamilyTask task, {required bool done}) async {
    final id = task.id;
    if (state.isBusy(id)) return state.resolve(task);

    final current = state.resolve(task);
    final previous = state.latest[id];
    final myId = ref.read(currentMemberProvider)?.id;
    final optimistic = done
        ? current.copyWith(
            status: TaskStatus.done,
            completedAt: () => current.completedAt ?? DateTime.now().toUtc(),
            completedById: () => current.completedById ?? myId,
          )
        : current.copyWith(
            status: TaskStatus.pending,
            completedAt: () => null,
            completedById: () => null,
          );

    final repo = _repo;
    state = state.copyWith(
      latest: {...state.latest, id: optimistic},
      busy: {...state.busy, id},
    );
    try {
      final saved = done ? await repo.complete(id) : await repo.reopen(id);
      if (ref.mounted) {
        state = state.copyWith(
          latest: {...state.latest, id: saved},
          busy: {...state.busy}..remove(id),
        );
        markChanged(ref, {DataScope.tasks});
      }
      return saved;
    } catch (e) {
      if (ref.mounted) {
        final latest = {...state.latest};
        if (previous == null) {
          latest.remove(id);
        } else {
          latest[id] = previous;
        }
        state = state.copyWith(
          latest: latest,
          busy: {...state.busy}..remove(id),
        );
      }
      _recover(id, e);
      rethrow;
    }
  }

  /// Completes [task] (see [setDone]).
  Future<FamilyTask> complete(FamilyTask task) => setDone(task, done: true);

  /// Reopens [task] (see [setDone]).
  Future<FamilyTask> reopen(FamilyTask task) => setDone(task, done: false);

  /// `DELETE /tasks/:id`; the task disappears from every list immediately
  /// after the server confirmed. A task that is already gone (`404`, e.g.
  /// deleted by another admin meanwhile) counts as deleted.
  Future<void> delete(String id) async {
    await _guard(id, () async {
      try {
        await _repo.delete(id);
      } catch (e) {
        if (TaskFailure.of(e) != TaskFailure.gone) {
          _recover(id, e);
          rethrow;
        }
      }
      _markGone(id);
    });
  }

  /// Hides [id] everywhere and refetches every task list.
  void _markGone(String id) {
    if (!ref.mounted) return;
    state = state.copyWith(
      deleted: {...state.deleted, id},
      latest: {...state.latest}..remove(id),
    );
    markChanged(ref, {DataScope.tasks});
  }

  /// Repairs local knowledge after a failed request on task [id] (`null` for
  /// a create). Never throws.
  void _recover(String? id, Object error) {
    if (!ref.mounted) return;
    switch (TaskFailure.of(error)) {
      case TaskFailure.gone:
        if (id != null) _markGone(id);
      case TaskFailure.notAllowed || TaskFailure.noFamily:
        markChanged(ref, {DataScope.tasks});
        _refreshSession();
      case TaskFailure.assigneeUnavailable:
        markChanged(ref, {DataScope.members, DataScope.tasks});
      case TaskFailure.other:
        break;
    }
  }

  /// Best-effort, fire-and-forget session refresh (see
  /// [taskSessionRefreshProvider]); failures (offline…) are ignored.
  void _refreshSession() {
    try {
      unawaited(
        ref.read(taskSessionRefreshProvider)().catchError((Object e) {
          if (kDebugMode) debugPrint('[tasks] session refresh failed: $e');
        }),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[tasks] session refresh failed: $e');
    }
  }

  /// Marks [id] busy while [action] runs. Concurrent mutations of the same
  /// task are rejected with a [StateError] (the UI disables its controls).
  Future<T> _guard<T>(String id, Future<T> Function() action) async {
    if (state.isBusy(id)) {
      throw StateError('A change to task $id is already in progress');
    }
    state = state.copyWith(busy: {...state.busy, id});
    try {
      return await action();
    } finally {
      if (ref.mounted) {
        state = state.copyWith(busy: {...state.busy}..remove(id));
      }
    }
  }
}

final taskControllerProvider = NotifierProvider<TaskController, TaskMutations>(
  TaskController.new,
);
