import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/features/ledger/domain/ledger_entry.dart';
import 'package:family_hub/features/ledger/ledger_routes.dart';
import 'package:family_hub/features/ledger/presentation/screens/money_screen.dart';
import 'package:family_hub/l10n/app_localizations.dart';

import '../ledger_test_utils.dart';

/// Every ledger screen at 320 dp width, 1.6× text and right-to-left must
/// render without overflow errors.
void main() {
  late FakeLedgerRepository ledger;
  late FakeGoalRepository goals;

  setUp(() {
    ledger = FakeLedgerRepository(
      entries: [
        testEntry(
          id: 'c1',
          amount: 123456.78,
          category: LedgerCategory.householdHelp,
          goalId: 'g1',
          note: 'A fairly long note describing this household help payment',
        ),
        testEntry(
          id: 'e2',
          type: LedgerType.income,
          category: LedgerCategory.otherIncome,
        ),
      ],
    );
    goals = FakeGoalRepository(
      goals: [
        testGoal(
          title: 'A very long savings goal title for the family holiday',
          target: 987654321,
          saved: 12345678,
          targetDate: DateTime.now().add(const Duration(days: 400)),
        ),
      ],
    );
  });

  Future<GoRouter> pumpNarrow(
    WidgetTester tester,
    String location, {
    Object? extra,
  }) async {
    tester.view.physicalSize = const Size(320 * 3, 1600 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: AppRoutes.money,
      routes: [
        GoRoute(path: AppRoutes.money, builder: (_, _) => const MoneyScreen()),
        ...ledgerRoutes,
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: ledgerOverrides(ledger: ledger, goals: goals),
        child: MaterialApp.router(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.6)),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: child!,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (location != AppRoutes.money) {
      router.push(location, extra: extra);
      await tester.pumpAndSettle();
    }
    return router;
  }

  testWidgets('entries list', (tester) async {
    await pumpNarrow(tester, AppRoutes.ledgerEntries);
    expect(tester.takeException(), isNull);
  });

  testWidgets('entry form (new)', (tester) async {
    await pumpNarrow(tester, AppRoutes.ledgerEntryNew(type: 'expense'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('entry form editing a contribution', (tester) async {
    await pumpNarrow(
      tester,
      AppRoutes.ledgerEntryNew(type: 'expense'),
      extra: ledger.entries.first,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('goal detail, contribute sheet and entry sheet', (tester) async {
    await pumpNarrow(tester, AppRoutes.goalDetail('g1'));
    expect(tester.takeException(), isNull);

    final contribute = find.widgetWithText(FilledButton, 'Contribute');
    await tester.scrollUntilVisible(
      contribute,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(contribute);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tapAt(const Offset(10, 10)); // dismiss the sheet
    await tester.pumpAndSettle();

    final note = find.textContaining('A fairly long note');
    await tester.scrollUntilVisible(
      note,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(note);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('goal form', (tester) async {
    await pumpNarrow(tester, AppRoutes.goalEdit('g1'));
    expect(tester.takeException(), isNull);
  });
}
