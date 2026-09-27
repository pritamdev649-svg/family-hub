import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/network/api_client.dart';
import 'package:family_hub/features/tasks/application/task_providers.dart';
import 'package:family_hub/features/tasks/domain/family_task.dart';
import 'package:family_hub/features/tasks/domain/task_failure.dart';
import 'package:family_hub/features/tasks/domain/task_query.dart';
import 'package:family_hub/features/tasks/domain/task_requests.dart';
import 'package:family_hub/shared/providers/shared_providers.dart';

import 'tasks_test_helpers.dart';

void main() {
  const pending = TaskQuery();

  group('taskListProvider', () {
    test('loads the first page and appends more without duplicates', () async {
      final repo = FakeTaskRepository([
        for (var i = 0; i < 25; i++) makeTask('t$i', due: dueIn(i)),
      ]);
      final container = makeContainer(repo);
      final sub = container.listen(taskListProvider(pending), (_, _) {});

      final first = await container.read(taskListProvider(pending).future);
      expect(first.items, hasLength(20));
      expect(first.hasMore, isTrue);
      expect(first.total, 25);

      await container.read(taskListProvider(pending).notifier).loadMore();
      final all = sub.read().requireValue;
      expect(all.items, hasLength(25));
      expect(all.items.map((t) => t.id).toSet(), hasLength(25));
      expect(all.hasMore, isFalse);
      expect(all.isLoadingMore, isFalse);

      // At the end: no further request.
      await container.read(taskListProvider(pending).notifier).loadMore();
      expect(repo.count('list'), 2);
    });

    test('a failed page keeps the items and can be retried', () async {
      final repo = FakeTaskRepository([
        for (var i = 0; i < 21; i++) makeTask('t$i'),
      ]);
      final container = makeContainer(repo);
      final sub = container.listen(taskListProvider(pending), (_, _) {});
      await container.read(taskListProvider(pending).future);

      repo.failList = const ApiException.network();
      await expectLater(
        container.read(taskListProvider(pending).notifier).loadMore(),
        throwsA(isA<ApiException>()),
      );
      expect(sub.read().requireValue.items, hasLength(20));
      expect(sub.read().requireValue.isLoadingMore, isFalse);
      expect(sub.read().requireValue.hasMore, isTrue);

      repo.failList = null;
      await container.read(taskListProvider(pending).notifier).loadMore();
      expect(sub.read().requireValue.items, hasLength(21));
    });

    test('refetches on markChanged({DataScope.tasks})', () async {
      final repo = FakeTaskRepository([makeTask('a')]);
      final container = makeContainer(repo);
      container.listen(taskListProvider(pending), (_, _) {});
      await container.read(taskListProvider(pending).future);
      expect(repo.count('list'), 1);

      repo.tasks.add(makeTask('b'));
      container.read(dataRefreshProvider.notifier).markChanged({
        DataScope.ledger,
      });
      await container.read(taskListProvider(pending).future);
      expect(repo.count('list'), 1, reason: 'other scopes are ignored');

      container.read(dataRefreshProvider.notifier).markChanged({
        DataScope.tasks,
      });
      final state = await container.read(taskListProvider(pending).future);
      expect(repo.count('list'), 2);
      expect(state.items.map((t) => t.id), ['a', 'b']);
    });

    test('filters by status and assignee', () async {
      final repo = FakeTaskRepository([
        makeTask('mine', assignee: amit),
        makeTask('kid', assignee: aarav),
        makeTask('done', assignee: aarav, status: TaskStatus.done),
      ]);
      final container = makeContainer(repo);
      final query = TaskQuery(assigneeId: aarav.id);
      container.listen(taskListProvider(query), (_, _) {});
      final state = await container.read(taskListProvider(query).future);
      expect(state.items.map((t) => t.id), ['kid']);

      const done = TaskQuery(status: TaskListStatus.done);
      container.listen(taskListProvider(done), (_, _) {});
      final doneState = await container.read(taskListProvider(done).future);
      expect(doneState.items.map((t) => t.id), ['done']);
    });
  });

  group('TaskController.setDone', () {
    test('is optimistic, then applies the server answer', () async {
      final task = makeTask('t1', due: dueIn(0));
      final repo = FakeTaskRepository([task])..gate = Completer<void>();
      final container = makeContainer(repo);
      final changes = <int?>[];
      container.listen(
        dataRefreshProvider.select((m) => m[DataScope.tasks]),
        (_, next) => changes.add(next),
      );
      final controller = container.read(taskControllerProvider.notifier);

      final future = controller.setDone(task, done: true);
      var state = container.read(taskControllerProvider);
      expect(state.resolve(task).isDone, isTrue);
      expect(state.resolve(task).completedById, amit.id);
      expect(state.isBusy('t1'), isTrue);
      expect(changes, isEmpty);

      // A second tap while in flight is ignored.
      await controller.setDone(task, done: false);
      expect(repo.count('complete'), 1);
      expect(repo.count('reopen'), 0);

      repo.gate!.complete();
      final saved = await future;
      state = container.read(taskControllerProvider);
      expect(saved.isDone, isTrue);
      expect(state.isBusy('t1'), isFalse);
      expect(state.resolve(task), saved);
      expect(changes, hasLength(1), reason: 'markChanged after success');
    });

    test('rolls back and rethrows when the request fails', () async {
      final task = makeTask('t1', assignee: aarav);
      final repo = FakeTaskRepository([task])
        ..gate = Completer<void>()
        ..failNextMutation = const ApiException.network();
      final container = makeContainer(repo);
      var changed = false;
      container.listen(dataRefreshProvider, (_, _) => changed = true);
      final controller = container.read(taskControllerProvider.notifier);

      final future = controller.setDone(task, done: true);
      expect(
        container.read(taskControllerProvider).resolve(task).isDone,
        isTrue,
      );
      repo.gate!.complete();
      await expectLater(future, throwsA(isA<ApiException>()));

      final state = container.read(taskControllerProvider);
      expect(state.resolve(task), task);
      expect(state.latest, isEmpty);
      expect(state.isBusy('t1'), isFalse);
      expect(changed, isFalse, reason: 'offline: nothing to refetch');
      expect(repo.sessionRefreshes, 0);
    });

    test('a second toggle while one is in flight is ignored', () async {
      final task = makeTask('t1');
      final repo = FakeTaskRepository([task])..gate = Completer<void>();
      final container = makeContainer(repo);
      final controller = container.read(taskControllerProvider.notifier);

      final first = controller.setDone(task, done: true);
      final second = controller.setDone(task, done: false);
      repo.gate!.complete();
      await Future.wait([first, second]);
      expect(repo.count('complete'), 1);
      expect(repo.count('reopen'), 0);
      expect(container.read(taskControllerProvider).resolve(task).isDone, true);
    });

    test('reopen clears completion fields optimistically', () async {
      final task = makeTask('t1', status: TaskStatus.done);
      final repo = FakeTaskRepository([task])..gate = Completer<void>();
      final container = makeContainer(repo);
      final future = container
          .read(taskControllerProvider.notifier)
          .reopen(task);
      final optimistic = container.read(taskControllerProvider).resolve(task);
      expect(optimistic.isPending, isTrue);
      expect(optimistic.completedAt, isNull);
      expect(optimistic.completedById, isNull);
      repo.gate!.complete();
      expect((await future).isPending, isTrue);
    });
  });

  group('TaskMutations.resolve', () {
    test('a newer server copy wins over the local one', () {
      final local = makeTask(
        't1',
        status: TaskStatus.done,
        updatedAt: DateTime.utc(2026, 9, 10),
      );
      final state = TaskMutations(latest: {'t1': local});
      final stale = makeTask('t1', updatedAt: DateTime.utc(2026, 9, 9));
      final newer = makeTask(
        't1',
        title: 'Renamed elsewhere',
        updatedAt: DateTime.utc(2026, 9, 11),
      );
      expect(state.resolve(stale), local);
      expect(state.resolve(newer), newer);
      expect(state.resolve(makeTask('other')).id, 'other');
    });
  });

  group('TaskController create / update / delete', () {
    test('create sends the draft and announces the change', () async {
      final repo = FakeTaskRepository();
      final container = makeContainer(repo);
      final before = container.read(dataRefreshProvider)[DataScope.tasks];
      final task = await container
          .read(taskControllerProvider.notifier)
          .create(TaskDraft(title: ' Read ', assigneeId: aarav.id));
      expect(repo.drafts.single.assigneeId, aarav.id);
      expect(task.title, 'Read');
      expect(
        container.read(dataRefreshProvider)[DataScope.tasks],
        (before ?? 0) + 1,
      );
    });

    test('update stores the saved task; empty patches are not sent', () async {
      final task = makeTask('t1', title: 'Old');
      final repo = FakeTaskRepository([task]);
      final container = makeContainer(repo);
      final controller = container.read(taskControllerProvider.notifier);

      final saved = await controller.update('t1', TaskPatch(title: 'New'));
      expect(saved.title, 'New');
      expect(container.read(taskControllerProvider).resolve(task).title, 'New');
      expect(repo.patches.single.fields, {'title': 'New'});

      final version = container.read(dataRefreshProvider)[DataScope.tasks];
      await controller.update('t1', TaskPatch());
      expect(
        container.read(dataRefreshProvider)[DataScope.tasks],
        version,
        reason: 'nothing changed → no refetch',
      );
    });

    test('delete hides the task everywhere', () async {
      final repo = FakeTaskRepository([makeTask('a'), makeTask('b')]);
      final container = makeContainer(repo);
      container.listen(taskListProvider(pending), (_, _) {});
      final list = await container.read(taskListProvider(pending).future);

      await container.read(taskControllerProvider.notifier).delete('a');
      final state = container.read(taskControllerProvider);
      expect(state.isDeleted('a'), isTrue);
      expect(state.apply(list.items).map((t) => t.id), ['b']);
      expect(state.isBusy('a'), isFalse);
      expect(repo.count('delete a'), 1);
    });

    test('a failed delete keeps the task and clears the busy flag', () async {
      final repo = FakeTaskRepository([makeTask('a')])
        ..failNextMutation = const ApiException.network();
      final container = makeContainer(repo);
      await expectLater(
        container.read(taskControllerProvider.notifier).delete('a'),
        throwsA(isA<ApiException>()),
      );
      final state = container.read(taskControllerProvider);
      expect(state.isDeleted('a'), isFalse);
      expect(state.isBusy('a'), isFalse);
    });
  });

  group('TaskController failure recovery', () {
    const gone = ApiException(code: ApiErrorCode.notFound, statusCode: 404);
    const forbidden = ApiException(
      code: ApiErrorCode.forbidden,
      statusCode: 403,
    );
    const assigneeLeft = ApiException(
      code: ApiErrorCode.validation,
      statusCode: 422,
      details: {'assigneeId': 'Assignee must be a member of your family'},
    );

    int version(ProviderContainer c, DataScope scope) =>
        c.read(dataRefreshProvider)[scope] ?? 0;

    test(
      '404 on complete: the task is gone everywhere, lists refetch',
      () async {
        final task = makeTask('t1');
        final repo = FakeTaskRepository([task])..failNextMutation = gone;
        final container = makeContainer(repo);
        final before = version(container, DataScope.tasks);

        await expectLater(
          container.read(taskControllerProvider.notifier).complete(task),
          throwsA(isA<ApiException>()),
        );
        final state = container.read(taskControllerProvider);
        expect(state.isDeleted('t1'), isTrue);
        expect(state.apply([task]), isEmpty);
        expect(state.isBusy('t1'), isFalse);
        expect(version(container, DataScope.tasks), before + 1);
      },
    );

    test('404 on update marks the task gone', () async {
      final repo = FakeTaskRepository([makeTask('t1')])
        ..failNextMutation = gone;
      final container = makeContainer(repo);
      await expectLater(
        container
            .read(taskControllerProvider.notifier)
            .update('t1', TaskPatch(title: 'x')),
        throwsA(isA<ApiException>()),
      );
      expect(container.read(taskControllerProvider).isDeleted('t1'), isTrue);
    });

    test('deleting a task that is already gone counts as deleted', () async {
      final repo = FakeTaskRepository([makeTask('t1')])
        ..failNextMutation = gone;
      final container = makeContainer(repo);
      final before = version(container, DataScope.tasks);

      await container.read(taskControllerProvider.notifier).delete('t1');
      final state = container.read(taskControllerProvider);
      expect(state.isDeleted('t1'), isTrue);
      expect(state.isBusy('t1'), isFalse);
      expect(version(container, DataScope.tasks), before + 1);
    });

    test('403: rolls back, refetches tasks and re-reads the session', () async {
      final task = makeTask('t1', assignee: aarav);
      final repo = FakeTaskRepository([task])..failNextMutation = forbidden;
      final container = makeContainer(repo, me: aarav);
      final before = version(container, DataScope.tasks);

      await expectLater(
        container.read(taskControllerProvider.notifier).complete(task),
        throwsA(isA<ApiException>()),
      );
      final state = container.read(taskControllerProvider);
      expect(state.resolve(task), task);
      expect(state.isDeleted('t1'), isFalse);
      expect(version(container, DataScope.tasks), before + 1);
      expect(repo.sessionRefreshes, 1);
    });

    test('403 on create also re-reads the session', () async {
      final repo = FakeTaskRepository()..failNextMutation = forbidden;
      final container = makeContainer(repo, me: aarav);
      await expectLater(
        container
            .read(taskControllerProvider.notifier)
            .create(TaskDraft(title: 'x', assigneeId: anaya.id)),
        throwsA(isA<ApiException>()),
      );
      expect(repo.sessionRefreshes, 1);
    });

    test('422 details.assigneeId refetches members and tasks', () async {
      final repo = FakeTaskRepository()..failNextMutation = assigneeLeft;
      final container = makeContainer(repo);
      final members = version(container, DataScope.members);
      final tasks = version(container, DataScope.tasks);
      await expectLater(
        container
            .read(taskControllerProvider.notifier)
            .create(const TaskDraft(title: 'x', assigneeId: 'm-left')),
        throwsA(isA<ApiException>()),
      );
      expect(version(container, DataScope.members), members + 1);
      expect(version(container, DataScope.tasks), tasks + 1);
      expect(repo.sessionRefreshes, 0);
    });

    test('TaskFailure classifies API errors', () {
      expect(TaskFailure.of(gone), TaskFailure.gone);
      expect(
        TaskFailure.of(
          const ApiException(code: ApiErrorCode.badRequest, statusCode: 400),
        ),
        TaskFailure.gone,
      );
      expect(TaskFailure.of(forbidden), TaskFailure.notAllowed);
      expect(
        TaskFailure.of(
          const ApiException(code: ApiErrorCode.noFamily, statusCode: 403),
        ),
        TaskFailure.noFamily,
      );
      expect(TaskFailure.noFamily.isAccessChange, isTrue);
      expect(TaskFailure.notAllowed.isAccessChange, isTrue);
      expect(TaskFailure.gone.isAccessChange, isFalse);
      expect(TaskFailure.of(assigneeLeft), TaskFailure.assigneeUnavailable);
      expect(
        TaskFailure.of(
          const ApiException(code: ApiErrorCode.validation, statusCode: 422),
        ),
        TaskFailure.other,
      );
      expect(TaskFailure.of(const ApiException.network()), TaskFailure.other);
      expect(TaskFailure.of(StateError('x')), TaskFailure.other);
    });
  });

  group('taskTodayProvider', () {
    test('is today\'s local midnight', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final today = container.read(taskTodayProvider);
      final now = DateTime.now();
      expect(today, DateTime(now.year, now.month, now.day));
    });

    test(
      'lists with a due filter refetch at midnight, others do not',
      () async {
        final repo = FakeTaskRepository([makeTask('a', due: dueIn(0))]);
        var now = DateTime(2026, 9, 26, 23, 59, 59);
        final container = ProviderContainer(
          overrides: [
            ...taskOverrides(repo),
            taskClockProvider.overrideWithValue(() => now),
          ],
          retry: (_, _) => null,
        );
        addTearDown(container.dispose);
        expect(container.read(taskTodayProvider), DateTime(2026, 9, 26));
        const today = TaskQuery(due: TaskDueFilter.today);
        container.listen(taskListProvider(today), (_, _) {});
        container.listen(taskListProvider(pending), (_, _) {});
        await container.read(taskListProvider(today).future);
        await container.read(taskListProvider(pending).future);
        expect(repo.count('list'), 2);

        // Same day: nothing changes.
        container.invalidate(taskTodayProvider);
        await container.read(taskListProvider(today).future);
        expect(repo.count('list'), 2);

        // What the midnight timer does.
        now = DateTime(2026, 9, 27, 0, 0, 1);
        container.invalidate(taskTodayProvider);
        expect(container.read(taskTodayProvider), DateTime(2026, 9, 27));
        await container.read(taskListProvider(today).future);
        await container.read(taskListProvider(pending).future);
        expect(
          repo.count('list'),
          3,
          reason: 'only the "today" list refetched',
        );
      },
    );
  });
}
