import 'package:flutter/foundation.dart';

import 'package:family_hub/features/tasks/domain/family_task.dart';

/// Sections of a pending task list, in display order.
enum TaskSection { overdue, today, upcoming, noDueDate }

/// One non-empty section of a grouped task list.
@immutable
class TaskGroup {
  const TaskGroup(this.section, this.tasks);

  final TaskSection section;
  final List<FamilyTask> tasks;

  @override
  bool operator ==(Object other) =>
      other is TaskGroup &&
      other.section == section &&
      listEquals(other.tasks, tasks);

  @override
  int get hashCode => Object.hash(section, Object.hashAll(tasks));
}

/// Section of [task] by its due day relative to [now] (status is ignored on
/// purpose: a task ticked off optimistically stays where it was until the
/// list refreshes, instead of jumping around).
TaskSection sectionOf(FamilyTask task, DateTime now) {
  final day = task.dueDay;
  if (day == null) return TaskSection.noDueDate;
  final local = now.toLocal();
  final today = DateTime(local.year, local.month, local.day);
  if (day.isBefore(today)) return TaskSection.overdue;
  if (day == today) return TaskSection.today;
  return TaskSection.upcoming;
}

/// Groups [tasks] into the non-empty [TaskSection]s (in enum order), keeping
/// the server order inside each section.
List<TaskGroup> groupTasks(Iterable<FamilyTask> tasks, {DateTime? now}) {
  final at = now ?? DateTime.now();
  final buckets = <TaskSection, List<FamilyTask>>{};
  for (final t in tasks) {
    (buckets[sectionOf(t, at)] ??= <FamilyTask>[]).add(t);
  }
  return [
    for (final s in TaskSection.values)
      if (buckets[s] case final list?) TaskGroup(s, List.unmodifiable(list)),
  ];
}
