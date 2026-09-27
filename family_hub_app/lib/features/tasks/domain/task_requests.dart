import 'package:flutter/foundation.dart';

import 'package:family_hub/core/utils/date_x.dart';
import 'package:family_hub/features/tasks/domain/family_task.dart';
import 'package:family_hub/shared/data/repository_utils.dart';

/// Length limits of contract §7 (`POST /tasks`).
abstract final class TaskLimits {
  static const titleMax = 120;
  static const descriptionMax = 1000;

  /// How far ahead the date picker offers due dates.
  static const dueDateMaxYearsAhead = 5;

  static final _visible = RegExp(r'[\p{L}\p{N}\p{S}\p{P}]', unicode: true);

  /// Whether [title] has something a person can see: a letter, digit,
  /// symbol / emoji or punctuation mark. The backend rejects titles made only
  /// of spaces or zero-width / format characters as blank.
  static bool hasVisibleText(String title) => _visible.hasMatch(title);
}

/// Body of `POST /tasks`.
///
/// [dueDate] is a calendar day; it is sent as local midnight converted to
/// UTC (contract "Time" rule). Blank descriptions and a missing due date are
/// omitted.
@immutable
class TaskDraft {
  const TaskDraft({
    required this.title,
    required this.assigneeId,
    this.description,
    this.dueDate,
    this.category = TaskCategory.other,
    this.priority = TaskPriority.medium,
  });

  final String title;
  final String? description;
  final String assigneeId;
  final DateTime? dueDate;
  final TaskCategory category;
  final TaskPriority priority;

  Map<String, dynamic> toJson() => {
    'title': title.trim(),
    'description': ?trimOrNull(description),
    'assigneeId': assigneeId,
    'dueDate': ?dueDate?.toApiDate(),
    'category': category.wireName,
    'priority': priority.wireName,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaskDraft &&
          other.title == title &&
          other.description == description &&
          other.assigneeId == assigneeId &&
          other.dueDate == dueDate &&
          other.category == category &&
          other.priority == priority;

  @override
  int get hashCode =>
      Object.hash(title, description, assigneeId, dueDate, category, priority);

  @override
  String toString() => 'TaskDraft($title → $assigneeId)';
}

/// Fields of a task that a PATCH can clear (send `null`).
enum TaskPatchField { description, dueDate }

/// Body of `PATCH /tasks/:id` — only the fields to change.
///
/// A field in [clear] is sent as `null` (removes the description / due
/// date). Use [TaskPatch.diff] to build it from an edit form.
class TaskPatch extends PatchBody {
  factory TaskPatch({
    String? title,
    String? description,
    String? assigneeId,
    DateTime? dueDate,
    TaskCategory? category,
    TaskPriority? priority,
    Set<TaskPatchField> clear = const {},
  }) {
    final fields = <String, dynamic>{
      'title': ?trimOrNull(title),
      'description': ?trimOrNull(description),
      'assigneeId': ?trimOrNull(assigneeId),
      'dueDate': ?dueDate?.toApiDate(),
      'category': ?category?.wireName,
      'priority': ?priority?.wireName,
    };
    if (clear.contains(TaskPatchField.description) &&
        !fields.containsKey('description')) {
      fields['description'] = null;
    }
    if (clear.contains(TaskPatchField.dueDate) &&
        !fields.containsKey('dueDate')) {
      fields['dueDate'] = null;
    }
    return TaskPatch._(Map.unmodifiable(fields));
  }

  const TaskPatch._(super.fields);

  /// Only the values of the edit form that differ from [before].
  ///
  /// Titles and descriptions are compared trimmed; due dates by calendar
  /// day. A blank description / `null` due date clears the stored one.
  factory TaskPatch.diff(
    FamilyTask before, {
    required String title,
    String? description,
    required String assigneeId,
    DateTime? dueDate,
    required TaskCategory category,
    required TaskPriority priority,
  }) {
    final d = PatchDiff<TaskPatchField>();
    final oldDue = before.dueDay;
    final newDue = dueDate == null
        ? null
        : DateTime(dueDate.year, dueDate.month, dueDate.day);
    return TaskPatch(
      title: d(before.title.trim(), title.trim()),
      description: d(
        trimOrNull(before.description),
        trimOrNull(description),
        TaskPatchField.description,
      ),
      assigneeId: d(before.assigneeId, assigneeId),
      dueDate: d(oldDue, newDue, TaskPatchField.dueDate),
      category: d(before.category, category),
      priority: d(before.priority, priority),
      clear: d.cleared,
    );
  }
}
