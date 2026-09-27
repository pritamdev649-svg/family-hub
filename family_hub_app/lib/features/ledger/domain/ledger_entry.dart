import 'package:flutter/foundation.dart';

import 'package:family_hub/shared/json.dart';

/// Direction of a ledger record (wire: `income|expense`).
enum LedgerType {
  income,
  expense;

  /// Value sent to / received from the API.
  String get wireName => enumWireName(this);

  bool get isIncome => this == income;

  /// Unknown / missing values fall back to [fallback] (default [expense]).
  static LedgerType fromWire(Object? v, [LedgerType fallback = expense]) =>
      enumByName(values, v, fallback);

  /// Nullable variant, e.g. for an optional `?type=` filter.
  static LedgerType? tryFromWire(Object? v) => enumByNameOrNull(values, v);
}

/// Ledger categories with the contract wire names
/// (docs/03-API_CONTRACT.md §8). Every category belongs to exactly one
/// [LedgerType]; the Dart names are camelCase (`householdHelp` ↔
/// `household_help`).
enum LedgerCategory {
  // Income
  salary(LedgerType.income),
  business(LedgerType.income),
  allowance(LedgerType.income),
  gift(LedgerType.income),
  interest(LedgerType.income),
  otherIncome(LedgerType.income),

  // Expense
  groceries(LedgerType.expense),
  utilities(LedgerType.expense),
  rent(LedgerType.expense),
  education(LedgerType.expense),
  health(LedgerType.expense),
  transport(LedgerType.expense),
  dining(LedgerType.expense),
  shopping(LedgerType.expense),
  entertainment(LedgerType.expense),
  householdHelp(LedgerType.expense),
  savings(LedgerType.expense),
  otherExpense(LedgerType.expense);

  const LedgerCategory(this.type);

  /// The type this category is valid for.
  final LedgerType type;

  bool get isIncome => type.isIncome;

  /// Value sent to / received from the API (`other_income`, …).
  String get wireName => enumWireName(this);

  /// The catch-all bucket (`other_income` / `other_expense`).
  bool get isOther => this == otherIncome || this == otherExpense;

  /// `savings` entries are created by goal contributions
  /// (`POST /goals/:id/contributions`), not typed in by hand.
  bool get isGoalOnly => this == savings;

  /// Income categories in contract order.
  static const List<LedgerCategory> incomeCategories = [
    salary,
    business,
    allowance,
    gift,
    interest,
    otherIncome,
  ];

  /// Expense categories in contract order.
  static const List<LedgerCategory> expenseCategories = [
    groceries,
    utilities,
    rent,
    education,
    health,
    transport,
    dining,
    shopping,
    entertainment,
    householdHelp,
    savings,
    otherExpense,
  ];

  /// Every category valid for [type] (contract order).
  static List<LedgerCategory> forType(LedgerType type) =>
      type.isIncome ? incomeCategories : expenseCategories;

  /// Categories offered when a person records an entry by hand: everything
  /// valid for [type] except goal-only categories ([savings]). [keep] (e.g.
  /// the current category of an entry being edited) is always included.
  static List<LedgerCategory> manualFor(
    LedgerType type, {
    LedgerCategory? keep,
  }) => [
    for (final c in forType(type))
      if (!c.isGoalOnly || c == keep) c,
  ];

  /// Catch-all category of [type].
  static LedgerCategory otherFor(LedgerType type) =>
      type.isIncome ? otherIncome : otherExpense;

  /// Parses a wire value. Unknown values — or a category that is not valid
  /// for [type] — fall back to the "other" category of [type] (expense when
  /// [type] is null).
  static LedgerCategory fromWire(Object? v, {LedgerType? type}) {
    final parsed = enumByNameOrNull(values, v);
    final t = type ?? parsed?.type ?? LedgerType.expense;
    if (parsed != null && parsed.type == t) return parsed;
    return otherFor(t);
  }

  static LedgerCategory? tryFromWire(Object? v) => enumByNameOrNull(values, v);
}

/// One income / expense record (contract §8 `LedgerEntry`).
///
/// FamilyHub only **records** money — nothing here moves real money
/// (docs/08-COMPLIANCE.md #18).
@immutable
class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.type,
    required this.amount,
    required this.category,
    required this.date,
    required this.memberId,
    required this.memberName,
    required this.createdById,
    this.note,
    this.goalId,
    this.createdAt,
  });

  factory LedgerEntry.fromJson(Map<String, dynamic> json) {
    final rawType = LedgerType.tryFromWire(json['type']);
    final rawCategory = LedgerCategory.tryFromWire(json['category']);
    // A missing / unknown type is inferred from a known category.
    final type = rawType ?? rawCategory?.type ?? LedgerType.expense;
    final amount = asDouble(json['amount']);
    return LedgerEntry(
      id: asStringOr(json['id'] ?? json['_id'], ''),
      type: type,
      amount: amount < 0 ? -amount : amount,
      category: LedgerCategory.fromWire(json['category'], type: type),
      note: asNonEmptyString(json['note'])?.trim(),
      date:
          calendarDate(parseDate(json['date'])) ??
          calendarDate(parseDate(json['createdAt'])) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      memberId: asStringOr(json['memberId'], ''),
      memberName: asStringOr(json['memberName'], '').trim(),
      createdById: asStringOr(json['createdById'], ''),
      goalId: asNonEmptyString(json['goalId']),
      createdAt: parseDate(json['createdAt']),
    );
  }

  final String id;
  final LedgerType type;

  /// Positive amount in major units (`1250.5` = ₹1,250.50).
  final double amount;
  final LedgerCategory category;
  final String? note;

  /// Business date as a **local calendar day** (midnight). Sent back with
  /// `DateX.toApiDate()`.
  final DateTime date;

  /// Whose money it is.
  final String memberId;

  /// Snapshot of the member name (kept after the member is removed).
  final String memberName;
  final String createdById;

  /// Set on `expense/savings` entries created by a goal contribution.
  final String? goalId;
  final DateTime? createdAt;

  bool get isIncome => type.isIncome;

  /// Created by a goal contribution: its amount cannot be edited (delete and
  /// contribute again instead).
  bool get isGoalLinked => goalId != null;

  /// Signed amount (`+` income, `−` expense) for totals.
  double get signedAmount => isIncome ? amount : -amount;

  /// Mirrors the backend rule for `PATCH` / `DELETE`: admins and the
  /// creator may change an entry.
  bool canBeModifiedBy({required String? memberId, required bool isAdmin}) =>
      isAdmin ||
      (memberId != null && memberId.isNotEmpty && memberId == createdById);

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.wireName,
    'amount': amount,
    'category': category.wireName,
    'note': note,
    'date': isoOrNull(date),
    'memberId': memberId,
    'memberName': memberName,
    'createdById': createdById,
    'goalId': goalId,
    'createdAt': isoOrNull(createdAt),
  };

  LedgerEntry copyWith({
    String? id,
    LedgerType? type,
    double? amount,
    LedgerCategory? category,
    ValueGetter<String?>? note,
    DateTime? date,
    String? memberId,
    String? memberName,
    String? createdById,
    ValueGetter<String?>? goalId,
    ValueGetter<DateTime?>? createdAt,
  }) => LedgerEntry(
    id: id ?? this.id,
    type: type ?? this.type,
    amount: amount ?? this.amount,
    category: category ?? this.category,
    note: note == null ? this.note : note(),
    date: date ?? this.date,
    memberId: memberId ?? this.memberId,
    memberName: memberName ?? this.memberName,
    createdById: createdById ?? this.createdById,
    goalId: goalId == null ? this.goalId : goalId(),
    createdAt: createdAt == null ? this.createdAt : createdAt(),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LedgerEntry &&
          other.id == id &&
          other.type == type &&
          other.amount == amount &&
          other.category == category &&
          other.note == note &&
          other.date == date &&
          other.memberId == memberId &&
          other.memberName == memberName &&
          other.createdById == createdById &&
          other.goalId == goalId &&
          other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(
    id,
    type,
    amount,
    category,
    note,
    date,
    memberId,
    memberName,
    createdById,
    goalId,
    createdAt,
  );

  @override
  String toString() =>
      'LedgerEntry($id, ${type.wireName}, $amount, ${category.wireName}, $date)';
}
