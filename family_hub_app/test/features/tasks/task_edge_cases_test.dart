import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/network/api_client.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/features/tasks/domain/family_task.dart';
import 'package:family_hub/features/tasks/presentation/screens/task_detail_screen.dart';
import 'package:family_hub/features/tasks/presentation/task_errors.dart';
import 'package:family_hub/features/tasks/presentation/screens/task_form_screen.dart';
import 'package:family_hub/features/tasks/presentation/screens/tasks_screen.dart';
import 'package:family_hub/features/tasks/presentation/widgets/task_gone_view.dart';
import 'package:family_hub/features/tasks/presentation/widgets/task_tile.dart';
import 'package:family_hub/l10n/app_localizations_en.dart';
import 'package:family_hub/shared/providers/shared_providers.dart';

import 'tasks_test_helpers.dart';

/// Edge cases of the tasks feature (docs/progress/f-tasks.md "Hardening"):
/// deleted records, permission changes, removed members, rapid taps, long
/// text.
void main() {
  const gone = ApiException(code: ApiErrorCode.notFound, statusCode: 404);
  const forbidden = ApiException(code: ApiErrorCode.forbidden, statusCode: 403);

  test('taskErrorMessage picks the task-specific text per action', () {
    final l10n = AppLocalizationsEn();
    const assigneeLeft = ApiException(
      code: ApiErrorCode.validation,
      statusCode: 422,
      details: {'assigneeId': 'gone'},
    );
    const noFamily = ApiException(code: ApiErrorCode.noFamily, statusCode: 403);
    String? msg(Object e, TaskAction a) => taskErrorMessage(e, a, l10n);

    expect(msg(gone, TaskAction.complete), l10n.tasksErrorGone);
    expect(msg(gone, TaskAction.update), l10n.tasksErrorGone);
    expect(msg(gone, TaskAction.create), isNull);
    expect(msg(forbidden, TaskAction.create), l10n.tasksErrorAssignSelfOnly);
    expect(msg(forbidden, TaskAction.reassign), l10n.tasksErrorAssignSelfOnly);
    expect(msg(forbidden, TaskAction.update), l10n.tasksErrorEditNotAllowed);
    expect(msg(forbidden, TaskAction.delete), l10n.tasksErrorEditNotAllowed);
    expect(
      msg(forbidden, TaskAction.reopen),
      l10n.tasksErrorCompleteNotAllowed,
    );
    expect(
      msg(assigneeLeft, TaskAction.reopen),
      l10n.tasksErrorAssigneeRemoved,
    );
    expect(
      msg(assigneeLeft, TaskAction.update),
      l10n.tasksErrorAssigneeNotInFamily,
    );
    // Generic app-wide messages for everything else.
    expect(msg(noFamily, TaskAction.complete), isNull);
    expect(msg(const ApiException.network(), TaskAction.complete), isNull);
    expect(
      msg(
        const ApiException(code: ApiErrorCode.validation, statusCode: 422),
        TaskAction.create,
      ),
      isNull,
    );
  });

  group('deleted tasks', () {
    testWidgets('a push link to a deleted task shows "no longer available" '
        'with a way back', (tester) async {
      await pumpTasksApp(
        tester,
        FakeTaskRepository(),
        location: AppRoutes.taskDetail('64f1a0000000000000009999'),
      );
      expect(find.byType(TaskGoneView), findsOneWidget);
      expect(find.text('This task is no longer available'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      expect(find.byTooltip('Edit'), findsNothing);

      await tester.tap(find.text('Back to tasks'));
      await tester.pumpAndSettle();
      expect(find.byType(TasksScreen), findsOneWidget);
    });

    testWidgets('a malformed link (400) is treated as gone', (tester) async {
      final repo = FakeTaskRepository()
        ..failGet = const ApiException(
          code: ApiErrorCode.badRequest,
          statusCode: 400,
        );
      await pumpTasksApp(
        tester,
        repo,
        location: AppRoutes.taskDetail('not-an-id'),
      );
      expect(find.byType(TaskGoneView), findsOneWidget);
    });

    testWidgets(
      'an open detail notices a deletion by someone else on refresh',
      (tester) async {
        final repo = FakeTaskRepository([makeTask('t1', title: 'Old chore')]);
        await pumpTasksApp(tester, repo, location: AppRoutes.taskDetail('t1'));
        expect(find.text('Old chore'), findsOneWidget);

        repo.tasks.clear(); // another admin deleted it
        await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
        await tester.pumpAndSettle();
        expect(find.byType(TaskGoneView), findsOneWidget);
        expect(find.text('Old chore'), findsNothing);
        expect(find.byTooltip('Delete'), findsNothing);
      },
    );

    testWidgets('completing a task deleted elsewhere explains it and removes '
        'the row', (tester) async {
      final repo = FakeTaskRepository([
        makeTask('a', title: 'Still here'),
        makeTask('b', title: 'Deleted elsewhere'),
      ]);
      await pumpTasksApp(tester, repo);

      repo
        ..tasks.removeWhere((t) => t.id == 'b')
        ..failNextMutation = gone;
      final tile = find.widgetWithText(TaskTile, 'Deleted elsewhere');
      await tester.tap(
        find.descendant(of: tile, matching: find.byType(Checkbox)),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('This task was deleted by someone else.'),
        findsOneWidget,
      );
      expect(find.text('Deleted elsewhere'), findsNothing);
      expect(find.text('Still here'), findsOneWidget);
      expect(find.text('1 pending task'), findsOneWidget);
    });

    testWidgets('saving an edit of a task deleted meanwhile explains it', (
      tester,
    ) async {
      final repo = FakeTaskRepository([makeTask('t1', title: 'Old title')]);
      await pumpTasksApp(tester, repo, location: AppRoutes.taskEdit('t1'));

      repo.failNextMutation = gone;
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Old title'),
        'New title',
      );
      await tester.ensureVisible(find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      expect(
        find.text('This task was deleted by someone else.'),
        findsOneWidget,
      );
      expect(find.byType(TaskGoneView), findsOneWidget);
      // The unsaved-changes guard is gone with the form: leaving just works.
      await tester.tap(find.text('Back to tasks'));
      await tester.pumpAndSettle();
      expect(find.byType(TasksScreen), findsOneWidget);
    });

    testWidgets('deleting a task someone else already deleted just closes', (
      tester,
    ) async {
      final repo = FakeTaskRepository([makeTask('t1', title: 'Old chore')]);
      await pumpTasksApp(tester, repo, location: AppRoutes.taskDetail('t1'));
      repo.failNextMutation = gone;

      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.byType(TaskDetailScreen), findsNothing);
      expect(find.text('Task deleted'), findsOneWidget);
    });
  });

  group('permission changes', () {
    testWidgets('a refused complete (403) explains why and re-reads the '
        'session', (tester) async {
      final repo = FakeTaskRepository([makeTask('t1', title: 'Water plants')])
        ..failNextMutation = forbidden;
      await pumpTasksApp(tester, repo);

      final tile = find.widgetWithText(TaskTile, 'Water plants');
      await tester.tap(
        find.descendant(of: tile, matching: find.byType(Checkbox)),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Only the person the task is assigned to or an admin can complete '
          'or reopen it.',
        ),
        findsOneWidget,
      );
      expect(repo.sessionRefreshes, 1);
      final checkbox = tester.widget<Checkbox>(
        find.descendant(of: tile, matching: find.byType(Checkbox)),
      );
      expect(checkbox.value, isFalse, reason: 'rolled back');
    });

    testWidgets('a refused edit (403) keeps the form and explains why', (
      tester,
    ) async {
      final repo = FakeTaskRepository([makeTask('t1', title: 'Old title')]);
      await pumpTasksApp(tester, repo, location: AppRoutes.taskEdit('t1'));
      repo.failNextMutation = forbidden;

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Old title'),
        'New title',
      );
      await tester.ensureVisible(find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Only an admin or the person who created this task can change or '
          'delete it.',
        ),
        findsOneWidget,
      );
      expect(find.byType(TaskFormScreen), findsOneWidget);
      expect(find.text('New title'), findsOneWidget, reason: 'input kept');
      expect(repo.sessionRefreshes, 1);
    });

    testWidgets('without a member profile the new-task form is refused', (
      tester,
    ) async {
      await pumpTasksApp(
        tester,
        FakeTaskRepository(),
        withoutMember: true,
        location: AppRoutes.taskNew(),
      );
      expect(find.text("You can't create tasks right now"), findsOneWidget);
      expect(find.text('Create task'), findsNothing);
    });

    testWidgets('an assignee removed while the form was open (422) is '
        'explained', (tester) async {
      final repo = FakeTaskRepository()
        ..failNextMutation = const ApiException(
          code: ApiErrorCode.validation,
          statusCode: 422,
          details: {'assigneeId': 'Assignee must be a member of your family'},
        );
      await pumpTasksApp(
        tester,
        repo,
        location: AppRoutes.taskNew(assigneeId: anaya.id),
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'),
        'Feed the cat',
      );
      await tester.ensureVisible(find.text('Create task'));
      await tester.tap(find.text('Create task'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'That person is no longer in your family. Please choose someone '
          'else.',
        ),
        findsOneWidget,
      );
      expect(find.byType(TaskFormScreen), findsOneWidget);
    });
  });

  group('members who left the family', () {
    // The API sends `assigneeName: null` for removed members.
    FamilyTask leftTask() => makeTask(
      't1',
      title: 'Morning walk',
      assignee: kamla,
      status: TaskStatus.done,
    ).copyWith(assigneeName: '');
    final remaining = [amit, aarav, anaya];

    testWidgets('tile and detail show "Former member"; reopen is explained '
        'instead of failing', (tester) async {
      final repo = FakeTaskRepository([leftTask()]);
      await pumpTasksApp(tester, repo, members: remaining);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      final tile = find.widgetWithText(TaskTile, 'Morning walk');
      expect(
        find.descendant(of: tile, matching: find.text('Former member')),
        findsOneWidget,
      );

      await tester.tap(find.text('Morning walk'));
      await tester.pumpAndSettle();
      expect(find.byType(TaskDetailScreen), findsOneWidget);
      expect(find.text('Former member'), findsOneWidget);
      expect(find.text('Reopen task'), findsNothing);
      expect(
        find.textContaining("This task can't be reopened"),
        findsOneWidget,
      );
      expect(find.text('Unknown'), findsNothing);
    });

    testWidgets('editing keeps the former assignee without forcing a new one', (
      tester,
    ) async {
      final repo = FakeTaskRepository([leftTask()]);
      await pumpTasksApp(
        tester,
        repo,
        members: remaining,
        location: AppRoutes.taskEdit('t1'),
      );
      expect(
        find.textContaining('is no longer in your family'),
        findsOneWidget,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Morning walk'),
        'Evening walk',
      );
      await tester.ensureVisible(find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      expect(find.text('Choose who should do this task'), findsNothing);
      expect(repo.patches.single.fields, {'title': 'Evening walk'});
    });
  });

  group('stale member list', () {
    // Kamla exists (the API names her) but this phone's list does not know
    // her yet (e.g. added on another phone).
    final done = makeTask(
      't1',
      title: 'Morning walk',
      assignee: kamla,
      status: TaskStatus.done,
    );

    testWidgets('is not mistaken for a removed assignee on the detail', (
      tester,
    ) async {
      await pumpTasksApp(
        tester,
        FakeTaskRepository([done]),
        members: [amit, aarav],
        location: AppRoutes.taskDetail('t1'),
      );
      expect(find.text('Reopen task'), findsOneWidget);
      expect(find.textContaining("can't be reopened"), findsNothing);
      expect(find.text('Kamla'), findsOneWidget);
    });

    testWidgets('the edit form refetches members and keeps the assignee', (
      tester,
    ) async {
      final repo = FakeTaskRepository([done]);
      await pumpTasksApp(
        tester,
        repo,
        members: [amit, aarav],
        location: AppRoutes.taskEdit('t1'),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TaskFormScreen)),
      );
      expect(container.read(dataRefreshProvider)[DataScope.members], 1);
      expect(find.textContaining('is no longer in your family'), findsNothing);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Morning walk'),
        'Evening walk',
      );
      await tester.ensureVisible(find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(repo.patches.single.fields, {'title': 'Evening walk'});
    });
  });

  group('rapid taps', () {
    testWidgets('a double tap on "New task" opens one form', (tester) async {
      await pumpTasksApp(tester, FakeTaskRepository());
      final fab = find.byType(FloatingActionButton);
      await tester.tap(fab);
      await tester.tap(fab, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(TaskFormScreen), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(TaskFormScreen), findsNothing);
      expect(find.byType(TasksScreen), findsOneWidget);
    });

    testWidgets('a double tap on a tile opens one detail', (tester) async {
      await pumpTasksApp(
        tester,
        FakeTaskRepository([makeTask('t1', title: 'Water plants')]),
      );
      final title = find.text('Water plants');
      await tester.tap(title);
      await tester.tap(title, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(TaskDetailScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(TaskDetailScreen), findsNothing);
    });

    testWidgets('double-tapping "Create task" sends one request', (
      tester,
    ) async {
      final repo = FakeTaskRepository();
      await pumpTasksApp(tester, repo, location: AppRoutes.taskNew());
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'),
        'Feed the cat',
      );
      await tester.ensureVisible(find.text('Create task'));
      final button = find.text('Create task');
      await tester.tap(button);
      await tester.tap(button, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(repo.count('create'), 1);
    });
  });

  group('stale data', () {
    Future<void> resume(WidgetTester tester) async {
      for (final state in const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pumpAndSettle();
    }

    testWidgets('coming back to the app refetches tasks changed by others '
        '(throttled)', (tester) async {
      var now = DateTime(2026, 9, 26, 10);
      final repo = FakeTaskRepository([makeTask('a', title: 'Mine')]);
      await pumpTasksApp(tester, repo, clock: () => now);
      final lists = repo.count('list');
      // The visible "My tasks" list (the header's done-this-week counter
      // reads the done list of the same scope as well).
      final pendingLists = repo.count('list pending');

      repo.tasks.add(makeTask('b', title: 'Added by Priya'));
      now = now.add(const Duration(seconds: 20));
      await resume(tester);
      expect(repo.count('list'), lists, reason: 'too soon after the last one');

      now = now.add(const Duration(minutes: 2));
      await resume(tester);
      expect(repo.count('list pending'), pendingLists + 1);
      expect(find.text('Added by Priya'), findsOneWidget);
    });
  });

  testWidgets('very long titles and names never overflow (RTL, large text)', (
    tester,
  ) async {
    final longName = 'Aaravvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv' * 2;
    final longMember = aarav.copyWith(name: longName);
    final repo = FakeTaskRepository([
      makeTask(
        't1',
        title: 'Supercalifragilistic' * 6,
        assignee: longMember,
        due: dueIn(-400),
        priority: TaskPriority.high,
      ),
    ]);
    await pumpTasksApp(
      tester,
      repo,
      members: [amit, longMember],
      textDirection: TextDirection.rtl,
      textScale: 1.6,
      surfaceSize: const Size(320, 700),
    );
    await tester.tap(find.text('Family'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final title = find.textContaining('Supercalifragilistic');
    await tester.ensureVisible(title);
    await tester.pumpAndSettle();
    await tester.tap(title);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(TaskDetailScreen), findsOneWidget);
    // Scroll the whole detail (lazily built) to lay out every row.
    await tester.scrollUntilVisible(
      find.text(longName),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text(longName), findsOneWidget);
  });
}
