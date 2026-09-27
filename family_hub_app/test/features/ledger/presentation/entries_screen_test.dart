import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/utils/date_x.dart';
import 'package:family_hub/features/ledger/application/ledger_providers.dart';
import 'package:family_hub/features/ledger/domain/ledger_entry.dart';
import 'package:family_hub/features/ledger/presentation/widgets/ledger_entry_tile.dart';
import 'package:family_hub/shared/models/member.dart';

import '../ledger_test_utils.dart';

void main() {
  late FakeLedgerRepository ledger;
  late FakeGoalRepository goals;

  setUp(() {
    ledger = FakeLedgerRepository(
      entries: [
        for (var i = 0; i < 25; i++)
          testEntry(
            id: 'e$i',
            note: 'Entry $i',
            type: i < 5 ? LedgerType.income : LedgerType.expense,
            category: i < 5 ? LedgerCategory.salary : LedgerCategory.groceries,
            memberId: i.isEven ? 'm-amit' : 'm-kamla',
            memberName: i.isEven ? 'Amit' : 'Kamla',
          ),
      ],
    );
    goals = FakeGoalRepository();
  });

  final members = [
    testMember(),
    testMember(id: 'm-kamla', name: 'Kamla', role: MemberRole.member),
  ];

  testWidgets('starts on the Money tab month, filters by type and member', (
    tester,
  ) async {
    useTallSurface(tester);
    final router = await pumpLedgerRouter(
      tester,
      overrides: ledgerOverrides(
        ledger: ledger,
        goals: goals,
        members: members,
      ),
    );
    router.push(AppRoutes.ledgerEntries);
    await tester.pumpAndSettle();

    final month = currentLedgerMonth().monthKey;
    expect(ledger.listCalls.last.query.month, month);
    expect(find.text('All entries'), findsOneWidget);
    expect(find.byType(LedgerEntryTile), findsNWidgets(20));
    expect(find.text('Load more'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Income'));
    await tester.pumpAndSettle();
    expect(ledger.listCalls.last.query.type, LedgerType.income);
    expect(find.byType(LedgerEntryTile), findsNWidgets(5));

    // Member filter (admins only).
    await tester.tap(find.text('Everyone'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kamla').last);
    await tester.pumpAndSettle();
    expect(ledger.listCalls.last.query.memberId, 'm-kamla');
    expect(ledger.listCalls.last.query.type, LedgerType.income);
  });

  testWidgets('load more appends the next page', (tester) async {
    // Tall enough that the whole first page (20 rows) and the "Load more"
    // button fit without scrolling (scrolling to the end loads the next
    // page by itself).
    tester.view.physicalSize = const Size(1080, 6400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final router = await pumpLedgerRouter(
      tester,
      overrides: ledgerOverrides(
        ledger: ledger,
        goals: goals,
        members: members,
      ),
    );
    router.push(AppRoutes.ledgerEntries);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(ledger.listCalls.last.page, 2);

    final list = find.descendant(
      of: find.byType(ListView),
      matching: find.byType(Scrollable),
    );

    await tester.scrollUntilVisible(
      find.text('Entry 24'),
      400,
      scrollable: list.first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Entry 24'), findsOneWidget);
    expect(find.text('Load more'), findsNothing);
  });

  testWidgets('empty result offers to clear the filters', (tester) async {
    useTallSurface(tester);
    ledger.entries.clear();
    final router = await pumpLedgerRouter(
      tester,
      overrides: ledgerOverrides(
        ledger: ledger,
        goals: goals,
        members: members,
      ),
    );
    router.push(AppRoutes.ledgerEntries);
    await tester.pumpAndSettle();

    expect(find.text('No entries found'), findsOneWidget);
    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(ledger.listCalls.last.query.hasFilters, isFalse);
    expect(find.text('All months'), findsOneWidget);
    expect(find.text('Entries you record will show up here.'), findsOneWidget);
  });

  testWidgets('members get no member filter and a visibility note', (
    tester,
  ) async {
    useTallSurface(tester);
    final me = testMember(
      id: 'm-kamla',
      name: 'Kamla',
      role: MemberRole.member,
    );
    final router = await pumpLedgerRouter(
      tester,
      overrides: ledgerOverrides(
        ledger: ledger,
        goals: goals,
        me: me,
        members: members,
      ),
    );
    router.push(AppRoutes.ledgerEntries);
    await tester.pumpAndSettle();

    expect(find.text('Everyone'), findsNothing);
    expect(
      find.text('You see the entries that are yours or that you added.'),
      findsOneWidget,
    );
  });
}
