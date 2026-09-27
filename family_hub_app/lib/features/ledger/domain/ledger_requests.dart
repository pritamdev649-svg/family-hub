import 'package:flutter/foundation.dart';

import 'package:family_hub/core/utils/date_x.dart';
import 'package:family_hub/features/ledger/domain/ledger_entry.dart';
import 'package:family_hub/features/ledger/domain/savings_goal.dart';
import 'package:family_hub/shared/data/repository_utils.dart';

/// Input limits of the ledger / goal endpoints (contract §8). The UI
/// enforces them before a round trip.
abstract final class LedgerLimits {
  /// `note` of entries and contributions.
  static const noteMax = 200;

  /// Goal `title` (1–80).
  static const goalTitleMax = 80;

  /// Goal `description` as offered by the form (the server accepts more).
  static const goalDescriptionMax = 500;
}

/// Rounds a money amount to 2 decimals (the API's precision).
double roundMoney(num v) => (v * 100).roundToDouble() / 100;

/// Filters of `GET /ledger/entries`. Also the family key of the entries
/// list provider, hence value equality.
@immutable
class LedgerEntryQuery {
  const LedgerEntryQuery({this.month, this.type, this.memberId, this.goalId});

  /// `YYYY-MM` (null = every month).
  final String? month;
  final LedgerType? type;
  final String? memberId;
  final String? goalId;

  /// Contributions of one goal.
  const LedgerEntryQuery.forGoal(String this.goalId)
    : month = null,
      type = null,
      memberId = null;

  bool get hasFilters =>
      month != null || type != null || memberId != null || goalId != null;

  Map<String, dynamic> toQuery() => {
    'month': month,
    'type': type?.wireName,
    'memberId': memberId,
    'goalId': goalId,
  };

  LedgerEntryQuery copyWith({
    ValueGetter<String?>? month,
    ValueGetter<LedgerType?>? type,
    ValueGetter<String?>? memberId,
    ValueGetter<String?>? goalId,
  }) => LedgerEntryQuery(
    month: month == null ? this.month : month(),
    type: type == null ? this.type : type(),
    memberId: memberId == null ? this.memberId : memberId(),
    goalId: goalId == null ? this.goalId : goalId(),
  );

  @override
  bool operator ==(Object other) =>
      other is LedgerEntryQuery &&
      other.month == month &&
      other.type == type &&
      other.memberId == memberId &&
      other.goalId == goalId;

  @override
  int get hashCode => Object.hash(month, type, memberId, goalId);

  @override
  String toString() => 'LedgerEntryQuery(${toQuery()})';
}

/// Body of `POST /ledger/entries`.
@immutable
class LedgerEntryInput {
  const LedgerEntryInput({
    required this.type,
    required this.amount,
    required this.category,
    required this.date,
    this.note,
    this.memberId,
  });

  final LedgerType type;
  final double amount;
  final LedgerCategory category;

  /// Local calendar day; sent as local midnight in UTC.
  final DateTime date;
  final String? note;

  /// Whose money it is (null = the caller). Members may only use themselves.
  final String? memberId;

  Map<String, dynamic> toJson() => {
    'type': type.wireName,
    'amount': roundMoney(amount),
    'category': category.wireName,
    'date': date.toApiDate(),
    'note': ?trimOrNull(note),
    'memberId': ?trimOrNull(memberId),
  };

  @override
  bool operator ==(Object other) =>
      other is LedgerEntryInput &&
      other.type == type &&
      other.amount == amount &&
      other.category == category &&
      other.date == date &&
      other.note == note &&
      other.memberId == memberId;

  @override
  int get hashCode => Object.hash(type, amount, category, date, note, memberId);
}

/// Body of `PATCH /ledger/entries/:id`: only the fields that changed.
/// `note: null` in [fields] clears the note.
class LedgerEntryPatch extends PatchBody {
  const LedgerEntryPatch._(super.fields);

  /// Differences between [before] and the edited values. The amount of a
  /// goal-linked entry is never sent (the API rejects changing it).
  factory LedgerEntryPatch.diff(
    LedgerEntry before, {
    required LedgerType type,
    required double amount,
    required LedgerCategory category,
    required DateTime date,
    required String? note,
    required String? memberId,
  }) {
    final fields = <String, dynamic>{};
    if (type != before.type) fields['type'] = type.wireName;
    final rounded = roundMoney(amount);
    if (!before.isGoalLinked && rounded != roundMoney(before.amount)) {
      fields['amount'] = rounded;
    }
    if (category != before.category || type != before.type) {
      fields['category'] = category.wireName;
    }
    final day = DateTime(date.year, date.month, date.day);
    if (!day.isSameDay(before.date)) fields['date'] = day.toApiDate();
    final newNote = trimOrNull(note);
    if (newNote != before.note) fields['note'] = newNote;
    final newMember = trimOrNull(memberId);
    if (newMember != null && newMember != before.memberId) {
      fields['memberId'] = newMember;
    }
    return LedgerEntryPatch._(Map.unmodifiable(fields));
  }
}

/// Body of `POST /goals`.
@immutable
class GoalInput {
  const GoalInput({
    required this.title,
    required this.targetAmount,
    this.description,
    this.targetDate,
  });

  final String title;
  final double targetAmount;
  final String? description;
  final DateTime? targetDate;

  Map<String, dynamic> toJson() => {
    'title': title.trim(),
    'targetAmount': roundMoney(targetAmount),
    'description': ?trimOrNull(description),
    'targetDate': ?targetDate?.toApiDate(),
  };
}

/// Body of `PATCH /goals/:id`: only the fields that changed (`null` clears
/// `description` / `targetDate`).
class GoalPatch extends PatchBody {
  const GoalPatch._(super.fields);

  /// Status change only (archive / restore).
  factory GoalPatch.status(GoalStatus status) =>
      GoalPatch._(Map.unmodifiable({'status': status.wireName}));

  factory GoalPatch.diff(
    SavingsGoal before, {
    required String title,
    required double targetAmount,
    required String? description,
    required DateTime? targetDate,
  }) {
    final fields = <String, dynamic>{};
    final t = title.trim();
    if (t != before.title) fields['title'] = t;
    final target = roundMoney(targetAmount);
    if (target != roundMoney(before.targetAmount)) {
      fields['targetAmount'] = target;
    }
    final d = trimOrNull(description);
    if (d != before.description) fields['description'] = d;
    final oldDate = before.targetDate;
    final changedDate = targetDate == null || oldDate == null
        ? targetDate != oldDate
        : !targetDate.isSameDay(oldDate);
    if (changedDate) fields['targetDate'] = targetDate?.toApiDate();
    return GoalPatch._(Map.unmodifiable(fields));
  }
}

/// Body of `POST /goals/:id/contributions`.
@immutable
class GoalContributionInput {
  const GoalContributionInput({required this.amount, this.note, this.date});

  final double amount;
  final String? note;
  final DateTime? date;

  Map<String, dynamic> toJson() => {
    'amount': roundMoney(amount),
    'note': ?trimOrNull(note),
    'date': ?date?.toApiDate(),
  };
}
