import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/features/ledger/domain/ledger_entry.dart';
import 'package:family_hub/features/ledger/domain/savings_goal.dart';
import 'package:family_hub/features/ledger/presentation/screens/goal_detail_screen.dart';
import 'package:family_hub/features/ledger/presentation/screens/goal_form_screen.dart';
import 'package:family_hub/features/ledger/presentation/widgets/goal_progress_card.dart';
import 'package:family_hub/shared/models/member.dart';

import '../ledger_test_utils.dart';

Finder _field(String label) => find.widgetWithText(TextField, label);

void main() {
  late FakeLedgerRepository ledger;
  late FakeGoalRepository goals;

  setUp(() {
    ledger = FakeLedgerRepository(
      entries: [
        testEntry(
          id: 'c1',
          amount: 7500,
          category: LedgerCategory.savings,
          goalId: 'g1',
          note: 'First saving',
        ),
        testEntry(id: 'other', note: 'Not a contribution'),
      ],
    );
    goals = FakeGoalRepository(
      goals: [
        testGoal(targetDate: DateTime.now().add(const Duration(days: 40))),
      ],
    );
  });

  group('GoalProgressCard', () {
    testWidgets('shows progress, amounts and days left', (tester) async {
      final fmt = ledgerTestFmt();
      final today = DateTime.now();
      await pumpLedgerApp(
        tester,
        Scaffold(
          body: GoalProgressCard(
            testGoal(
              targetDate: DateTime(today.year, today.month, today.day + 12),
            ),
            onTap: () {},
          ),
        ),
        overrides: ledgerOverrides(ledger: ledger, goals: goals),
      );
      await tester.pumpAndSettle();

      expect(find.text('Goa vacation'), findsOneWidget);
      expect(
        find.text('${fmt.money(12500)} of ${fmt.money(60000)}'),
        findsOneWidget,
      );
      expect(find.text(fmt.percent(12500 / 60000)), findsOneWidget);
      expect(find.text('12 days left'), findsOneWidget);
      // Active goals show no status chip.
      expect(find.text('Active'), findsNothing);
    });
  });

  group('GoalDetailScreen', () {
    testWidgets('admin: details, contributions and menu', (tester) async {
      useTallSurface(tester);
      final router = await pumpLedgerRouter(
        tester,
        overrides: ledgerOverrides(ledger: ledger, goals: goals),
      );
      router.push(AppRoutes.goalDetail('g1'));
      await tester.pumpAndSettle();
      final fmt = ledgerTestFmt();

      expect(find.byType(GoalDetailScreen), findsOneWidget);
      expect(find.text('Goa vacation'), findsWidgets);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text(fmt.money(47500)), findsOneWidget); // still to go
      expect(find.text('40 days left'), findsOneWidget);
      expect(find.text('First saving'), findsOneWidget);
      expect(find.text('Not a contribution'), findsNothing);
      expect(ledger.listCalls.last.query.goalId, 'g1');
      expect(find.byTooltip('Goal actions'), findsOneWidget);

      await tester.tap(find.byTooltip('Goal actions'));
      await tester.pumpAndSettle();
      expect(find.text('Archive'), findsOneWidget);
      expect(find.text('Delete goal'), findsOneWidget);
    });

    testWidgets('contributing that completes the goal celebrates', (
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
      expect(find.text('Contribute to Goa vacation'), findsOneWidget);

      await tester.enterText(_field('Amount (₹)'), '47500');
      await tester.enterText(_field('Note (optional)'), 'Bonus');
      await tester.tap(find.widgetWithText(FilledButton, 'Contribute').last);
      await tester.pumpAndSettle();

      final (goalId, input) = goals.contributions.single;
      expect(goalId, 'g1');
      expect(input.amount, 47500);
      expect(input.toJson()['note'], 'Bonus');
      expect(find.text('Goal achieved!'), findsOneWidget);
      await tester.tap(find.text('Hooray!'));
      await tester.pumpAndSettle();
      expect(find.text('Achieved'), findsOneWidget);
    });

    testWidgets('a normal contribution shows a confirmation', (tester) async {
      useTallSurface(tester);
      final router = await pumpLedgerRouter(
        tester,
        overrides: ledgerOverrides(ledger: ledger, goals: goals),
      );
      router.push(AppRoutes.goalDetail('g1'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Contribute'));
      await tester.pumpAndSettle();
      await tester.enterText(_field('Amount (₹)'), '500');
      await tester.tap(find.widgetWithText(FilledButton, 'Contribute').last);
      await tester.pumpAndSettle();

      expect(find.text('Goal achieved!'), findsNothing);
      expect(find.text('Contribution recorded'), findsOneWidget);
    });

    testWidgets('archived goal: contribute disabled; member has no menu', (
      tester,
    ) async {
      useTallSurface(tester);
      goals.goals[0] = goals.goals[0].copyWith(status: GoalStatus.archived);
      final me = testMember(
        id: 'm-aarav',
        name: 'Aarav',
        role: MemberRole.member,
      );
      final router = await pumpLedgerRouter(
        tester,
        overrides: ledgerOverrides(ledger: ledger, goals: goals, me: me),
      );
      router.push(AppRoutes.goalDetail('g1'));
      await tester.pumpAndSettle();

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Contribute'),
      );
      expect(button.onPressed, isNull);
      expect(
        find.text("This goal is archived and doesn't take contributions."),
        findsOneWidget,
      );
      expect(find.byTooltip('Goal actions'), findsNothing);
      expect(find.text('You see your own contributions here.'), findsOneWidget);
    });

    testWidgets('unknown goal (stale link) shows "not found" + way back', (
      tester,
    ) async {
      useTallSurface(tester);
      final router = await pumpLedgerRouter(
        tester,
        overrides: ledgerOverrides(ledger: ledger, goals: goals),
      );
      router.push(AppRoutes.goalDetail('missing'));
      await tester.pumpAndSettle();
      expect(find.text('Goal not found'), findsOneWidget);
      // A retry cannot help; no admin menu for a goal that is gone.
      expect(find.text('Retry'), findsNothing);
      expect(find.byTooltip('Goal actions'), findsNothing);

      await tester.tap(find.text('Back to Money'));
      await tester.pumpAndSettle();
      expect(find.byType(GoalDetailScreen), findsNothing);
      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        AppRoutes.money,
      );
    });

    testWidgets('admin deletes the goal after confirming', (tester) async {
      useTallSurface(tester);
      final router = await pumpLedgerRouter(
        tester,
        overrides: ledgerOverrides(ledger: ledger, goals: goals),
      );
      router.push(AppRoutes.goalDetail('g1'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Goal actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete goal'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this goal?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(goals.deleted, ['g1']);
      expect(find.byType(GoalDetailScreen), findsNothing);
      expect(find.text('Goal deleted'), findsOneWidget);
    });
  });

  group('GoalFormScreen', () {
    testWidgets('creates a goal', (tester) async {
      useTallSurface(tester);
      final router = await pumpLedgerRouter(
        tester,
        overrides: ledgerOverrides(ledger: ledger, goals: goals),
      );
      router.push(AppRoutes.goalNew);
      await tester.pumpAndSettle();
      expect(find.text('New savings goal'), findsOneWidget);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(goals.created, isEmpty);

      await tester.enterText(_field('Goal name'), ' School fees fund ');
      await tester.enterText(_field('Target amount (₹)'), '40000');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final input = goals.created.single;
      expect(input.toJson(), {
        'title': 'School fees fund',
        'targetAmount': 40000.0,
      });
      expect(find.byType(GoalFormScreen), findsNothing);
      expect(find.text('Goal created'), findsOneWidget);
    });

    testWidgets('edits only changed fields', (tester) async {
      useTallSurface(tester);
      final router = await pumpLedgerRouter(
        tester,
        overrides: ledgerOverrides(ledger: ledger, goals: goals),
      );
      router.push(AppRoutes.goalEdit('g1'));
      await tester.pumpAndSettle();

      expect(find.text('Edit goal'), findsOneWidget);
      expect(
        tester.widget<TextField>(_field('Target amount (₹)')).controller!.text,
        '60000',
      );
      await tester.enterText(_field('Target amount (₹)'), '65000');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final (id, patch) = goals.updated.single;
      expect(id, 'g1');
      expect(patch.toJson(), {'targetAmount': 65000.0});
    });

    testWidgets('members cannot open the form', (tester) async {
      final me = testMember(
        id: 'm-aarav',
        name: 'Aarav',
        role: MemberRole.member,
      );
      await pumpLedgerApp(
        tester,
        const GoalFormScreen(),
        overrides: ledgerOverrides(ledger: ledger, goals: goals, me: me),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Only family admins can create or change savings goals.'),
        findsOneWidget,
      );
      expect(find.text('Save'), findsNothing);
    });
  });
}
