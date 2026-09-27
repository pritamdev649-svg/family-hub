import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/features/tasks/domain/task_query.dart';
import 'package:family_hub/shared/providers/shared_providers.dart';

/// Segments of the tasks tab.
enum TasksView {
  /// The signed-in member's pending tasks.
  mine,

  /// Pending tasks of the whole family (optionally of one member).
  family,

  /// Completed tasks of the family (optionally of one member).
  done,
}

/// Due-date chips of the pending views ([TaskDueFilter] plus "all").
enum TaskDueChoice {
  all(null),
  overdue(TaskDueFilter.overdue),
  today(TaskDueFilter.today),
  week(TaskDueFilter.week);

  const TaskDueChoice(this.filter);

  final TaskDueFilter? filter;
}

/// Current filters of the tasks tab.
@immutable
class TasksFilter {
  const TasksFilter({
    this.view = TasksView.mine,
    this.due = TaskDueChoice.all,
    this.memberId,
  });

  final TasksView view;

  /// Ignored in the [TasksView.done] view.
  final TaskDueChoice due;

  /// Member filter of the [TasksView.family] / [TasksView.done] views.
  final String? memberId;

  /// Whether the due-date chips apply to [view].
  bool get showsDueFilter => view != TasksView.done;

  /// Whether the member filter applies to [view].
  bool get showsMemberFilter => view != TasksView.mine;

  /// The API query for this filter; [myMemberId] is the signed-in member.
  /// Without a member (should not happen inside the app) "mine" falls back
  /// to the family list.
  TaskQuery toQuery(String? myMemberId) => switch (view) {
    TasksView.mine => TaskQuery(
      assigneeId: myMemberId,
      status: TaskListStatus.pending,
      due: due.filter,
    ),
    TasksView.family => TaskQuery(
      assigneeId: memberId,
      status: TaskListStatus.pending,
      due: due.filter,
    ),
    TasksView.done => TaskQuery(
      assigneeId: memberId,
      status: TaskListStatus.done,
    ),
  };

  TasksFilter copyWith({
    TasksView? view,
    TaskDueChoice? due,
    ValueGetter<String?>? memberId,
  }) {
    return TasksFilter(
      view: view ?? this.view,
      due: due ?? this.due,
      memberId: memberId == null ? this.memberId : memberId(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TasksFilter &&
      other.view == view &&
      other.due == due &&
      other.memberId == memberId;

  @override
  int get hashCode => Object.hash(view, due, memberId);
}

/// Filters of the tasks tab; reset when the signed-in user changes.
class TasksFilterController extends Notifier<TasksFilter> {
  @override
  TasksFilter build() {
    ref.watch(sessionUserIdProvider);
    return const TasksFilter();
  }

  void setView(TasksView view) => state = state.copyWith(view: view);

  void setDue(TaskDueChoice due) => state = state.copyWith(due: due);

  void setMember(String? memberId) =>
      state = state.copyWith(memberId: () => memberId);
}

final tasksFilterProvider =
    NotifierProvider<TasksFilterController, TasksFilter>(
      TasksFilterController.new,
    );
