import 'package:flutter/foundation.dart';

import 'package:family_hub/shared/json.dart';

/// `Task.status` (docs/03-API_CONTRACT.md §7). Unknown values → [pending].
enum TaskStatus {
  pending,
  done;

  /// Contract wire value (`pending` / `done`).
  String get wireName => enumWireName(this);

  static TaskStatus fromWire(Object? v) => enumByName(values, v, pending);
}

/// `Task.category`. Unknown values → [other].
enum TaskCategory {
  study,
  chore,
  skill,
  health,
  errand,
  other;

  String get wireName => enumWireName(this);

  static TaskCategory fromWire(Object? v) => enumByName(values, v, other);
}

/// `Task.priority`. Unknown values → [medium].
enum TaskPriority {
  low,
  medium,
  high;

  String get wireName => enumWireName(this);

  static TaskPriority fromWire(Object? v) => enumByName(values, v, medium);
}

/// A task / chore on the family board (contract §7 `Task`).
///
/// Every `*Id` field is a **member** id. [dueDate] is a date-only value: the
/// app sends local midnight converted to UTC, so use [dueDay] (the calendar
/// day, viewer-independent) for display and comparisons.
@immutable
class FamilyTask {
  const FamilyTask({
    required this.id,
    required this.title,
    required this.assigneeId,
    this.description,
    this.assigneeName = '',
    this.createdById = '',
    this.createdByName = '',
    this.dueDate,
    this.category = TaskCategory.other,
    this.priority = TaskPriority.medium,
    this.status = TaskStatus.pending,
    this.completedAt,
    this.completedById,
    this.createdAt,
    this.updatedAt,
  });

  /// Parses a contract `Task` defensively: never throws on missing, `null`,
  /// wrongly typed or extra fields.
  factory FamilyTask.fromJson(Map<String, dynamic> json) {
    return FamilyTask(
      id: asStringOr(json['id'] ?? json['_id'], ''),
      title: asStringOr(json['title'], '').trim(),
      description: asNonEmptyString(json['description'])?.trim(),
      assigneeId: asStringOr(json['assigneeId'], ''),
      assigneeName: asStringOr(json['assigneeName'], '').trim(),
      createdById: asStringOr(json['createdById'], ''),
      createdByName: asStringOr(json['createdByName'], '').trim(),
      dueDate: parseDate(json['dueDate']),
      category: TaskCategory.fromWire(json['category']),
      priority: TaskPriority.fromWire(json['priority']),
      status: TaskStatus.fromWire(json['status']),
      completedAt: parseDate(json['completedAt']),
      completedById: asNonEmptyString(json['completedById']),
      createdAt: parseDate(json['createdAt']),
      updatedAt: parseDate(json['updatedAt']),
    );
  }

  final String id;
  final String title;
  final String? description;
  final String assigneeId;
  final String assigneeName;
  final String createdById;
  final String createdByName;

  /// Raw instant from the API (UTC). See [dueDay].
  final DateTime? dueDate;
  final TaskCategory category;
  final TaskPriority priority;
  final TaskStatus status;
  final DateTime? completedAt;
  final String? completedById;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isDone => status == TaskStatus.done;
  bool get isPending => status == TaskStatus.pending;
  bool get hasDueDate => dueDate != null;

  /// Calendar day of [dueDate] as a local `DateTime(y, m, d)` (see
  /// [calendarDate]), or `null` without a due date.
  DateTime? get dueDay => calendarDate(dueDate);

  /// Pending and due before the start of [now]'s day.
  bool isOverdueOn(DateTime now) {
    final day = dueDay;
    if (!isPending || day == null) return false;
    return day.isBefore(_dateOnly(now));
  }

  /// Due on the calendar day of [date] (any status).
  bool isDueOn(DateTime date) {
    final day = dueDay;
    if (day == null) return false;
    final d = _dateOnly(date);
    return day.year == d.year && day.month == d.month && day.day == d.day;
  }

  /// Pending and due before today (device local time).
  bool get isOverdue => isOverdueOn(DateTime.now());

  /// Due today (device local time), whatever the status.
  bool get isDueToday => isDueOn(DateTime.now());

  static DateTime _dateOnly(DateTime d) {
    final local = d.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'assigneeId': assigneeId,
    'assigneeName': assigneeName,
    'createdById': createdById,
    'createdByName': createdByName,
    'dueDate': isoOrNull(dueDate),
    'category': category.wireName,
    'priority': priority.wireName,
    'status': status.wireName,
    'completedAt': isoOrNull(completedAt),
    'completedById': completedById,
    'createdAt': isoOrNull(createdAt),
    'updatedAt': isoOrNull(updatedAt),
  };

  /// Nullable fields take a [ValueGetter] so they can be cleared:
  /// `copyWith(dueDate: () => null)`.
  FamilyTask copyWith({
    String? id,
    String? title,
    ValueGetter<String?>? description,
    String? assigneeId,
    String? assigneeName,
    String? createdById,
    String? createdByName,
    ValueGetter<DateTime?>? dueDate,
    TaskCategory? category,
    TaskPriority? priority,
    TaskStatus? status,
    ValueGetter<DateTime?>? completedAt,
    ValueGetter<String?>? completedById,
    ValueGetter<DateTime?>? createdAt,
    ValueGetter<DateTime?>? updatedAt,
  }) {
    return FamilyTask(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description == null ? this.description : description(),
      assigneeId: assigneeId ?? this.assigneeId,
      assigneeName: assigneeName ?? this.assigneeName,
      createdById: createdById ?? this.createdById,
      createdByName: createdByName ?? this.createdByName,
      dueDate: dueDate == null ? this.dueDate : dueDate(),
      category: category ?? this.category,
      priority: priority ?? this.priority,
      status: status ?? this.status,
      completedAt: completedAt == null ? this.completedAt : completedAt(),
      completedById: completedById == null
          ? this.completedById
          : completedById(),
      createdAt: createdAt == null ? this.createdAt : createdAt(),
      updatedAt: updatedAt == null ? this.updatedAt : updatedAt(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FamilyTask &&
          other.id == id &&
          other.title == title &&
          other.description == description &&
          other.assigneeId == assigneeId &&
          other.assigneeName == assigneeName &&
          other.createdById == createdById &&
          other.createdByName == createdByName &&
          other.dueDate == dueDate &&
          other.category == category &&
          other.priority == priority &&
          other.status == status &&
          other.completedAt == completedAt &&
          other.completedById == completedById &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    description,
    assigneeId,
    assigneeName,
    createdById,
    createdByName,
    dueDate,
    category,
    priority,
    status,
    completedAt,
    completedById,
    createdAt,
    updatedAt,
  );

  @override
  String toString() => 'FamilyTask($id, $title, ${status.wireName})';
}
