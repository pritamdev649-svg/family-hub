import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/features/ledger/domain/ledger_entry.dart';
import 'package:family_hub/features/ledger/domain/ledger_requests.dart';
import 'package:family_hub/features/ledger/domain/ledger_summary.dart';
import 'package:family_hub/features/ledger/domain/savings_goal.dart';

void main() {
  group('LedgerCategory', () {
    test('wire names match the contract', () {
      expect(LedgerCategory.incomeCategories.map((c) => c.wireName), [
        'salary',
        'business',
        'allowance',
        'gift',
        'interest',
        'other_income',
      ]);
      expect(LedgerCategory.expenseCategories.map((c) => c.wireName), [
        'groceries',
        'utilities',
        'rent',
        'education',
        'health',
        'transport',
        'dining',
        'shopping',
        'entertainment',
        'household_help',
        'savings',
        'other_expense',
      ]);
      expect(
        LedgerCategory.incomeCategories.length +
            LedgerCategory.expenseCategories.length,
        LedgerCategory.values.length,
      );
    });

    test('every category belongs to exactly its type list', () {
      for (final c in LedgerCategory.values) {
        expect(LedgerCategory.forType(c.type), contains(c));
        expect(c.isIncome, c.type == LedgerType.income);
      }
    });

    test('fromWire parses snake_case and falls back per type', () {
      expect(
        LedgerCategory.fromWire('household_help'),
        LedgerCategory.householdHelp,
      );
      expect(
        LedgerCategory.fromWire('bogus', type: LedgerType.income),
        LedgerCategory.otherIncome,
      );
      expect(LedgerCategory.fromWire(null), LedgerCategory.otherExpense);
      // Valid category, wrong type → the type's catch-all.
      expect(
        LedgerCategory.fromWire('salary', type: LedgerType.expense),
        LedgerCategory.otherExpense,
      );
    });

    test('manual categories exclude savings unless kept', () {
      expect(
        LedgerCategory.manualFor(LedgerType.expense),
        isNot(contains(LedgerCategory.savings)),
      );
      expect(
        LedgerCategory.manualFor(
          LedgerType.expense,
          keep: LedgerCategory.savings,
        ),
        contains(LedgerCategory.savings),
      );
      expect(
        LedgerCategory.manualFor(LedgerType.income),
        LedgerCategory.incomeCategories,
      );
    });
  });

  group('LedgerEntry.fromJson', () {
    test('parses a contract entry', () {
      final e = LedgerEntry.fromJson({
        'id': 'e1',
        'type': 'income',
        'amount': 1250.5,
        'category': 'other_income',
        'note': '  Bonus ',
        'date': '2026-09-25T18:30:00.000Z', // local midnight in India
        'memberId': 'm1',
        'memberName': 'Priya',
        'createdById': 'm2',
        'goalId': null,
        'createdAt': '2026-09-26T10:15:00.000Z',
      });
      expect(e.id, 'e1');
      expect(e.type, LedgerType.income);
      expect(e.amount, 1250.5);
      expect(e.category, LedgerCategory.otherIncome);
      expect(e.note, 'Bonus');
      expect(e.date, DateTime(2026, 9, 26));
      expect(e.memberName, 'Priya');
      expect(e.isGoalLinked, isFalse);
      expect(e.signedAmount, 1250.5);
      expect(e.createdAt, DateTime.utc(2026, 9, 26, 10, 15));
    });

    test('is defensive about missing and odd fields', () {
      final e = LedgerEntry.fromJson({
        '_id': 'x',
        'amount': '-99.5',
        'category': 'salary',
        'note': '   ',
        'goalId': '',
        'extra': {'ignored': true},
      });
      expect(e.id, 'x');
      // Missing type inferred from the category.
      expect(e.type, LedgerType.income);
      expect(e.amount, 99.5);
      expect(e.note, isNull);
      expect(e.goalId, isNull);
      expect(e.memberId, '');
      expect(e.date, DateTime.fromMillisecondsSinceEpoch(0));
    });

    test('unknown type and category fall back to expense / other', () {
      final e = LedgerEntry.fromJson({
        'type': 'transfer',
        'category': 'crypto',
      });
      expect(e.type, LedgerType.expense);
      expect(e.category, LedgerCategory.otherExpense);
      expect(e.signedAmount, -0.0);
    });

    test('canBeModifiedBy mirrors admin-or-creator', () {
      final e = LedgerEntry.fromJson({'createdById': 'm1', 'memberId': 'm2'});
      expect(e.canBeModifiedBy(memberId: 'm1', isAdmin: false), isTrue);
      expect(e.canBeModifiedBy(memberId: 'm2', isAdmin: false), isFalse);
      expect(e.canBeModifiedBy(memberId: 'm3', isAdmin: true), isTrue);
      expect(e.canBeModifiedBy(memberId: null, isAdmin: false), isFalse);
    });

    test('round-trips through toJson', () {
      final e = LedgerEntry.fromJson({
        'id': 'e1',
        'type': 'expense',
        'amount': 60,
        'category': 'savings',
        'date': DateTime(2026, 9, 1).toUtc().toIso8601String(),
        'memberId': 'm1',
        'memberName': 'Amit',
        'createdById': 'm1',
        'goalId': 'g1',
      });
      expect(LedgerEntry.fromJson(e.toJson()), e);
      expect(e.isGoalLinked, isTrue);
    });
  });

  group('SavingsGoal', () {
    test('parses the contract example', () {
      final g = SavingsGoal.fromJson({
        'id': 'g1',
        'title': 'Goa vacation',
        'description': '',
        'targetAmount': 60000,
        'savedAmount': 12500,
        'targetDate': null,
        'status': 'active',
        'progress': 0.2083,
        'createdById': 'm1',
      });
      expect(g.title, 'Goa vacation');
      expect(g.description, isNull);
      expect(g.progress, 0.2083);
      expect(g.remaining, 47500);
      expect(g.isActive, isTrue);
      expect(g.acceptsContributions, isTrue);
      expect(g.daysLeft(), isNull);
    });

    test('progress is clamped and computed when missing', () {
      expect(
        SavingsGoal.fromJson({
          'targetAmount': 100,
          'savedAmount': 250,
        }).progress,
        1,
      );
      expect(
        SavingsGoal.fromJson({
          'targetAmount': 100,
          'savedAmount': 25,
          'progress': 'oops',
        }).progress,
        0.25,
      );
      expect(SavingsGoal.fromJson({'progress': -3}).progress, 0);
      expect(SavingsGoal.fromJson({'progress': 7}).progress, 1);
      expect(SavingsGoal.fromJson(const {}).progress, 0);
    });

    test('remaining never goes negative and rounds to cents', () {
      expect(
        SavingsGoal.fromJson({
          'targetAmount': 100,
          'savedAmount': 120,
        }).remaining,
        0,
      );
      expect(
        SavingsGoal.fromJson({
          'targetAmount': 100.3,
          'savedAmount': 0.1,
        }).remaining,
        100.2,
      );
    });

    test(
      'unknown status falls back to active; archived rejects contributions',
      () {
        expect(
          SavingsGoal.fromJson({'status': 'paused'}).status,
          GoalStatus.active,
        );
        final archived = SavingsGoal.fromJson({'status': 'archived'});
        expect(archived.isArchived, isTrue);
        expect(archived.acceptsContributions, isFalse);
      },
    );

    test('daysLeft / isOverdue count calendar days', () {
      final now = DateTime(2026, 9, 26, 22, 30);
      SavingsGoal due(DateTime d) =>
          SavingsGoal(id: 'g', title: 't', targetAmount: 1, targetDate: d);
      expect(due(DateTime(2026, 9, 26)).daysLeft(now: now), 0);
      expect(due(DateTime(2026, 9, 27)).daysLeft(now: now), 1);
      expect(due(DateTime(2026, 12, 25)).daysLeft(now: now), 90);
      expect(due(DateTime(2026, 9, 20)).daysLeft(now: now), -6);
      expect(due(DateTime(2026, 9, 20)).isOverdue(now: now), isTrue);
      expect(
        due(
          DateTime(2026, 9, 20),
        ).copyWith(status: GoalStatus.achieved).isOverdue(now: now),
        isFalse,
      );
    });

    test('copyWith drops the server progress when amounts change', () {
      final g = SavingsGoal.fromJson({
        'targetAmount': 100,
        'savedAmount': 10,
        'progress': 0.1,
      });
      expect(g.copyWith(title: 'x').progress, 0.1);
      expect(g.copyWith(savedAmount: 50).progress, 0.5);
    });
  });

  group('LedgerSummary', () {
    final json = {
      'month': '2026-09',
      'currency': 'inr',
      'scope': 'family',
      'income': 218000,
      'expense': 71500.5,
      'net': 146499.5,
      'byCategory': [
        {'type': 'expense', 'category': 'groceries', 'amount': 7000},
        {'type': 'expense', 'category': 'rent', 'amount': 28000},
        {'type': 'expense', 'category': 'household_help', 'amount': 11000},
        {'type': 'expense', 'category': 'utilities', 'amount': 3500},
        {'type': 'expense', 'category': 'education', 'amount': 3200},
        {'type': 'expense', 'category': 'transport', 'amount': 3200},
        {'type': 'expense', 'category': 'dining', 'amount': 980},
        {'type': 'expense', 'category': 'health', 'amount': 1200},
        {'type': 'expense', 'category': 'other_expense', 'amount': 13420.5},
        {'type': 'income', 'category': 'salary', 'amount': 205000},
        {'type': 'income', 'category': 'business', 'amount': 13000},
        {'type': 'expense', 'category': 'shopping', 'amount': 0},
        'junk',
      ],
    };

    test('parses totals and sorts categories', () {
      final s = LedgerSummary.fromJson(json);
      expect(s.month, '2026-09');
      expect(s.currency, 'INR');
      expect(s.isFamily, isTrue);
      expect(s.net, 146499.5);
      expect(s.isEmpty, isFalse);
      // Zero-amount categories and junk are dropped; largest first.
      expect(s.byCategory.length, 11);
      expect(s.byCategory.first.category, LedgerCategory.salary);
      expect(s.categoriesOf(LedgerType.income).map((c) => c.category), [
        LedgerCategory.salary,
        LedgerCategory.business,
      ]);
    });

    test('breakdown keeps the top 6 and folds the rest + other into Other', () {
      final b = LedgerSummary.fromJson(json).breakdown(LedgerType.expense);
      expect(b.items.map((c) => c.category), [
        LedgerCategory.rent,
        LedgerCategory.householdHelp,
        LedgerCategory.groceries,
        LedgerCategory.utilities,
        LedgerCategory.education,
        LedgerCategory.transport,
      ]);
      // health 1200 + dining 980 + other_expense 13420.5
      expect(b.rest, 15600.5);
      expect(b.total, 71500.5);
      expect(b.shareOf(28000), closeTo(0.3916, 0.0001));
    });

    test('net falls back to income − expense; missing data is empty', () {
      final s = LedgerSummary.fromJson({'income': 100, 'expense': 150});
      expect(s.net, -50);
      expect(s.scope, SummaryScope.personal);
      final empty = LedgerSummary.fromJson(const {});
      expect(empty.isEmpty, isTrue);
      expect(empty.breakdown(LedgerType.expense).isEmpty, isTrue);
    });
  });

  group('requests', () {
    final before = LedgerEntry.fromJson({
      'id': 'e1',
      'type': 'expense',
      'amount': 100,
      'category': 'groceries',
      'note': 'Veg',
      'date': DateTime(2026, 9, 20).toUtc().toIso8601String(),
      'memberId': 'm1',
      'memberName': 'Amit',
      'createdById': 'm1',
    });

    test('entry input sends rounded amount and local-midnight date', () {
      final json = LedgerEntryInput(
        type: LedgerType.expense,
        amount: 10.555,
        category: LedgerCategory.householdHelp,
        date: DateTime(2026, 9, 26),
        note: '  ',
      ).toJson();
      expect(json['amount'], 10.56);
      expect(json['category'], 'household_help');
      expect(json['date'], DateTime(2026, 9, 26).toUtc().toIso8601String());
      expect(json.containsKey('note'), isFalse);
      expect(json.containsKey('memberId'), isFalse);
    });

    test('entry patch contains only changed fields', () {
      final same = LedgerEntryPatch.diff(
        before,
        type: LedgerType.expense,
        amount: 100,
        category: LedgerCategory.groceries,
        date: DateTime(2026, 9, 20, 15),
        note: ' Veg ',
        memberId: 'm1',
      );
      expect(same.isEmpty, isTrue);

      final changed = LedgerEntryPatch.diff(
        before,
        type: LedgerType.income,
        amount: 120.5,
        category: LedgerCategory.gift,
        date: DateTime(2026, 9, 21),
        note: '',
        memberId: 'm2',
      );
      expect(changed.toJson(), {
        'type': 'income',
        'amount': 120.5,
        'category': 'gift',
        'date': DateTime(2026, 9, 21).toUtc().toIso8601String(),
        'note': null,
        'memberId': 'm2',
      });
    });

    test('goal-linked entries never send an amount', () {
      final linked = before.copyWith(goalId: () => 'g1');
      final patch = LedgerEntryPatch.diff(
        linked,
        type: LedgerType.expense,
        amount: 999,
        category: LedgerCategory.groceries,
        date: DateTime(2026, 9, 20),
        note: 'Veg',
        memberId: null,
      );
      expect(patch.isEmpty, isTrue);
    });

    test('goal patch diffs and clears optional fields', () {
      final goal = SavingsGoal.fromJson({
        'id': 'g1',
        'title': 'Goa',
        'targetAmount': 60000,
        'description': 'Trip',
        'targetDate': DateTime(2027, 1, 15).toUtc().toIso8601String(),
      });
      expect(
        GoalPatch.diff(
          goal,
          title: ' Goa ',
          targetAmount: 60000,
          description: 'Trip',
          targetDate: DateTime(2027, 1, 15, 9),
        ).isEmpty,
        isTrue,
      );
      expect(
        GoalPatch.diff(
          goal,
          title: 'Goa trip',
          targetAmount: 65000,
          description: null,
          targetDate: null,
        ).toJson(),
        {
          'title': 'Goa trip',
          'targetAmount': 65000.0,
          'description': null,
          'targetDate': null,
        },
      );
      expect(GoalPatch.status(GoalStatus.archived).toJson(), {
        'status': 'archived',
      });
    });

    test('entry query equality and query map', () {
      const a = LedgerEntryQuery(month: '2026-09', type: LedgerType.income);
      const b = LedgerEntryQuery(month: '2026-09', type: LedgerType.income);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.toQuery(), {
        'month': '2026-09',
        'type': 'income',
        'memberId': null,
        'goalId': null,
      });
      expect(const LedgerEntryQuery.forGoal('g1').goalId, 'g1');
      expect(const LedgerEntryQuery().hasFilters, isFalse);
      expect(a.copyWith(month: () => null).month, isNull);
    });
  });
}
