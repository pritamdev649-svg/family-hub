import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/network/api_exception.dart';
import 'package:family_hub/core/utils/date_x.dart';
import 'package:family_hub/features/ledger/application/ledger_providers.dart';
import 'package:family_hub/features/ledger/domain/ledger_entry.dart';
import 'package:family_hub/features/ledger/domain/ledger_summary.dart';
import 'package:family_hub/features/ledger/domain/savings_goal.dart';
import 'package:family_hub/features/ledger/presentation/screens/entry_form_screen.dart';
import 'package:family_hub/features/ledger/presentation/screens/money_screen.dart';
import 'package:family_hub/features/ledger/presentation/widgets/goal_progress_card.dart';
import 'package:family_hub/features/ledger/presentation/widgets/ledger_entry_tile.dart';
import 'package:family_hub/features/ledger/presentation/widgets/money_header.dart';
import 'package:family_hub/l10n/app_localizations.dart';
import 'package:family_hub/shared/models/member.dart';

import '../ledger_test_utils.dart';

LedgerSummary _summary({SummaryScope scope = SummaryScope.family}) =>
    LedgerSummary(
      month: currentLedgerMonth().monthKey,
      currency: 'INR',
      scope: scope,
      income: 205000,
      expense: 58830,
      net: 146170,
      byCategory: const [
        CategoryTotal(
          type: LedgerType.expense,
          category: LedgerCategory.rent,
          amount: 28000,
        ),
        CategoryTotal(
          type: LedgerType.expense,
          category: LedgerCategory.householdHelp,
          amount: 11000,
        ),
        CategoryTotal(
          type: LedgerType.expense,
          category: LedgerCategory.groceries,
          amount: 6940,
        ),
        CategoryTotal(
          type: LedgerType.income,
          category: LedgerCategory.salary,
          amount: 205000,
        ),
      ],
    );

/// The header's "next month" arrow.
IconButton _nextMonthButton(WidgetTester tester) => tester.widget<IconButton>(
  find.ancestor(
    of: find.byTooltip('Next month'),
    matching: find.byType(IconButton),
  ),
);

void main() {
  late FakeLedgerRepository ledger;
  late FakeGoalRepository goals;

  setUp(() {
    ledger = FakeLedgerRepository(
      entries: [
        for (var i = 0; i < 12; i++)
          testEntry(id: 'e$i', note: 'Entry $i', amount: 100.0 + i),
      ],
      summaryResult: _summary(),
    );
    goals = FakeGoalRepository(
      goals: [
        testGoal(),
        testGoal(id: 'g2', title: 'Old fund', status: GoalStatus.archived),
      ],
    );
  });

  testWidgets('admin: summary, breakdown, goals, recent entries, caption', (
    tester,
  ) async {
    useTallSurface(tester);
    await pumpLedgerApp(
      tester,
      const MoneyScreen(),
      overrides: ledgerOverrides(ledger: ledger, goals: goals),
    );
    await tester.pumpAndSettle();
    final fmt = ledgerTestFmt();

    // Month switcher on the current month; "next" is disabled.
    expect(find.text(fmt.monthYear(currentLedgerMonth())), findsOneWidget);
    expect(_nextMonthButton(tester).onPressed, isNull);

    // The gradient header summarises the month: scope, balance, income /
    // expenses and the spent-vs-income line.
    expect(find.byType(MoneyHeader), findsOneWidget);
    expect(find.text('Family'), findsOneWidget);
    expect(find.text(fmt.money(146170)), findsOneWidget);
    expect(find.text(fmt.money(205000)), findsWidgets);
    expect(find.text(fmt.money(58830)), findsWidgets);
    expect(
      find.text('${fmt.percent(58830 / 205000)} of income spent'),
      findsOneWidget,
    );
    expect(find.text('On track'), findsOneWidget);

    // Category bars: expenses by default.
    expect(find.text('By category'), findsOneWidget);
    expect(find.text('Rent'), findsOneWidget);
    expect(find.text('Household help'), findsOneWidget);

    // Goals: active shown, archived hidden behind a toggle; admin can add.
    expect(find.byType(GoalProgressCard), findsOneWidget);
    expect(find.text('Goa vacation'), findsOneWidget);
    expect(find.text('Old fund'), findsNothing);
    expect(find.text('New goal'), findsOneWidget);
    await tester.tap(find.text('Show 1 archived goal'));
    await tester.pumpAndSettle();
    expect(find.text('Old fund'), findsOneWidget);

    // Recent entries: at most 10.
    expect(find.byType(LedgerEntryTile), findsNWidgets(recentEntriesCount));
    expect(find.text('Entry 0'), findsOneWidget);
    expect(find.text('See all'), findsOneWidget);

    // Compliance caption and the add button.
    expect(find.text('Records only – no real money is moved.'), findsOneWidget);
    expect(find.text('Add entry'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow phone, largest text and RTL do not overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320 * 3, 2400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: ledgerOverrides(ledger: ledger, goals: goals),
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.6)),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: child!,
            ),
          ),
          home: const MoneyScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(MoneyHeader), findsOneWidget);
    expect(find.text('Goa vacation'), findsOneWidget);
  });

  testWidgets('member: personal scope, no goal creation', (tester) async {
    useTallSurface(tester);
    ledger.summaryResult = _summary(scope: SummaryScope.personal);
    goals.goals.clear();
    final me = testMember(
      id: 'm-aarav',
      name: 'Aarav',
      role: MemberRole.member,
    );
    await pumpLedgerApp(
      tester,
      const MoneyScreen(),
      overrides: ledgerOverrides(ledger: ledger, goals: goals, me: me),
    );
    await tester.pumpAndSettle();

    expect(find.text('Personal'), findsOneWidget);
    expect(find.text('New goal'), findsNothing);
    expect(find.text('No savings goals yet'), findsOneWidget);
    expect(
      find.text(
        'Your family admins can create goals that everyone contributes to.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('switching month loads that month', (tester) async {
    useTallSurface(tester);
    await pumpLedgerApp(
      tester,
      const MoneyScreen(),
      overrides: ledgerOverrides(ledger: ledger, goals: goals),
    );
    await tester.pumpAndSettle();
    final previous = currentLedgerMonth().addMonths(-1);

    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();

    expect(ledger.summaryCalls.last, previous.monthKey);
    expect(ledger.listCalls.last.query.month, previous.monthKey);
    expect(find.text(ledgerTestFmt().monthYear(previous)), findsOneWidget);
    expect(_nextMonthButton(tester).onPressed, isNotNull);
  });

  testWidgets('month picker jumps to a chosen month', (tester) async {
    useTallSurface(tester);
    await pumpLedgerApp(
      tester,
      const MoneyScreen(),
      overrides: ledgerOverrides(ledger: ledger, goals: goals),
    );
    await tester.pumpAndSettle();
    final fmt = ledgerTestFmt();
    final target = currentLedgerMonth().addMonths(-3);

    await tester.tap(find.text(fmt.monthYear(currentLedgerMonth())));
    await tester.pumpAndSettle();
    expect(find.text('Choose a month'), findsOneWidget);
    await tester.tap(find.text(fmt.monthYear(target)));
    await tester.pumpAndSettle();

    expect(ledger.summaryCalls.last, target.monthKey);
  });

  testWidgets('summary error shows retry and recovers', (tester) async {
    useTallSurface(tester);
    final failing = _FailingSummaryRepository(entries: ledger.entries);
    await pumpLedgerApp(
      tester,
      const MoneyScreen(),
      overrides: ledgerOverrides(ledger: failing, goals: goals),
    );
    await tester.pumpAndSettle();

    expect(find.text('Something went wrong'), findsOneWidget);
    // The other sections still render.
    expect(find.text('Goa vacation'), findsOneWidget);

    failing.fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('By category'), findsOneWidget);
    expect(find.text(ledgerTestFmt().money(146170)), findsOneWidget);
  });

  testWidgets('Add entry → Add expense opens the expense form', (tester) async {
    useTallSurface(tester);
    await pumpLedgerRouter(
      tester,
      overrides: ledgerOverrides(ledger: ledger, goals: goals),
    );

    await tester.tap(find.text('Add entry'));
    await tester.pumpAndSettle();
    expect(find.text('What would you like to record?'), findsOneWidget);
    await tester.tap(find.text('Add expense'));
    await tester.pumpAndSettle();

    final form = tester.widget<EntryFormScreen>(find.byType(EntryFormScreen));
    expect(form.initialType, LedgerType.expense);
    expect(form.entry, isNull);
    expect(find.text('New entry'), findsOneWidget);
  });

  testWidgets('tapping an entry shows details; creator can delete', (
    tester,
  ) async {
    useTallSurface(tester);
    await pumpLedgerRouter(
      tester,
      overrides: ledgerOverrides(ledger: ledger, goals: goals),
    );

    await tester.tap(find.text('Entry 0'));
    await tester.pumpAndSettle();
    expect(find.text('Entry details'), findsOneWidget);
    expect(find.text('Groceries'), findsWidgets);

    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this entry?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete').last);
    await tester.pumpAndSettle();

    expect(ledger.deleted, ['e0']);
    expect(find.text('Entry details'), findsNothing);
    expect(find.text('Entry deleted'), findsOneWidget);
  });
}

class _FailingSummaryRepository extends FakeLedgerRepository {
  _FailingSummaryRepository({super.entries});

  bool fail = true;

  @override
  Future<LedgerSummary> summary({String? month}) async {
    if (fail) {
      throw const ApiException(
        code: ApiErrorCode.internal,
        message: 'boom',
        statusCode: 500,
      );
    }
    return _summary();
  }
}
