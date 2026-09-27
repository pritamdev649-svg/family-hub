import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/utils/date_x.dart';
import 'package:family_hub/features/ledger/domain/ledger_entry.dart';
import 'package:family_hub/features/ledger/presentation/screens/entry_form_screen.dart';
import 'package:family_hub/features/ledger/presentation/screens/money_screen.dart';
import 'package:family_hub/features/ledger/presentation/widgets/category_grid.dart';
import 'package:family_hub/features/ledger/presentation/widgets/type_toggle.dart';
import 'package:family_hub/shared/models/member.dart';

import '../ledger_test_utils.dart';

Finder _field(String label) => find.widgetWithText(TextField, label);

void main() {
  late FakeLedgerRepository ledger;
  late FakeGoalRepository goals;

  setUp(() {
    ledger = FakeLedgerRepository();
    goals = FakeGoalRepository();
  });

  testWidgets('validates, then records an expense and returns', (tester) async {
    useTallSurface(tester);
    final router = await pumpLedgerRouter(
      tester,
      overrides: ledgerOverrides(
        ledger: ledger,
        goals: goals,
        members: [
          testMember(),
          testMember(id: 'm-kamla', name: 'Kamla', role: MemberRole.member),
        ],
      ),
    );
    router.push(AppRoutes.ledgerEntryNew(type: 'expense'));
    await tester.pumpAndSettle();

    // Savings is not offered for manual entries; income categories hidden.
    expect(
      find.widgetWithText(LedgerCategoryTile, 'Groceries'),
      findsOneWidget,
    );
    expect(find.widgetWithText(LedgerCategoryTile, 'Savings'), findsNothing);
    expect(find.widgetWithText(LedgerCategoryTile, 'Salary'), findsNothing);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('This field is required'), findsWidgets);
    expect(find.text('Choose a category'), findsOneWidget);
    expect(ledger.created, isEmpty);

    // The caption names the currency.
    expect(find.text('Amount (₹)'), findsOneWidget);

    // Max two decimals are enforced while typing.
    await tester.enterText(heroAmountInput(), '1250.505');
    expect(find.text('1250.505'), findsNothing);
    await tester.enterText(heroAmountInput(), '1,250.50');
    await tester.tap(find.widgetWithText(LedgerCategoryTile, 'Groceries'));
    await tester.enterText(_field('Note (optional)'), '  Weekly veggies ');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final input = ledger.created.single;
    expect(input.type, LedgerType.expense);
    expect(input.amount, 1250.5);
    expect(input.category, LedgerCategory.groceries);
    expect(input.date, DateTime.now().startOfDay);
    expect(input.toJson()['note'], 'Weekly veggies');
    // Admin: the selected member (default: self) is sent.
    expect(input.memberId, 'm-amit');

    // Popped back to the Money tab with a confirmation.
    expect(find.byType(EntryFormScreen), findsNothing);
    expect(find.byType(MoneyScreen), findsOneWidget);
    expect(find.text('Entry added'), findsOneWidget);
  });

  testWidgets('switching type resets an incompatible category', (tester) async {
    useTallSurface(tester);
    await pumpLedgerApp(
      tester,
      const EntryFormScreen(initialType: LedgerType.expense),
      overrides: ledgerOverrides(ledger: ledger, goals: goals),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(LedgerCategoryTile, 'Rent'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(LedgerTypeToggle),
        matching: find.text('Income'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(LedgerCategoryTile, 'Salary'), findsOneWidget);
    expect(find.widgetWithText(LedgerCategoryTile, 'Rent'), findsNothing);
    final tiles = tester.widgetList<LedgerCategoryTile>(
      find.byType(LedgerCategoryTile),
    );
    expect(tiles, isNotEmpty);
    expect(tiles.every((t) => !t.selected), isTrue);
  });

  testWidgets('members record for themselves (member field locked)', (
    tester,
  ) async {
    useTallSurface(tester);
    final me = testMember(
      id: 'm-aarav',
      name: 'Aarav',
      role: MemberRole.member,
    );
    final router = await pumpLedgerRouter(
      tester,
      overrides: ledgerOverrides(ledger: ledger, goals: goals, me: me),
    );
    router.push(AppRoutes.ledgerEntryNew(type: 'income'));
    await tester.pumpAndSettle();

    expect(find.text('Aarav (you)'), findsOneWidget);
    expect(find.text('Members record entries for themselves.'), findsOneWidget);

    await tester.enterText(heroAmountInput(), '500');
    await tester.tap(find.widgetWithText(LedgerCategoryTile, 'Allowance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final input = ledger.created.single;
    expect(input.type, LedgerType.income);
    expect(input.memberId, isNull);
    expect(input.toJson().containsKey('memberId'), isFalse);
  });

  testWidgets('editing a goal contribution locks amount, type and category', (
    tester,
  ) async {
    useTallSurface(tester);
    final entry = testEntry(
      id: 'c1',
      amount: 5000,
      category: LedgerCategory.savings,
      goalId: 'g1',
      note: 'Goa trip',
    );
    ledger.entries.add(entry);
    final router = await pumpLedgerRouter(
      tester,
      overrides: ledgerOverrides(ledger: ledger, goals: goals),
    );
    router.push(AppRoutes.ledgerEntryNew(type: 'expense'), extra: entry);
    await tester.pumpAndSettle();

    expect(find.text('Edit entry'), findsOneWidget);
    expect(find.textContaining('goal contribution'), findsOneWidget);
    final amount = tester.widget<TextField>(heroAmountInput());
    expect(amount.enabled, isFalse);
    expect(amount.controller!.text, '5000');
    expect(find.widgetWithText(LedgerCategoryTile, 'Savings'), findsOneWidget);

    await tester.enterText(_field('Note (optional)'), 'Goa trip – Priya');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final (id, patch) = ledger.updated.single;
    expect(id, 'c1');
    expect(patch.toJson(), {'note': 'Goa trip – Priya'});
    expect(find.text('Entry updated'), findsOneWidget);
  });

  testWidgets('unsaved changes ask before leaving', (tester) async {
    useTallSurface(tester);
    final router = await pumpLedgerRouter(
      tester,
      overrides: ledgerOverrides(ledger: ledger, goals: goals),
    );
    router.push(AppRoutes.ledgerEntryNew(type: 'expense'));
    await tester.pumpAndSettle();
    await tester.enterText(heroAmountInput(), '10');
    await tester.pumpAndSettle();

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.byType(EntryFormScreen), findsNothing);
    expect(ledger.created, isEmpty);
  });
}
