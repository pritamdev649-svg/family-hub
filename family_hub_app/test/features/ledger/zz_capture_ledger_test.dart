// TEMPORARY visual capture for the rd-ledger redesign review (deleted after
// review). Not part of the suite.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/utils/date_x.dart';
import 'package:family_hub/features/ledger/application/ledger_providers.dart';
import 'package:family_hub/features/ledger/domain/ledger_entry.dart';
import 'package:family_hub/features/ledger/domain/ledger_summary.dart';
import 'package:family_hub/features/ledger/domain/savings_goal.dart';
import 'package:family_hub/features/ledger/ledger_routes.dart';
import 'package:family_hub/features/ledger/presentation/screens/money_screen.dart';
import 'package:family_hub/features/ledger/presentation/widgets/goal_progress_card.dart';
import 'package:family_hub/features/ledger/presentation/widgets/month_summary_card.dart';
import 'package:family_hub/l10n/app_localizations.dart';

import 'ledger_test_utils.dart';

const _out = String.fromEnvironment('OUT', defaultValue: '/tmp');

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final p in paths) {
      final bytes = File(p).readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }

  const sdk =
      '/Users/rajesh/development/flutter/bin/cache/artifacts/material_fonts';
  await load('Roboto', [
    '$sdk/Roboto-Regular.ttf',
    '$sdk/Roboto-Medium.ttf',
    '$sdk/Roboto-Bold.ttf',
    '$sdk/Roboto-Black.ttf',
  ]);
  await load('packages/phosphor_flutter/PhosphorLight', [
    '/Users/rajesh/.pub-cache/hosted/pub.dev/phosphor_flutter-2.1.0/lib/fonts/Phosphor-Light.ttf',
  ]);
}

LedgerSummary _summary({double expense = 58830}) => LedgerSummary(
  month: currentLedgerMonth().monthKey,
  currency: 'INR',
  scope: SummaryScope.family,
  income: 205000,
  expense: expense,
  net: 205000 - expense,
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
      type: LedgerType.expense,
      category: LedgerCategory.utilities,
      amount: 4200,
    ),
    CategoryTotal(
      type: LedgerType.income,
      category: LedgerCategory.salary,
      amount: 205000,
    ),
  ],
);

FakeLedgerRepository _ledger() => FakeLedgerRepository(
  summaryResult: _summary(),
  entries: [
    testEntry(id: 'e1', note: 'Weekly vegetables', amount: 1250.5),
    testEntry(
      id: 'e2',
      type: LedgerType.income,
      category: LedgerCategory.salary,
      amount: 205000,
      note: 'September salary',
    ),
    testEntry(
      id: 'e3',
      category: LedgerCategory.utilities,
      amount: 2340,
      note: null,
      memberName: 'Priya',
    ),
    testEntry(
      id: 'e4',
      category: LedgerCategory.savings,
      amount: 7500,
      goalId: 'g1',
      note: 'First saving',
    ),
    testEntry(id: 'e5', category: LedgerCategory.dining, amount: 860),
  ],
);

FakeGoalRepository _goals() => FakeGoalRepository(
  goals: [
    testGoal(targetDate: DateTime.now().add(const Duration(days: 40))),
    testGoal(
      id: 'g2',
      title: 'School fees',
      target: 40000,
      saved: 31000,
      targetDate: DateTime.now().add(const Duration(days: 12)),
    ),
    testGoal(
      id: 'g3',
      title: 'Rainy-day fund',
      target: 100000,
      saved: 100000,
      status: GoalStatus.achieved,
    ),
  ],
);

Future<void> _capture(
  WidgetTester tester,
  String name, {
  required String location,
  ThemeMode mode = ThemeMode.light,
  Future<void> Function(WidgetTester)? before,
  Object? extra,
  double height = 1500,
  double width = 390,
  Widget? home,
  bool rtlLarge = false,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
  tester.view.viewPadding = const FakeViewPadding(top: 44, bottom: 34);
  addTearDown(tester.view.reset);
  final key = GlobalKey();
  final router = GoRouter(
    initialLocation: AppRoutes.money,
    routes: [
      GoRoute(
        path: AppRoutes.money,
        builder: (_, _) => home ?? const MoneyScreen(),
      ),
      ...ledgerRoutes,
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: ProviderScope(
        retry: (_, _) => null,
        overrides: ledgerOverrides(ledger: _ledger(), goals: _goals()),
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          routerConfig: router,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: mode,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => !rtlLarge
              ? child!
              : MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: const TextScaler.linear(1.4)),
                  child: Directionality(
                    textDirection: TextDirection.rtl,
                    child: child!,
                  ),
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
  if (before != null) {
    await before(tester);
    await tester.pumpAndSettle();
  }
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_out/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}

class _DashboardLike extends StatelessWidget {
  const _DashboardLike();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          MonthSummaryCard(_summary(), onTap: () {}),
          const SizedBox(height: 16),
          MonthSummaryCard(_summary(expense: 230000), onTap: () {}),
          const SizedBox(height: 16),
          GoalProgressCard(testGoal(), onTap: () {}),
          const SizedBox(height: 8),
          GoalProgressCard(
            testGoal(id: 'zz', title: 'New scooter', saved: 0),
            onTap: () {},
          ),
        ],
      ),
    );
  }
}

void main() {
  setUpAll(_loadFonts);

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final m = mode.name;
    testWidgets('money $m', (t) => _capture(t, 'money_$m', location: AppRoutes.money, mode: mode));
    testWidgets('form $m', (t) => _capture(t, 'form_$m', location: AppRoutes.ledgerEntryNew(type: 'expense'), mode: mode, before: (t) async {
      await t.enterText(find.byType(TextField).first, '1250.50');
      await t.pump();
      await t.tap(find.text('Groceries'));
    }));
    testWidgets('goal $m', (t) => _capture(t, 'goal_$m', location: AppRoutes.goalDetail('g1'), mode: mode));
    testWidgets('entries $m', (t) => _capture(t, 'entries_$m', location: AppRoutes.ledgerEntries, mode: mode));
    testWidgets('dash $m', (t) => _capture(t, 'dash_$m', location: AppRoutes.money, mode: mode, home: const _DashboardLike()));
  }
  testWidgets('money scrolled', (t) => _capture(t, 'money_scrolled', location: AppRoutes.money, height: 844, before: (t) async {
    await t.drag(find.byType(Scrollable).first, const Offset(0, -420));
  }));
  testWidgets('sheet', (t) => _capture(t, 'sheet_light', location: AppRoutes.money, height: 844, before: (t) async {
    await t.tap(find.text('Weekly vegetables'));
  }));
  testWidgets('add sheet', (t) => _capture(t, 'add_sheet_light', location: AppRoutes.money, height: 844, before: (t) async {
    await t.tap(find.text('Add entry'));
  }));
  testWidgets('money rtl', (t) => _capture(t, 'money_rtl_large', location: AppRoutes.money, width: 340, height: 1900, rtlLarge: true));
  testWidgets('form rtl', (t) => _capture(t, 'form_rtl_large', location: AppRoutes.ledgerEntryNew(type: 'expense'), width: 340, height: 1700, rtlLarge: true));
  testWidgets('goal rtl', (t) => _capture(t, 'goal_rtl_large', location: AppRoutes.goalDetail('g2'), width: 340, height: 1100, rtlLarge: true));
  testWidgets('goal achieved', (t) => _capture(t, 'goal_achieved_dark', location: AppRoutes.goalDetail('g3'), mode: ThemeMode.dark, height: 900));
  testWidgets('form income', (t) => _capture(t, 'form_income_light', location: AppRoutes.ledgerEntryNew(type: 'income'), before: (t) async {
    await t.tap(find.text('Save'));
  }));
}
