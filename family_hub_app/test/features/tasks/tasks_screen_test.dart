import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/network/api_client.dart';
import 'package:family_hub/features/tasks/domain/family_task.dart';
import 'package:family_hub/features/tasks/presentation/screens/task_form_screen.dart';
import 'package:family_hub/features/tasks/presentation/widgets/task_check_button.dart';
import 'package:family_hub/features/tasks/presentation/widgets/task_glass.dart';
import 'package:family_hub/features/tasks/presentation/widgets/task_tile.dart';

import 'tasks_test_helpers.dart';

void main() {
  FakeTaskRepository seededRepo() => FakeTaskRepository([
    makeTask('bill', title: 'Pay electricity bill', due: dueIn(-2)),
    makeTask(
      'insurance',
      title: 'Renew car insurance',
      due: dueIn(0),
      priority: TaskPriority.high,
    ),
    makeTask('tap', title: 'Fix kitchen tap', due: dueIn(4)),
    makeTask('shelf', title: 'Build a shelf'),
    makeTask(
      'homework',
      title: 'Finish homework',
      assignee: aarav,
      due: dueIn(0),
      category: TaskCategory.study,
    ),
    makeTask(
      'walk',
      title: 'Morning walk',
      assignee: kamla,
      status: TaskStatus.done,
    ),
  ]);

  group('TasksScreen', () {
    testWidgets('My tasks: grouped sections, count, no assignee', (
      tester,
    ) async {
      await pumpTasksApp(tester, seededRepo());

      expect(find.text('My tasks'), findsOneWidget);
      expect(find.text('4 pending tasks'), findsOneWidget);
      expect(find.text('Overdue'), findsWidgets); // chip + section header
      expect(find.text('Due today'), findsOneWidget);
      expect(find.text('Upcoming'), findsOneWidget);
      expect(find.text('No due date'), findsOneWidget);
      expect(find.text('Pay electricity bill'), findsOneWidget);
      expect(find.text('Finish homework'), findsNothing);
      // Sections come in order: overdue task above today's task.
      expect(
        tester.getTopLeft(find.text('Pay electricity bill')).dy,
        lessThan(tester.getTopLeft(find.text('Renew car insurance')).dy),
      );
      // The assignee is obvious in "My tasks".
      expect(find.bySemanticsLabel('Assigned to Amit'), findsNothing);
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('header counts pending, overdue and done this week', (
      tester,
    ) async {
      final repo = seededRepo()
        ..tasks.add(
          makeTask(
            'fresh',
            title: 'Water the plants',
            status: TaskStatus.done,
          ).copyWith(completedAt: () => DateTime.now().toUtc()),
        );
      await pumpTasksApp(tester, repo);

      String valueOf(int i) {
        final stat = find.byType(TaskGlassStat).at(i);
        return tester.widget<TaskGlassStat>(stat).value ?? '';
      }

      expect(find.text('Tasks'), findsOneWidget);
      expect(valueOf(0), '4', reason: "Amit's pending tasks");
      expect(valueOf(1), '1', reason: 'the electricity bill is overdue');
      expect(valueOf(2), '1', reason: 'done this week');
      expect(find.text('Done this week'), findsOneWidget);
      expect(find.text('20%'), findsOneWidget, reason: '1 of 1 + 4');

      // Family scope: Aarav's homework counts too.
      await tester.tap(find.text('Family'));
      await tester.pumpAndSettle();
      expect(valueOf(0), '5');
      expect(find.text('Everything your family is working on'), findsOneWidget);
    });

    testWidgets('Family view: member chips filter the list', (tester) async {
      await pumpTasksApp(tester, seededRepo());

      await tester.tap(find.text('Family'));
      await tester.pumpAndSettle();
      expect(find.text('Finish homework'), findsOneWidget);
      expect(find.text('Pay electricity bill'), findsOneWidget);
      expect(find.text('Everyone'), findsOneWidget);

      // The member chips scroll horizontally.
      final aaravChip = find.widgetWithText(ChoiceChip, 'Aarav');
      await tester.ensureVisible(aaravChip);
      await tester.pumpAndSettle();
      await tester.tap(aaravChip);
      await tester.pumpAndSettle();
      expect(find.text('Finish homework'), findsOneWidget);
      expect(find.text('Pay electricity bill'), findsNothing);
      expect(find.text('1 pending task'), findsOneWidget);
    });

    testWidgets('Done view hides due chips and lists completed tasks', (
      tester,
    ) async {
      await pumpTasksApp(tester, seededRepo());

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Morning walk'), findsOneWidget);
      expect(find.text('This week'), findsNothing);
      expect(find.text('1 completed task'), findsOneWidget);
    });

    testWidgets('friendly empty states per filter', (tester) async {
      await pumpTasksApp(tester, FakeTaskRepository());

      expect(find.text("You're all caught up!"), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'New task'), findsWidgets);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Overdue'));
      await tester.pumpAndSettle();
      expect(find.text('Nothing overdue'), findsOneWidget);

      // The due chips scroll horizontally.
      final weekChip = find.widgetWithText(ChoiceChip, 'This week');
      await tester.ensureVisible(weekChip);
      await tester.pumpAndSettle();
      await tester.tap(weekChip);
      await tester.pumpAndSettle();
      expect(find.text('Nothing due this week'), findsOneWidget);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('No completed tasks yet'), findsOneWidget);
    });

    testWidgets('error state offers retry', (tester) async {
      final repo = FakeTaskRepository([makeTask('a', title: 'Visible later')])
        ..failList = const ApiException.network();
      await pumpTasksApp(tester, repo);
      expect(find.text('Retry'), findsOneWidget);

      repo.failList = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Visible later'), findsOneWidget);
    });

    testWidgets('checkbox completes optimistically, then refreshes', (
      tester,
    ) async {
      final repo = seededRepo()..gate = Completer<void>();
      await pumpTasksApp(tester, repo);

      final tile = find.widgetWithText(TaskTile, 'Fix kitchen tap');
      await tester.tap(
        find.descendant(of: tile, matching: find.byType(Checkbox)),
      );
      await tester.pump();

      Checkbox checkbox() => tester.widget<Checkbox>(
        find.descendant(of: tile, matching: find.byType(Checkbox)),
      );
      expect(checkbox().value, isTrue, reason: 'optimistic');
      expect(checkbox().onChanged, isNull, reason: 'busy: no double submit');

      repo.gate!.complete();
      await tester.pumpAndSettle();
      expect(repo.count('complete tap'), 1);
      expect(find.text('Nice work! Task completed.'), findsOneWidget);
      // The refetched "My tasks" list no longer contains the done task.
      expect(find.text('Fix kitchen tap'), findsNothing);
      expect(find.text('3 pending tasks'), findsOneWidget);
    });

    testWidgets('a failed toggle rolls back and shows the error', (
      tester,
    ) async {
      final repo = seededRepo()
        ..failNextMutation = const ApiException(
          code: ApiErrorCode.forbidden,
          statusCode: 403,
        );
      await pumpTasksApp(tester, repo);

      final tile = find.widgetWithText(TaskTile, 'Build a shelf');
      await tester.tap(
        find.descendant(of: tile, matching: find.byType(Checkbox)),
      );
      await tester.pumpAndSettle();

      final checkbox = tester.widget<Checkbox>(
        find.descendant(of: tile, matching: find.byType(Checkbox)),
      );
      expect(checkbox.value, isFalse);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Nice work! Task completed.'), findsNothing);
    });

    testWidgets('members only get checkboxes for their own tasks', (
      tester,
    ) async {
      await pumpTasksApp(tester, seededRepo(), me: aarav);

      await tester.tap(find.text('Family'));
      await tester.pumpAndSettle();
      final own = find.widgetWithText(TaskTile, 'Finish homework');
      final other = find.widgetWithText(TaskTile, 'Pay electricity bill');
      expect(
        find.descendant(of: own, matching: find.byType(TaskCheckButton)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: own, matching: find.byType(Checkbox)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: other, matching: find.byType(Checkbox)),
        findsNothing,
      );
      // Others' tasks show a read-only status mark instead.
      expect(
        find.descendant(of: other, matching: find.byType(TaskStatusMark)),
        findsOneWidget,
      );
    });

    testWidgets('FAB opens the new-task form with the filtered member', (
      tester,
    ) async {
      await pumpTasksApp(tester, seededRepo());
      await tester.tap(find.text('Family'));
      await tester.pumpAndSettle();
      // The member chips scroll horizontally.
      final anayaChip = find.widgetWithText(ChoiceChip, 'Anaya');
      await tester.ensureVisible(anayaChip);
      await tester.pumpAndSettle();
      await tester.tap(anayaChip);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      final form = tester.widget<TaskFormScreen>(find.byType(TaskFormScreen));
      expect(form.initialAssigneeId, anaya.id);
      expect(form.taskId, isNull);
      // Anaya is pre-selected, so child templates are offered.
      expect(find.text('Quick ideas for Anaya'), findsOneWidget);
    });

    testWidgets('a task created from the tab shows up after saving', (
      tester,
    ) async {
      final repo = seededRepo();
      await pumpTasksApp(tester, repo);
      expect(find.text('4 pending tasks'), findsOneWidget);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'),
        'Call the plumber',
      );
      await tester.pump();
      await tester.ensureVisible(find.text('Create task'));
      await tester.tap(find.text('Create task'));
      await tester.pumpAndSettle();

      expect(find.byType(TaskFormScreen), findsNothing);
      expect(find.text('Task created'), findsOneWidget);
      expect(find.text('Call the plumber'), findsOneWidget);
      expect(find.text('5 pending tasks'), findsOneWidget);
      expect(repo.drafts.single.assigneeId, amit.id);
    });

    testWidgets('RTL and the largest text size lay out without overflow', (
      tester,
    ) async {
      await pumpTasksApp(
        tester,
        seededRepo(),
        textDirection: TextDirection.rtl,
        textScale: 1.6,
        surfaceSize: const Size(360, 800),
      );
      await tester.tap(find.text('Family'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(TaskTile), findsWidgets);
    });

    testWidgets('a short landscape screen with large text never overflows', (
      tester,
    ) async {
      await pumpTasksApp(
        tester,
        seededRepo(),
        textScale: 1.6,
        surfaceSize: const Size(640, 360),
      );
      // Header, filters and list scroll together: the switcher is reachable
      // below the (compact) header.
      await tester.scrollUntilVisible(
        find.text('Family'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Family'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // The list follows below the filters.
      await tester.scrollUntilVisible(
        find.byType(TaskTile).first,
        100,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(TaskTile), findsWidgets);
    });
  });
}
