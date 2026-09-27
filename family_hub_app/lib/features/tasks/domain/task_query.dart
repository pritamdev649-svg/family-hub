import 'package:flutter/foundation.dart';

import 'package:family_hub/features/tasks/domain/family_task.dart';

/// `?status=` of `GET /tasks`.
enum TaskListStatus {
  pending,
  done,
  all;

  /// Whether a task with [status] belongs to a list with this filter.
  bool includes(TaskStatus status) => switch (this) {
    TaskListStatus.pending => status == TaskStatus.pending,
    TaskListStatus.done => status == TaskStatus.done,
    TaskListStatus.all => true,
  };
}

/// `?due=` of `GET /tasks` (evaluated by the server in the family time
/// zone; "week" is the Monday-based week containing today).
enum TaskDueFilter { overdue, today, week }

/// Filters of one task list (`GET /tasks?assigneeId=&status=&due=`).
///
/// Used as the argument of the `taskListProvider` family, so it has value
/// equality.
@immutable
class TaskQuery {
  const TaskQuery({
    this.assigneeId,
    this.status = TaskListStatus.pending,
    this.due,
  });

  /// Only tasks of this member (`null` = whole family).
  final String? assigneeId;
  final TaskListStatus status;

  /// `null` = any due date (including none).
  final TaskDueFilter? due;

  /// Query parameters for the API (`null` values are dropped by `ApiClient`).
  Map<String, dynamic> toQueryParameters() => {
    'assigneeId': assigneeId,
    'status': status.name,
    'due': due?.name,
  };

  TaskQuery copyWith({
    ValueGetter<String?>? assigneeId,
    TaskListStatus? status,
    ValueGetter<TaskDueFilter?>? due,
  }) {
    return TaskQuery(
      assigneeId: assigneeId == null ? this.assigneeId : assigneeId(),
      status: status ?? this.status,
      due: due == null ? this.due : due(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaskQuery &&
          other.assigneeId == assigneeId &&
          other.status == status &&
          other.due == due;

  @override
  int get hashCode => Object.hash(assigneeId, status, due);

  @override
  String toString() =>
      'TaskQuery(assigneeId: $assigneeId, status: ${status.name}, due: ${due?.name})';
}
