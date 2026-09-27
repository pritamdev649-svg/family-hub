import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/utils/date_x.dart';
import 'package:family_hub/features/ledger/application/ledger_providers.dart';
import 'package:family_hub/features/ledger/domain/ledger_entry.dart';
import 'package:family_hub/features/ledger/domain/ledger_summary.dart';
import 'package:family_hub/features/ledger/domain/savings_goal.dart';
import 'package:family_hub/features/ledger/presentation/screens/entries_screen.dart';
import 'package:family_hub/features/ledger/presentation/screens/entry_form_screen.dart';
import 'package:family_hub/features/ledger/presentation/screens/goal_detail_screen.dart';
import 'package:family_hub/features/ledger/presentation/screens/goal_form_screen.dart';
import 'package:family_hub/features/ledger/presentation/widgets/contribute_sheet.dart';
import 'package:family_hub/features/ledger/presentation/widgets/category_grid.dart';
import 'package:family_hub/features/ledger/presentation/widgets/entry_detail_sheet.dart';
import 'package:family_hub/shared/models/member.dart';
import 'package:family_hub/shared/providers/shared_providers.dart';

import '../ledger_test_utils.dart';

/// Edge cases of the Money feature: records deleted / archived by someone
/// else, permission and membership changes while a screen is open, server
/// validation the form could not know about, rapid repeated taps.
void main() {
  late FakeLedgerRepository ledger;
  late FakeGoalRepository goals;

  final amit = testMember();
  final kamla = testMember(
    id: 'm-kamla',
    name: 'Kamla',
    role: MemberRole.member,
  );

  setUp(() {
    ledger = FakeLedgerRepository(
      entries: [
        testEntry(id: 'e1', note: 'Vegetables'),
        testEntry(
          id: 'c1',
          amount: 7500,
          category: LedgerCategory.savings,
          goalId: 'g1',
          note: 'First saving',
        ),
      ],
      summaryResult: LedgerSummary(
        month: currentLedgerMonth().monthKey,
        currency: 'INR',
        scope: SummaryScope.family,
        income: 1000,
        expense: 0,
        net: 1000,
        byCategory: const [
          CategoryTotal(
            type: LedgerType.income,
            category: LedgerCategory.salary,
            amount: 1000,
          ),
        ],
      ),
    );
    goals = FakeGoalRepository(goals: [testGoal()]);
  });

  Finder field(String label) => find.widgetWithText(TextField, label);

  ProviderContainer containerOf(WidgetTester tester, Type screen) =>
      ProviderScope.containerOf(tester.element(find.byType(screen)));

  group('records changed by someone else', () {
    testWidgets('deleting an entry that is already gone closes the sheet', (
      tester,
    ) async {
      useTallSurface(tester);
      await pumpLedgerRouter(
        tester,
        overrides: ledgerOverrides(ledger: ledger, goals: goals),
      );
      final listsBefore = ledger.listCalls.length;

      await tester.tap(find.text('Vegetables'));
      await tester.pumpAndSettle();
      ledger.failNextWrite = notFoundError;
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete').last);
      await tester.pumpAndSettle();

      expect(find.byType(LedgerEntrySheet), findsNothing);
      expect(find.text('This entry was already deleted.'), findsOneWidget);
      // The lists were refreshed to the server's state.
      expect(ledger.listCalls.length, greaterThan(listsBefore));
    });

    testWidgets('saving an edited entry that was deleted closes the form', (
      tester,
    ) async {
      useTallSurface(tester);
      final router = await pumpLedgerRouter(
        tester,
        overrides: ledgerOverrides(ledger: ledger, goals: goals),
      );
      router.push(
        AppRoutes.ledgerEntryNew(type: 'expense'),
        extra: ledger.entries.first,
      );
      await tester.pumpAndSettle();
      await tester.enterText(field('Note (optional)'), 'Fruit too');
      ledger.failNextWrite = notFoundError;
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.byType(EntryFormScreen), findsNothing);
      expect(
        find.text('This entry no longer exists – someone may have deleted it.'),
        findsOneWidget,
      );
    });

    testWidgets('contributing to a goal that was deleted', (tester) async {
      useTallSurface(tester);
      final router = await pumpLedgerRouter(
        tester,
        overrides: ledgerOverrides(ledger: ledger, goals: goals),
      );
      router.push(AppRoutes.goalDetail('g1'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Contribute'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Amount (₹)'), '500');
      // Server state: another admin deleted the goal.
      goals.goals.clear();
      goals.failNextWrite = notFoundError;
      await tester.tap(find.widgetWithText(FilledButton, 'Contribute').last);
      await tester.pumpAndSettle();

      expect(
        find.text('This goal no longer exists – an admin may have deleted it.'),
        findsOneWidget,
      );
      // Behind the sheet the detail already switched to "not found".
      Navigator.of(tester.element(find.byType(ContributeSheet))).pop();
      await tester.pumpAndSettle();
      expect(find.text('Goal not found'), findsOneWidget);
    });

    testWidgets('contributing to a goal archived meanwhile (409)', (
      tester,
    ) async {
      useTallSurface(tester);
      final router = await pumpLedgerRouter(
        tester,
        overrides: ledgerOverrides(ledger: ledger, goals: goals),
      );
      router.push(AppRoutes.goalDetail('g1'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Contribute'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Amount (₹)'), '500');
      goals.goals[0] = goals.goals[0].copyWith(status: GoalStatus.archived);
      goals.failNextWrite = validationError(['goalId'], status: 409);
      await tester.tap(find.widgetWithText(FilledButton, 'Contribute').last);
      await tester.pumpAndSettle();

      expect(
        find.text("This goal is archived, so it can't take contributions."),
        findsOneWidget,
      );
      Navigator.of(tester.element(find.byType(ContributeSheet))).pop();
      await tester.pumpAndSettle();
      // Refreshed: the detail now knows the goal is archived.
      expect(
        find.text("This goal is archived and doesn't take contributions."),
        findsOneWidget,
      );
    });

    testWidgets('archiving a goal another admin deleted shows "not found"', (
      tester,
    ) async {
      useTallSurface(tester);
      final router = await pumpLedgerRouter(
        tester,
        overrides: ledgerOverrides(ledger: ledger, goals: goals),
      );
      router.push(AppRoutes.goalDetail('g1'));
      await tester.pumpAndSettle();

      goals.goals.clear();
      goals.failNextWrite = notFoundError;
      await tester.tap(find.byTooltip('Goal actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archive'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Archive'));
      await tester.pumpAndSettle();

      expect(
        find.text('This goal no longer exists – an admin may have deleted it.'),
        findsOneWidget,
      );
      expect(find.text('Goal not found'), findsOneWidget);
      expect(find.byTooltip('Goal actions'), findsNothing);
    });

    testWidgets('deleting a goal that is already gone leaves the screen', (
      tester,
    ) async {
      useTallSurface(tester);
      final router = await pumpLedgerRouter(
        tester,
        overrides: ledgerOverrides(ledger: ledger, goals: goals),
      );
      router.push(AppRoutes.goalDetail('g1'));
      await tester.pumpAndSettle();

      goals.failNextWrite = notFoundError;
      await tester.tap(find.byTooltip('Goal actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete goal'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.byType(GoalDetailScreen), findsNothing);
      expect(find.text('This goal was already deleted.'), findsOneWidget);
    });

    testWidgets('saving a goal edit after it was deleted closes the form', (
      tester,
    ) async {
      useTallSurface(tester);
      final router = await pumpLedgerRouter(
        tester,
        overrides: ledgerOverrides(ledger: ledger, goals: goals),
      );
      router.push(AppRoutes.goalEdit('g1'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Goal name'), 'Goa trip');
      goals.failNextWrite = notFoundError;
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.byType(GoalFormScreen), findsNothing);
      expect(
        find.text('This goal no longer exists – an admin may have deleted it.'),
        findsOneWidget,
      );
    });

    testWidgets('editing a goal that no longer exists', (tester) async {
      useTallSurface(tester);
      final router = await pumpLedgerRouter(
        tester,
        overrides: ledgerOverrides(ledger: ledger, goals: goals),
      );
      router.push(AppRoutes.goalEdit('missing'));
      await tester.pumpAndSettle();
      expect(find.text('Goal not found'), findsOneWidget);
      expect(find.text('Save'), findsNothing);
    });
  });

  group('server validation and failures', () {
    Future<void> fillExpense(WidgetTester tester) async {
      await tester.enterText(heroAmountInput(), '250');
      await tester.tap(find.widgetWithText(LedgerCategoryTile, 'Groceries'));
      await tester.pumpAndSettle();
    }

    testWidgets('chosen member left the family (422 memberId)', (tester) async {
      useTallSurface(tester);
      final router = await pumpLedgerRouter(
        tester,
        overrides: ledgerOverrides(
          ledger: ledger,
          goals: goals,
          members: [amit, kamla],
        ),
      );
      router.push(AppRoutes.ledgerEntryNew(type: 'expense'));
      await tester.pumpAndSettle();
      await fillExpense(tester);
      final before = containerOf(
        tester,
        EntryFormScreen,
      ).read(dataRefreshProvider)[DataScope.members]!;

      ledger.failNextWrite = validationError(['memberId']);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'That person is no longer in the family. Choose someone else.',
        ),
        findsOneWidget,
      );
      // Still on the form, ready to try again; the members list refreshed.
      expect(find.byType(EntryFormScreen), findsOneWidget);
      expect(
        containerOf(
          tester,
          EntryFormScreen,
        ).read(dataRefreshProvider)[DataScope.members],
        before + 1,
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(ledger.created, hasLength(1));
    });

    testWidgets('date outside the family time zone window (422 date)', (
      tester,
    ) async {
      useTallSurface(tester);
      final router = await pumpLedgerRouter(
        tester,
        overrides: ledgerOverrides(ledger: ledger, goals: goals),
      );
      router.push(AppRoutes.ledgerEntryNew(type: 'expense'));
      await tester.pumpAndSettle();
      await fillExpense(tester);
      ledger.failNextWrite = validationError(['date']);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining("too far ahead for your family's time zone"),
        findsOneWidget,
      );
    });

    testWidgets('a timed-out save says to check before retrying', (
      tester,
    ) async {
      useTallSurface(tester);
      final router = await pumpLedgerRouter(
        tester,
        overrides: ledgerOverrides(ledger: ledger, goals: goals),
      );
      router.push(AppRoutes.ledgerEntryNew(type: 'expense'));
      await tester.pumpAndSettle();
      await fillExpense(tester);
      ledger.failNextWrite = timeoutError;
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('it may already be saved'), findsOneWidget);
      expect(find.byType(EntryFormScreen), findsOneWidget);
    });
  });

  group('permissions and membership changes', () {
    testWidgets('403 on delete explains and resyncs the session', (
      tester,
    ) async {
      useTallSurface(tester);
      final recorder = ResyncRecorder();
      await pumpLedgerRouter(
        tester,
        overrides: ledgerOverrides(
          ledger: ledger,
          goals: goals,
          resync: recorder,
        ),
      );
      await tester.tap(find.text('Vegetables'));
      await tester.pumpAndSettle();
      ledger.failNextWrite = forbiddenError;
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete').last);
      await tester.pumpAndSettle();

      expect(find.byType(LedgerEntrySheet), findsOneWidget);
      expect(
        find.text(
          "You can't do this any more. Your role in the family may have changed.",
        ),
        findsOneWidget,
      );
      expect(recorder.calls, 1);
    });

    testWidgets('demoted while the form is open: records for self', (
      tester,
    ) async {
      useTallSurface(tester);
      final admin = NotifierProvider<_Flag, bool>(() => _Flag(true));
      final router = await pumpLedgerRouter(
        tester,
        overrides: ledgerOverrides(
          ledger: ledger,
          goals: goals,
          members: [amit, kamla],
          isAdminOverride: isAdminProvider.overrideWith(
            (ref) => ref.watch(admin),
          ),
        ),
      );
      router.push(AppRoutes.ledgerEntryNew(type: 'expense'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Amit (you)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kamla').last);
      await tester.pumpAndSettle();

      containerOf(tester, EntryFormScreen).read(admin.notifier).set(false);
      await tester.pumpAndSettle();
      // The locked field shows who the entry will really be for.
      expect(find.text('Amit (you)'), findsOneWidget);
      expect(
        find.text('Members record entries for themselves.'),
        findsOneWidget,
      );

      await tester.enterText(heroAmountInput(), '250');
      await tester.tap(find.widgetWithText(LedgerCategoryTile, 'Groceries'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(ledger.created.single.memberId, isNull);
    });

    testWidgets('editing an entry of someone who left the family', (
      tester,
    ) async {
      useTallSurface(tester);
      final router = await pumpLedgerRouter(
        tester,
        overrides: ledgerOverrides(ledger: ledger, goals: goals),
      );
      router.push(
        AppRoutes.ledgerEntryNew(type: 'expense'),
        extra: testEntry(
          id: 'old',
          memberId: 'm-gone',
          memberName: 'Kamla',
          createdById: 'm-amit',
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Recorded for Kamla, who is no longer in the family.'),
        findsOneWidget,
      );
      await tester.enterText(field('Note (optional)'), 'Medicines');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      // The owner is kept (not moved to the admin).
      expect(ledger.updated.single.$2.toJson(), {'note': 'Medicines'});
    });

    testWidgets('entry details name a creator who left "Former member"', (
      tester,
    ) async {
      useTallSurface(tester);
      ledger.entries.insert(
        0,
        testEntry(id: 'x', note: 'Old bill', createdById: 'm-gone'),
      );
      await pumpLedgerRouter(
        tester,
        overrides: ledgerOverrides(ledger: ledger, goals: goals),
      );
      await tester.tap(find.text('Old bill'));
      await tester.pumpAndSettle();
      expect(find.text('Added by'), findsOneWidget);
      expect(find.text('Former member'), findsOneWidget);
    });

    testWidgets('member filter survives the member leaving the family', (
      tester,
    ) async {
      useTallSurface(tester);
      var members = [amit, kamla];
      ledger.entries.add(
        testEntry(id: 'k1', note: 'Medicines', memberId: 'm-kamla'),
      );
      final router = await pumpLedgerRouter(
        tester,
        overrides: ledgerOverrides(
          ledger: ledger,
          goals: goals,
          membersOverride: membersProvider.overrideWith((ref) async => members),
        ),
      );
      router.push(AppRoutes.ledgerEntries);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Everyone'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kamla').last);
      await tester.pumpAndSettle();
      expect(find.text('Medicines'), findsOneWidget);

      members = [amit];
      containerOf(tester, EntriesScreen).invalidate(membersProvider);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Former member'), findsOneWidget);
      expect(find.text('Medicines'), findsOneWidget);
    });
  });

  group('rapid repeated taps', () {
    testWidgets('a double tap on an entry opens one sheet', (tester) async {
      useTallSurface(tester);
      await pumpLedgerRouter(
        tester,
        overrides: ledgerOverrides(ledger: ledger, goals: goals),
      );
      await tester.tap(find.text('Vegetables'));
      await tester.tap(find.text('Vegetables'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(
        find.byType(LedgerEntrySheet, skipOffstage: false),
        findsOneWidget,
      );

      // Closing it re-enables the list.
      Navigator.of(tester.element(find.byType(LedgerEntrySheet))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vegetables'));
      await tester.pumpAndSettle();
      expect(find.byType(LedgerEntrySheet), findsOneWidget);
    });

    testWidgets('a double tap on Contribute opens one sheet', (tester) async {
      useTallSurface(tester);
      final router = await pumpLedgerRouter(
        tester,
        overrides: ledgerOverrides(ledger: ledger, goals: goals),
      );
      router.push(AppRoutes.goalDetail('g1'));
      await tester.pumpAndSettle();
      final button = find.widgetWithText(FilledButton, 'Contribute');
      await tester.tap(button);
      await tester.tap(button, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(ContributeSheet, skipOffstage: false), findsOneWidget);
    });

    testWidgets('a double tap on a goal card opens one detail screen', (
      tester,
    ) async {
      useTallSurface(tester);
      await pumpLedgerRouter(
        tester,
        overrides: ledgerOverrides(ledger: ledger, goals: goals),
      );
      await tester.tap(find.text('Goa vacation'));
      await tester.tap(find.text('Goa vacation'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(
        find.byType(GoalDetailScreen, skipOffstage: false),
        findsOneWidget,
      );
    });
  });

  testWidgets('a month with income only shows the income bars', (tester) async {
    useTallSurface(tester);
    await pumpLedgerRouter(
      tester,
      overrides: ledgerOverrides(ledger: ledger, goals: goals),
    );
    expect(find.text('No expenses recorded this month.'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('^Salary: ')), findsOneWidget);
  });
}

class _Flag extends Notifier<bool> {
  _Flag(this._initial);

  final bool _initial;

  @override
  bool build() => _initial;

  void set(bool value) => state = value;
}
