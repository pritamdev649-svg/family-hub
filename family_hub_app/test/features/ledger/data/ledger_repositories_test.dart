import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/network/api_exception.dart';
import 'package:family_hub/core/utils/date_x.dart';
import 'package:family_hub/features/ledger/data/goal_repository.dart';
import 'package:family_hub/features/ledger/data/ledger_mock_handlers.dart';
import 'package:family_hub/features/ledger/data/ledger_repository.dart';
import 'package:family_hub/features/ledger/domain/ledger_entry.dart';
import 'package:family_hub/features/ledger/domain/ledger_requests.dart';
import 'package:family_hub/features/ledger/domain/ledger_summary.dart';
import 'package:family_hub/features/ledger/domain/savings_goal.dart';

import '../ledger_test_utils.dart';

/// Repositories end-to-end through the envelope-aware ApiClient and the
/// in-memory mock backend (contract paths, JSON and error mapping).
void main() {
  late LedgerRepository ledger;
  late GoalRepository goals;

  setUp(() {
    final api = mockLedgerApi().api;
    ledger = LedgerRepository(api);
    goals = GoalRepository(api);
  });

  test('lists, pages and filters entries', () async {
    final first = await ledger.listEntries(limit: 10);
    expect(first.items, hasLength(10));
    expect(first.hasMore, isTrue);
    final second = await ledger.listEntries(page: 2, limit: 10);
    expect(second.page, 2);
    expect(
      first.items
          .map((e) => e.id)
          .toSet()
          .intersection(second.items.map((e) => e.id).toSet()),
      isEmpty,
    );

    final income = await ledger.listEntries(
      query: LedgerEntryQuery(
        month: DateTime.now().monthKey,
        type: LedgerType.income,
      ),
      limit: 100,
    );
    expect(income.items.every((e) => e.isIncome), isTrue);
  });

  test('create → update → delete an entry', () async {
    final created = await ledger.createEntry(
      LedgerEntryInput(
        type: LedgerType.expense,
        amount: 1234.56,
        category: LedgerCategory.householdHelp,
        date: DateTime.now().startOfDay,
        note: 'Driver',
      ),
    );
    expect(created.amount, 1234.56);
    expect(created.category, LedgerCategory.householdHelp);
    expect(created.date, DateTime.now().startOfDay);

    final updated = await ledger.updateEntry(
      created.id,
      LedgerEntryPatch.diff(
        created,
        type: LedgerType.expense,
        amount: 1500,
        category: LedgerCategory.transport,
        date: created.date,
        note: null,
        memberId: null,
      ),
    );
    expect(updated!.amount, 1500);
    expect(updated.category, LedgerCategory.transport);
    expect(updated.note, isNull);

    await ledger.deleteEntry(created.id);
    final all = await ledger.listEntries(limit: 100);
    expect(all.items.map((e) => e.id), isNot(contains(created.id)));
  });

  test('summary is family scope for the admin', () async {
    final s = await ledger.summary(month: DateTime.now().monthKey);
    expect(s.scope, SummaryScope.family);
    expect(s.currency, 'INR');
    expect(s.income, greaterThan(0));
    expect(s.breakdown(LedgerType.expense).items, isNotEmpty);
  });

  test('goals: list, contribute until achieved, archive', () async {
    final list = await goals.listGoals();
    final goa = list.single;
    expect(goa.id, mockGoaGoalId);

    final result = await goals.contribute(
      goa.id,
      const GoalContributionInput(amount: 47500, note: 'Bonus'),
    );
    expect(result.goal.isAchieved, isTrue);
    expect(result.goal.progress, 1);
    expect(result.entry.category, LedgerCategory.savings);
    expect(result.entry.goalId, goa.id);

    final archived = await goals.updateGoal(
      goa.id,
      GoalPatch.status(GoalStatus.archived),
    );
    expect(archived!.isArchived, isTrue);

    await expectLater(
      goals.contribute(goa.id, const GoalContributionInput(amount: 1)),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', ApiErrorCode.validation)
            .having((e) => e.statusCode, 'status', 409),
      ),
    );
  });

  test('create goal and empty patches are not sent', () async {
    final goal = await goals.createGoal(
      GoalInput(
        title: 'School fees fund',
        targetAmount: 40000,
        targetDate: DateTime(DateTime.now().year + 1, 4, 1),
      ),
    );
    expect(goal.title, 'School fees fund');
    expect(goal.targetDate, DateTime(DateTime.now().year + 1, 4, 1));
    expect(
      await goals.updateGoal(
        goal.id,
        GoalPatch.diff(
          goal,
          title: goal.title,
          targetAmount: goal.targetAmount,
          description: null,
          targetDate: goal.targetDate,
        ),
      ),
      isNull,
    );
    await goals.deleteGoal(goal.id);
    expect(
      (await goals.listGoals()).map((g) => g.id),
      isNot(contains(goal.id)),
    );
  });

  test('maps API errors (404 for unknown ids, 422 validation)', () async {
    await expectLater(
      ledger.deleteEntry('ffffffffffffffffffffffff'),
      throwsA(
        isA<ApiException>().having((e) => e.isNotFound, 'notFound', true),
      ),
    );
    await expectLater(
      goals.createGoal(const GoalInput(title: '', targetAmount: 1)),
      throwsA(
        isA<ApiException>().having((e) => e.isValidation, 'validation', true),
      ),
    );
  });
}
