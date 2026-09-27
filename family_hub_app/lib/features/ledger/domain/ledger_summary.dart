import 'package:flutter/foundation.dart';

import 'package:family_hub/features/ledger/domain/ledger_entry.dart';
import 'package:family_hub/shared/json.dart';

/// Whose money a [LedgerSummary] covers: the whole family (admins) or only
/// the caller (members).
enum SummaryScope {
  family,
  personal;

  String get wireName => enumWireName(this);

  static SummaryScope fromWire(Object? v, [SummaryScope fallback = personal]) =>
      enumByName(values, v, fallback);
}

/// Total of one category in a month (`byCategory` item).
@immutable
class CategoryTotal {
  const CategoryTotal({
    required this.type,
    required this.category,
    required this.amount,
  });

  factory CategoryTotal.fromJson(Map<String, dynamic> json) {
    final rawType = LedgerType.tryFromWire(json['type']);
    final rawCategory = LedgerCategory.tryFromWire(json['category']);
    final type = rawType ?? rawCategory?.type ?? LedgerType.expense;
    final amount = asDouble(json['amount']);
    return CategoryTotal(
      type: type,
      category: LedgerCategory.fromWire(json['category'], type: type),
      amount: amount < 0 ? -amount : amount,
    );
  }

  final LedgerType type;
  final LedgerCategory category;
  final double amount;

  Map<String, dynamic> toJson() => {
    'type': type.wireName,
    'category': category.wireName,
    'amount': amount,
  };

  @override
  bool operator ==(Object other) =>
      other is CategoryTotal &&
      other.type == type &&
      other.category == category &&
      other.amount == amount;

  @override
  int get hashCode => Object.hash(type, category, amount);

  @override
  String toString() => 'CategoryTotal(${category.wireName}: $amount)';
}

/// Category bars for one [LedgerType]: the biggest categories plus one
/// "Other" bucket ([rest]) that also absorbs the `other_*` category, so the
/// UI never shows two "Other" rows.
@immutable
class CategoryBreakdown {
  const CategoryBreakdown({
    required this.type,
    required this.items,
    required this.rest,
    required this.total,
  });

  final LedgerType type;

  /// Largest categories first (at most `maxItems`, `other_*` excluded).
  final List<CategoryTotal> items;

  /// Sum of every category not in [items] (including `other_*`).
  final double rest;

  /// Sum of all categories of [type].
  final double total;

  bool get isEmpty => total <= 0;

  /// Share of [amount] in [total] (0–1).
  double shareOf(double amount) =>
      total <= 0 ? 0 : (amount / total).clamp(0.0, 1.0);
}

/// Month totals (contract §8 `GET /ledger/summary`; also the dashboard's
/// `monthSummary`).
@immutable
class LedgerSummary {
  const LedgerSummary({
    required this.month,
    required this.currency,
    required this.scope,
    required this.income,
    required this.expense,
    required this.net,
    this.byCategory = const [],
  });

  /// An all-zero summary (e.g. before the first entry).
  const LedgerSummary.empty({
    required this.month,
    this.currency = '',
    this.scope = SummaryScope.personal,
  }) : income = 0,
       expense = 0,
       net = 0,
       byCategory = const [];

  factory LedgerSummary.fromJson(Map<String, dynamic> json) {
    final income = asDouble(json['income']);
    final expense = asDouble(json['expense']);
    final net = asDoubleOrNull(json['net']) ?? (income - expense);
    final categories =
        asMapList(
            json['byCategory'],
            CategoryTotal.fromJson,
          ).where((c) => c.amount > 0).toList()
          ..sort((a, b) => b.amount.compareTo(a.amount));
    return LedgerSummary(
      month: asStringOr(json['month'], '').trim(),
      currency: asStringOr(json['currency'], '').trim().toUpperCase(),
      scope: SummaryScope.fromWire(json['scope']),
      income: income < 0 ? 0 : income,
      expense: expense < 0 ? 0 : expense,
      net: net,
      byCategory: List.unmodifiable(categories),
    );
  }

  /// `YYYY-MM`.
  final String month;

  /// ISO-4217 code (may be empty on odd data — formatting then uses the
  /// family currency).
  final String currency;
  final SummaryScope scope;
  final double income;
  final double expense;

  /// `income − expense` (negative when more was spent than earned).
  final double net;

  /// Largest first.
  final List<CategoryTotal> byCategory;

  /// Nothing recorded this month.
  bool get isEmpty => income == 0 && expense == 0 && byCategory.isEmpty;

  bool get isFamily => scope == SummaryScope.family;

  /// Categories of [type], largest first.
  List<CategoryTotal> categoriesOf(LedgerType type) => [
    for (final c in byCategory)
      if (c.type == type) c,
  ];

  /// Top [maxItems] categories of [type] (excluding `other_*`) plus the
  /// remainder as [CategoryBreakdown.rest].
  CategoryBreakdown breakdown(LedgerType type, {int maxItems = 6}) {
    final all = categoriesOf(type);
    final ranked = [
      for (final c in all)
        if (!c.category.isOther) c,
    ];
    final top = ranked.take(maxItems < 0 ? 0 : maxItems).toList();
    final total = all.fold<double>(0, (sum, c) => sum + c.amount);
    final shown = top.fold<double>(0, (sum, c) => sum + c.amount);
    final rest = total - shown;
    return CategoryBreakdown(
      type: type,
      items: List.unmodifiable(top),
      rest: rest <= 0.004 ? 0 : (rest * 100).roundToDouble() / 100,
      total: total,
    );
  }

  Map<String, dynamic> toJson() => {
    'month': month,
    'currency': currency,
    'scope': scope.wireName,
    'income': income,
    'expense': expense,
    'net': net,
    'byCategory': [for (final c in byCategory) c.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is LedgerSummary &&
      other.month == month &&
      other.currency == currency &&
      other.scope == scope &&
      other.income == income &&
      other.expense == expense &&
      other.net == net &&
      listEquals(other.byCategory, byCategory);

  @override
  int get hashCode => Object.hash(
    month,
    currency,
    scope,
    income,
    expense,
    net,
    Object.hashAll(byCategory),
  );

  @override
  String toString() =>
      'LedgerSummary($month, ${scope.wireName}, +$income −$expense)';
}
