import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/network/api_client.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/features/tasks/domain/family_task.dart';
import 'package:family_hub/features/tasks/presentation/screens/task_detail_screen.dart';
import 'package:family_hub/features/tasks/presentation/screens/task_form_screen.dart';
import 'package:family_hub/features/tasks/presentation/screens/tasks_screen.dart';

import 'tasks_test_helpers.dart';

void main() {
  group('TaskFormScreen', () {
    testWidgets('create: template for the assignee, then saves the draft', (
      tester,
    ) async {
      final repo = FakeTaskRepository();
      await pumpTasksApp(
        tester,
        repo,
        location: AppRoutes.taskNew(assigneeId: anaya.id),
      );

      expect(find.text('New task'), findsWidgets);
      // Anaya is a child → child templates.
      expect(find.text('Quick ideas for Anaya'), findsOneWidget);
      expect(find.text('Finish homework'), findsOneWidget);
      expect(find.text('Budget practice'), findsNothing);

      await tester.tap(find.widgetWithText(ActionChip, 'Finish homework'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(TextFormField, 'Finish homework'),
        findsOneWidget,
      );

      await tester.ensureVisible(find.text('Create task'));
      await tester.tap(find.text('Create task'));
      await tester.pumpAndSettle();

      final draft = repo.drafts.single;
      expect(draft.assigneeId, anaya.id);
      expect(draft.title, 'Finish homework');
      expect(draft.category, TaskCategory.study);
      expect(draft.priority, TaskPriority.high);
      expect(draft.description, isNotEmpty);
      expect(find.text('Task created'), findsOneWidget);
      // Opened directly → leaves to the Tasks tab.
      expect(find.byType(TasksScreen), findsOneWidget);
    });

    testWidgets('validates the title before sending', (tester) async {
      final repo = FakeTaskRepository();
      await pumpTasksApp(tester, repo, location: AppRoutes.taskNew());

      await tester.ensureVisible(find.text('Create task'));
      await tester.tap(find.text('Create task'));
      await tester.pumpAndSettle();
      expect(find.text('This field is required'), findsOneWidget);
      expect(repo.count('create'), 0);

      // Zero-width characters only: still blank (the server would say so).
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'),
        '\u200B\u200D',
      );
      await tester.tap(find.text('Create task'));
      await tester.pumpAndSettle();
      expect(find.text('This field is required'), findsOneWidget);
      expect(repo.count('create'), 0);
    });

    testWidgets('members can only assign themselves', (tester) async {
      await pumpTasksApp(
        tester,
        FakeTaskRepository(),
        me: aarav,
        // Asking for someone else is ignored for a member.
        location: AppRoutes.taskNew(assigneeId: anaya.id),
      );
      expect(
        find.text('Only admins can assign tasks to other family members.'),
        findsOneWidget,
      );
      expect(find.text('Aarav (you)'), findsOneWidget);
      // Aarav is a teen → teen templates.
      expect(find.text('Budget practice'), findsOneWidget);
      final dropdown = tester.widget<DropdownButtonFormField<Object?>>(
        find.byWidgetPredicate((w) => w is DropdownButtonFormField),
      );
      expect(dropdown.onChanged, isNull);
    });

    testWidgets('edit: prefilled, sends only the changes', (tester) async {
      final repo = FakeTaskRepository([
        makeTask('t1', title: 'Old title', due: dueIn(2)),
      ]);
      await pumpTasksApp(tester, repo, location: AppRoutes.taskEdit('t1'));

      expect(find.text('Edit task'), findsOneWidget);
      expect(find.text('Quick ideas'), findsNothing);
      final title = find.widgetWithText(TextFormField, 'Old title');
      expect(title, findsOneWidget);

      await tester.enterText(title, 'New title');
      await tester.ensureVisible(find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      expect(repo.patches.single.fields, {'title': 'New title'});
      expect(find.text('Task updated'), findsOneWidget);
    });

    testWidgets('leaving with unsaved changes asks to discard them', (
      tester,
    ) async {
      final repo = FakeTaskRepository();
      await pumpTasksApp(tester, repo);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'),
        'Half-written task',
      );
      await tester.pump(); // rebuild so the form blocks the pop
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);

      // Cancel keeps the form and the text.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Half-written task'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Discard'));
      await tester.pumpAndSettle();
      expect(find.byType(TaskFormScreen), findsNothing);
      expect(find.byType(TasksScreen), findsOneWidget);
      expect(repo.count('create'), 0);
    });

    testWidgets('edit is refused without permission', (tester) async {
      final repo = FakeTaskRepository([
        makeTask('t1', assignee: aarav, creator: amit),
      ]);
      await pumpTasksApp(
        tester,
        repo,
        me: aarav,
        location: AppRoutes.taskEdit('t1'),
      );
      expect(find.text("You can't edit this task"), findsOneWidget);
      expect(find.text('Save changes'), findsNothing);
    });
  });

  group('TaskDetailScreen', () {
    testWidgets('shows the task and completes it', (tester) async {
      final repo = FakeTaskRepository([
        makeTask(
          't1',
          title: 'Tidy up your room',
          assignee: anaya,
          creator: amit,
          due: dueIn(-1),
        ).copyWith(description: () => 'Toys back in the box'),
      ]);
      await pumpTasksApp(tester, repo, location: AppRoutes.taskDetail('t1'));

      expect(find.text('Tidy up your room'), findsOneWidget);
      expect(find.text('Toys back in the box'), findsOneWidget);
      expect(find.text('Overdue'), findsOneWidget);
      expect(find.text('Anaya'), findsOneWidget);
      expect(find.textContaining('Amit'), findsWidgets);
      expect(find.byTooltip('Edit'), findsOneWidget);
      expect(find.byTooltip('Delete'), findsOneWidget);

      await tester.ensureVisible(find.text('Mark as done'));
      await tester.tap(find.text('Mark as done'));
      await tester.pumpAndSettle();
      expect(repo.count('complete t1'), 1);
      expect(find.text('Reopen task'), findsOneWidget);
      expect(find.text('Completed by'), findsOneWidget);
    });

    testWidgets('a member sees no actions on someone else\'s task', (
      tester,
    ) async {
      final repo = FakeTaskRepository([
        makeTask('t1', title: 'Pay bills', assignee: amit, creator: amit),
      ]);
      await pumpTasksApp(
        tester,
        repo,
        me: aarav,
        location: AppRoutes.taskDetail('t1'),
      );
      expect(find.text('Mark as done'), findsNothing);
      expect(find.byTooltip('Edit'), findsNothing);
      expect(
        find.text('Only Amit or an admin can change the status of this task.'),
        findsOneWidget,
      );
    });

    testWidgets('delete asks for confirmation, then leaves', (tester) async {
      final repo = FakeTaskRepository([makeTask('t1', title: 'Old chore')]);
      await pumpTasksApp(tester, repo, location: AppRoutes.taskDetail('t1'));

      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this task?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(repo.count('delete t1'), 1);
      expect(find.byType(TaskDetailScreen), findsNothing);
      expect(find.text('Task deleted'), findsOneWidget);
    });

    testWidgets('unknown task → "no longer available", no pointless retry', (
      tester,
    ) async {
      await pumpTasksApp(
        tester,
        FakeTaskRepository(),
        location: AppRoutes.taskDetail('missing'),
      );
      expect(find.text('This task is no longer available'), findsOneWidget);
      expect(find.text('Back to tasks'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      expect(find.byType(TaskFormScreen), findsNothing);
    });

    testWidgets('a failed load (offline) still offers retry', (tester) async {
      final repo = FakeTaskRepository([makeTask('t1', title: 'Old chore')])
        ..failGet = const ApiException.network();
      await pumpTasksApp(tester, repo, location: AppRoutes.taskDetail('t1'));
      expect(find.text('Retry'), findsOneWidget);

      repo.failGet = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Old chore'), findsOneWidget);
    });
  });

  testWidgets('form and detail survive RTL + the largest text size', (
    tester,
  ) async {
    final repo = FakeTaskRepository([
      makeTask(
        't1',
        title: 'A rather long task title that needs to wrap on small phones',
        assignee: kamla,
        due: dueIn(-1),
        priority: TaskPriority.high,
      ).copyWith(description: () => 'Details ' * 20),
    ]);
    await pumpTasksApp(
      tester,
      repo,
      location: AppRoutes.taskDetail('t1'),
      textDirection: TextDirection.rtl,
      textScale: 1.6,
      surfaceSize: const Size(360, 800),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(TaskDetailScreen), findsOneWidget);

    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(TaskFormScreen), findsOneWidget);
  });
}
