import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/network/api_exception.dart';
import 'package:family_hub/core/utils/date_x.dart';
import 'package:family_hub/features/ledger/application/ledger_providers.dart';
import 'package:family_hub/features/ledger/domain/ledger_entry.dart';
import 'package:family_hub/features/ledger/domain/ledger_requests.dart';
import 'package:family_hub/features/ledger/domain/ledger_summary.dart';
import 'package:family_hub/features/ledger/domain/savings_goal.dart';
import 'package:family_hub/shared/providers/shared_providers.dart';

import '../ledger_test_utils.dart';

void main() {
  late FakeLedgerRepository ledger;
  late FakeGoalRepository goals;
  late ProviderContainer container;

  ProviderContainer create({bool signedIn = true}) {
    final c = ProviderContainer(
      retry: (_, _) => null,
      overrides: ledgerOverrides(
        ledger: ledger,
        goals: goals,
        signedIn: signedIn,
      ),
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    ledger = FakeLedgerRepository(
      entries: [
        for (var i = 0; i < 45; i++)
          testEntry(
            id: 'e$i',
            type: i.isEven ? LedgerType.expense : LedgerType.income,
            category: i.isEven
                ? LedgerCategory.groceries
                : LedgerCategory.salary,
          ),
      ],
      summaryResult: const LedgerSummary(
        month: '2026-09',
        currency: 'INR',
        scope: SummaryScope.family,
        income: 100,
        expense: 40,
        net: 60,
      ),
    );
    goals = FakeGoalRepository(goals: [testGoal()]);
    container = create();
  });

  group('month helpers', () {
    final now = DateTime(2026, 9, 26, 14);

    test('clamp to the current month and normalise to the first day', () {
      expect(currentLedgerMonth(now), DateTime(2026, 9));
      expect(
        clampLedgerMonth(DateTime(2027, 2, 10), now: now),
        DateTime(2026, 9),
      );
      expect(
        clampLedgerMonth(DateTime(2026, 3, 31), now: now),
        DateTime(2026, 3),
      );
      expect(canGoToNextMonth(DateTime(2026, 8), now: now), isTrue);
      expect(canGoToNextMonth(DateTime(2026, 9, 15), now: now), isFalse);
    });

    test('SelectedLedgerMonth steps back and never past today', () {
      final notifier = container.read(selectedLedgerMonthProvider.notifier);
      final current = currentLedgerMonth();
      expect(container.read(selectedLedgerMonthProvider), current);
      expect(notifier.canGoNext, isFalse);
      notifier.next();
      expect(container.read(selectedLedgerMonthProvider), current);

      notifier.previous();
      notifier.previous();
      expect(
        container.read(selectedLedgerMonthProvider),
        current.addMonths(-2),
      );
      notifier.next();
      expect(
        container.read(selectedLedgerMonthProvider),
        current.addMonths(-1),
      );

      notifier.select(current.addMonths(5));
      expect(container.read(selectedLedgerMonthProvider), current);
    });
  });

  group('summary, recent entries and goals', () {
    test('summary and recent entries load for a month key', () async {
      final s = await container.read(ledgerSummaryProvider('2026-09').future);
      expect(s.net, 60);
      expect(ledger.summaryCalls, ['2026-09']);

      final recent = await container.read(
        recentLedgerEntriesProvider('2026-09').future,
      );
      expect(recent, hasLength(recentEntriesCount));
      expect(ledger.listCalls.last.query.month, '2026-09');
      expect(ledger.listCalls.last.limit, recentEntriesCount);
    });

    test('signed out → empty data without requests', () async {
      final c = create(signedIn: false);
      final s = await c.read(ledgerSummaryProvider('2026-09').future);
      expect(s.isEmpty, isTrue);
      expect(await c.read(savingsGoalsProvider.future), isEmpty);
      expect(ledger.summaryCalls, isEmpty);
      expect(goals.listCalls, 0);
    });

    test('savingsGoalProvider finds a goal or throws NOT_FOUND', () async {
      final sub = container.listen(savingsGoalProvider('g1'), (_, _) {});
      addTearDown(sub.close);
      expect(
        (await container.read(savingsGoalProvider('g1').future)).title,
        'Goa vacation',
      );

      final missing = container.listen(savingsGoalProvider('nope'), (_, _) {});
      addTearDown(missing.close);
      await expectLater(
        container.read(savingsGoalProvider('nope').future),
        throwsA(
          isA<ApiException>().having((e) => e.isNotFound, 'notFound', true),
        ),
      );
    });

    test('markChanged(goals) refetches the goals', () async {
      final sub = container.listen(savingsGoalsProvider, (_, _) {});
      addTearDown(sub.close);
      await container.read(savingsGoalsProvider.future);
      expect(goals.listCalls, 1);
      container.read(dataRefreshProvider.notifier).markChanged({
        DataScope.goals,
      });
      await container.read(savingsGoalsProvider.future);
      expect(goals.listCalls, 2);
    });
  });

  group('LedgerEntriesController', () {
    const query = LedgerEntryQuery(month: '2026-09');

    test('loads page by page and stops at the end', () async {
      final sub = container.listen(ledgerEntriesProvider(query), (_, _) {});
      addTearDown(sub.close);
      final notifier = container.read(ledgerEntriesProvider(query).notifier);

      var state = await container.read(ledgerEntriesProvider(query).future);
      expect(state.items, hasLength(20));
      expect(state.hasMore, isTrue);

      await notifier.loadMore();
      state = container.read(ledgerEntriesProvider(query)).requireValue;
      expect(state.items, hasLength(40));
      expect(state.isLoadingMore, isFalse);

      await notifier.loadMore();
      state = container.read(ledgerEntriesProvider(query)).requireValue;
      expect(state.items, hasLength(45));
      expect(state.hasMore, isFalse);
      expect(state.items.map((e) => e.id).toSet(), hasLength(45));

      final calls = ledger.listCalls.length;
      await notifier.loadMore(); // nothing more → no request
      expect(ledger.listCalls.length, calls);
      expect(ledger.listCalls.map((c) => c.page), [1, 2, 3]);
      expect(ledger.listCalls.every((c) => c.query == query), isTrue);
    });

    test('a failed page keeps the loaded items and rethrows', () async {
      final sub = container.listen(ledgerEntriesProvider(query), (_, _) {});
      addTearDown(sub.close);
      await container.read(ledgerEntriesProvider(query).future);
      ledger.failNextList = const ApiException(
        code: ApiErrorCode.network,
        message: 'offline',
      );
      await expectLater(
        container.read(ledgerEntriesProvider(query).notifier).loadMore(),
        throwsA(isA<ApiException>()),
      );
      final state = container.read(ledgerEntriesProvider(query)).requireValue;
      expect(state.items, hasLength(20));
      expect(state.isLoadingMore, isFalse);
      expect(state.hasMore, isTrue);
    });

    test('a ledger change starts over from page 1', () async {
      final sub = container.listen(ledgerEntriesProvider(query), (_, _) {});
      addTearDown(sub.close);
      await container.read(ledgerEntriesProvider(query).future);
      await container.read(ledgerEntriesProvider(query).notifier).loadMore();
      expect(
        container.read(ledgerEntriesProvider(query)).requireValue.items,
        hasLength(40),
      );

      container.read(dataRefreshProvider.notifier).markChanged({
        DataScope.ledger,
      });
      final state = await container.read(ledgerEntriesProvider(query).future);
      expect(state.items, hasLength(20));
      expect(ledger.listCalls.last.page, 1);
    });

    test('filters are passed to the repository', () async {
      const goalQuery = LedgerEntryQuery.forGoal('g1');
      ledger.entries.add(testEntry(id: 'c1', goalId: 'g1'));
      final sub = container.listen(ledgerEntriesProvider(goalQuery), (_, _) {});
      addTearDown(sub.close);
      final state = await container.read(
        ledgerEntriesProvider(goalQuery).future,
      );
      expect(state.items.map((e) => e.id), ['c1']);
    });
  });

  group('LedgerActions', () {
    Map<DataScope, int> counters() => container.read(dataRefreshProvider);

    test('every successful mutation marks ledger + goals changed', () async {
      final actions = container.read(ledgerActionsProvider);
      final before = counters();

      await actions.createEntry(
        LedgerEntryInput(
          type: LedgerType.expense,
          amount: 10,
          category: LedgerCategory.dining,
          date: DateTime(2026, 9, 26),
        ),
      );
      await actions.deleteEntry('e0');
      await actions.contribute('g1', const GoalContributionInput(amount: 5));
      await actions.setGoalStatus('g1', GoalStatus.archived);
      await actions.deleteGoal('g1');

      final after = counters();
      expect(after[DataScope.ledger]! - before[DataScope.ledger]!, 5);
      expect(after[DataScope.goals]! - before[DataScope.goals]!, 5);
      expect(after[DataScope.tasks], before[DataScope.tasks]);
      expect(ledger.created, hasLength(1));
      expect(ledger.deleted, ['e0']);
      expect(goals.contributions.single.$1, 'g1');
      expect(goals.updated.single.$2.toJson(), {'status': 'archived'});
      expect(goals.deleted, ['g1']);
    });

    test('empty patches and failures do not mark anything changed', () async {
      final actions = container.read(ledgerActionsProvider);
      final before = counters();
      final entry = ledger.entries.first;
      final result = await actions.updateEntry(
        entry.id,
        LedgerEntryPatch.diff(
          entry,
          type: entry.type,
          amount: entry.amount,
          category: entry.category,
          date: entry.date,
          note: entry.note,
          memberId: entry.memberId,
        ),
      );
      expect(result, isNull);
      await expectLater(
        actions.contribute('missing', const GoalContributionInput(amount: 1)),
        throwsA(anything),
      );
      expect(counters(), before);
    });
  });

  group('edge cases: stale data, permissions, session', () {
    Map<DataScope, int> counters() => container.read(dataRefreshProvider);
    int delta(Map<DataScope, int> before, DataScope scope) =>
        counters()[scope]! - before[scope]!;

    test('404 / 409 / timeout refresh the lists and are rethrown', () async {
      final actions = container.read(ledgerActionsProvider);
      final before = counters();

      ledger.failNextWrite = notFoundError;
      await expectLater(actions.deleteEntry('e0'), throwsA(notFoundError));
      goals.failNextWrite = validationError(['goalId'], status: 409);
      await expectLater(
        actions.contribute('g1', const GoalContributionInput(amount: 5)),
        throwsA(isA<ApiException>()),
      );
      ledger.failNextWrite = timeoutError;
      await expectLater(
        actions.createEntry(
          LedgerEntryInput(
            type: LedgerType.expense,
            amount: 10,
            category: LedgerCategory.dining,
            date: DateTime(2026, 9, 26),
          ),
        ),
        throwsA(timeoutError),
      );

      expect(delta(before, DataScope.ledger), 3);
      expect(delta(before, DataScope.goals), 3);
      expect(ledger.deleted, isEmpty);
    });

    test(
      '422 memberId refreshes the members; other 422s change nothing',
      () async {
        final actions = container.read(ledgerActionsProvider);
        final before = counters();
        final input = LedgerEntryInput(
          type: LedgerType.expense,
          amount: 10,
          category: LedgerCategory.dining,
          date: DateTime(2026, 9, 26),
          memberId: 'gone',
        );
        ledger.failNextWrite = validationError(['memberId']);
        await expectLater(
          actions.createEntry(input),
          throwsA(isA<ApiException>()),
        );
        expect(delta(before, DataScope.members), 1);
        expect(delta(before, DataScope.ledger), 0);

        ledger.failNextWrite = validationError(['amount']);
        await expectLater(
          actions.createEntry(input),
          throwsA(isA<ApiException>()),
        );
        expect(delta(before, DataScope.members), 1);
        expect(delta(before, DataScope.ledger), 0);
      },
    );

    test('FORBIDDEN / NO_FAMILY writes resync the session', () async {
      final recorder = ResyncRecorder();
      final c = ProviderContainer(
        retry: (_, _) => null,
        overrides: ledgerOverrides(
          ledger: ledger,
          goals: goals,
          resync: recorder,
        ),
      );
      addTearDown(c.dispose);
      final actions = c.read(ledgerActionsProvider);

      goals.failNextWrite = forbiddenError;
      await expectLater(
        actions.setGoalStatus('g1', GoalStatus.archived),
        throwsA(forbiddenError),
      );
      await pumpEventQueue();
      expect(recorder.calls, 1);

      ledger.failNextWrite = noFamilyError;
      await expectLater(actions.deleteEntry('e1'), throwsA(noFamilyError));
      await pumpEventQueue();
      expect(recorder.calls, 2);
    });

    test('a NO_FAMILY read resyncs the session', () async {
      final recorder = ResyncRecorder();
      final c = ProviderContainer(
        retry: (_, _) => null,
        overrides: ledgerOverrides(
          ledger: ledger,
          goals: goals,
          resync: recorder,
        ),
      );
      addTearDown(c.dispose);
      ledger.failNextSummary = noFamilyError;
      final sub = c.listen(ledgerSummaryProvider('2026-09'), (_, _) {});
      addTearDown(sub.close);
      await expectLater(
        c.read(ledgerSummaryProvider('2026-09').future),
        throwsA(anything),
      );
      await pumpEventQueue();
      expect(recorder.calls, 1);
    });

    test(
      'concurrent resync requests share one refresh; errors are swallowed',
      () async {
        var calls = 0;
        final done = Completer<void>();
        final resync = LedgerSessionResync(() {
          calls++;
          return done.future;
        });
        resync();
        resync();
        resync();
        expect(calls, 1);
        done.completeError(StateError('offline'));
        await pumpEventQueue();
        resync();
        expect(calls, 2);

        // A refresh that throws synchronously does not lock the resync.
        var syncCalls = 0;
        final throwing = LedgerSessionResync(() {
          syncCalls++;
          throw StateError('no session');
        });
        throwing();
        await pumpEventQueue();
        throwing();
        await pumpEventQueue();
        expect(syncCalls, 2);
      },
    );

    test('a role change refetches the role-dependent data', () async {
      final admin = NotifierProvider<_Flag, bool>(() => _Flag(true));
      final c = ProviderContainer(
        retry: (_, _) => null,
        overrides: ledgerOverrides(
          ledger: ledger,
          goals: goals,
          isAdminOverride: isAdminProvider.overrideWith(
            (ref) => ref.watch(admin),
          ),
        ),
      );
      addTearDown(c.dispose);
      const query = LedgerEntryQuery(month: '2026-09');
      final subs = [
        c.listen(ledgerSummaryProvider('2026-09'), (_, _) {}),
        c.listen(recentLedgerEntriesProvider('2026-09'), (_, _) {}),
        c.listen(ledgerEntriesProvider(query), (_, _) {}),
      ];
      addTearDown(() {
        for (final s in subs) {
          s.close();
        }
      });
      await c.read(ledgerSummaryProvider('2026-09').future);
      await c.read(recentLedgerEntriesProvider('2026-09').future);
      await c.read(ledgerEntriesProvider(query).future);
      final summaries = ledger.summaryCalls.length;
      final lists = ledger.listCalls.length;

      c.read(admin.notifier).set(false); // demoted on another phone
      await c.read(ledgerSummaryProvider('2026-09').future);
      await c.read(recentLedgerEntriesProvider('2026-09').future);
      await c.read(ledgerEntriesProvider(query).future);
      expect(ledger.summaryCalls.length, summaries + 1);
      expect(ledger.listCalls.length, lists + 2);
    });

    test('loadMore at the end of the list does nothing', () async {
      const query = LedgerEntryQuery(type: LedgerType.income);
      final sub = container.listen(ledgerEntriesProvider(query), (_, _) {});
      addTearDown(sub.close);
      final notifier = container.read(ledgerEntriesProvider(query).notifier);
      await container.read(ledgerEntriesProvider(query).future);
      await notifier.loadMore(); // 22 income entries → 20 + 2
      expect(
        container.read(ledgerEntriesProvider(query)).value!.hasMore,
        false,
      );
      final calls = ledger.listCalls.length;
      await notifier.loadMore();
      await notifier.loadMore();
      expect(ledger.listCalls.length, calls);
      expect(
        container.read(ledgerEntriesProvider(query)).value!.items,
        hasLength(22),
      );
    });
  });
}

class _Flag extends Notifier<bool> {
  _Flag(this._initial);

  final bool _initial;

  @override
  bool build() => _initial;

  void set(bool value) => state = value;
}
