import 'package:flutter/foundation.dart';

import 'package:family_hub/core/utils/date_x.dart';
import 'package:family_hub/features/ledger/domain/ledger_entry.dart';
import 'package:family_hub/shared/json.dart';

/// Lifecycle of a savings goal (wire: `active|achieved|archived`).
enum GoalStatus {
  active,
  achieved,
  archived;

  String get wireName => enumWireName(this);

  static GoalStatus fromWire(Object? v, [GoalStatus fallback = active]) =>
      enumByName(values, v, fallback);
}

/// A family savings goal (contract §8 `SavingsGoal`), e.g. "Goa vacation".
@immutable
class SavingsGoal {
  const SavingsGoal({
    required this.id,
    required this.title,
    required this.targetAmount,
    this.savedAmount = 0,
    this.description,
    this.targetDate,
    this.status = GoalStatus.active,
    double? progress,
    this.createdById = '',
    this.createdAt,
    this.updatedAt,
  }) : _progress = progress;

  factory SavingsGoal.fromJson(Map<String, dynamic> json) {
    final target = asDouble(json['targetAmount']);
    final saved = asDouble(json['savedAmount']);
    return SavingsGoal(
      id: asStringOr(json['id'] ?? json['_id'], ''),
      title: asStringOr(json['title'], '').trim(),
      description: asNonEmptyString(json['description'])?.trim(),
      targetAmount: target < 0 ? 0 : target,
      savedAmount: saved < 0 ? 0 : saved,
      targetDate: calendarDate(parseDate(json['targetDate'])),
      status: GoalStatus.fromWire(json['status']),
      progress: asDoubleOrNull(json['progress']),
      createdById: asStringOr(json['createdById'], ''),
      createdAt: parseDate(json['createdAt']),
      updatedAt: parseDate(json['updatedAt']),
    );
  }

  final String id;
  final String title;
  final String? description;

  /// Major units (`60000` = ₹60,000).
  final double targetAmount;
  final double savedAmount;

  /// Local calendar day (midnight) or null.
  final DateTime? targetDate;
  final GoalStatus status;
  final String createdById;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Server value (may be missing or out of range on odd data).
  final double? _progress;

  /// Fraction saved, always clamped to 0–1. Uses the server's value when
  /// present, else `saved / target`.
  double get progress {
    final p = _progress;
    if (p != null && p.isFinite) return p.clamp(0.0, 1.0);
    if (targetAmount <= 0) return savedAmount > 0 ? 1 : 0;
    return (savedAmount / targetAmount).clamp(0.0, 1.0);
  }

  /// Amount still needed (never negative), rounded to 2 decimals.
  double get remaining {
    final r = targetAmount - savedAmount;
    return r <= 0 ? 0 : (r * 100).roundToDouble() / 100;
  }

  bool get isActive => status == GoalStatus.active;
  bool get isAchieved => status == GoalStatus.achieved;
  bool get isArchived => status == GoalStatus.archived;

  /// The backend rejects contributions to archived goals.
  bool get acceptsContributions => !isArchived;

  /// Whole days from today until [targetDate] (0 = due today, negative =
  /// overdue by that many days); null without a target date.
  int? daysLeft({DateTime? now}) {
    final target = targetDate;
    if (target == null) return null;
    final today = (now ?? DateTime.now()).toLocal().startOfDay;
    final day = DateTime(target.year, target.month, target.day);
    // Round: DST changes make some days 23 or 25 hours long.
    return (day.difference(today).inHours / 24).round();
  }

  /// Whether the target date has passed while the goal is still active.
  bool isOverdue({DateTime? now}) {
    final left = daysLeft(now: now);
    return isActive && left != null && left < 0;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'targetAmount': targetAmount,
    'savedAmount': savedAmount,
    'targetDate': isoOrNull(targetDate),
    'status': status.wireName,
    'progress': progress,
    'createdById': createdById,
    'createdAt': isoOrNull(createdAt),
    'updatedAt': isoOrNull(updatedAt),
  };

  SavingsGoal copyWith({
    String? id,
    String? title,
    ValueGetter<String?>? description,
    double? targetAmount,
    double? savedAmount,
    ValueGetter<DateTime?>? targetDate,
    GoalStatus? status,
    String? createdById,
    ValueGetter<DateTime?>? createdAt,
    ValueGetter<DateTime?>? updatedAt,
  }) {
    final newTarget = targetAmount ?? this.targetAmount;
    final newSaved = savedAmount ?? this.savedAmount;
    // Keep the server progress only while the amounts it describes are kept.
    final keepProgress =
        newTarget == this.targetAmount && newSaved == this.savedAmount;
    return SavingsGoal(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description == null ? this.description : description(),
      targetAmount: newTarget,
      savedAmount: newSaved,
      targetDate: targetDate == null ? this.targetDate : targetDate(),
      status: status ?? this.status,
      progress: keepProgress ? _progress : null,
      createdById: createdById ?? this.createdById,
      createdAt: createdAt == null ? this.createdAt : createdAt(),
      updatedAt: updatedAt == null ? this.updatedAt : updatedAt(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SavingsGoal &&
          other.id == id &&
          other.title == title &&
          other.description == description &&
          other.targetAmount == targetAmount &&
          other.savedAmount == savedAmount &&
          other.targetDate == targetDate &&
          other.status == status &&
          other.progress == progress &&
          other.createdById == createdById &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    description,
    targetAmount,
    savedAmount,
    targetDate,
    status,
    progress,
    createdById,
    createdAt,
    updatedAt,
  );

  @override
  String toString() =>
      'SavingsGoal($id, $title, $savedAmount/$targetAmount, ${status.wireName})';
}

/// Result of `POST /goals/:id/contributions`: the updated goal and the
/// `expense/savings` ledger entry that records the contribution.
@immutable
class GoalContributionResult {
  const GoalContributionResult({required this.goal, required this.entry});

  final SavingsGoal goal;
  final LedgerEntry entry;
}
