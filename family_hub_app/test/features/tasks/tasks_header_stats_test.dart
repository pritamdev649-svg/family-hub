import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/network/api_client.dart';
import 'package:family_hub/features/tasks/application/task_providers.dart';
import 'package:family_hub/features/tasks/domain/family_task.dart';
import 'package:family_hub/features/tasks/presentation/tasks_header_stats.dart';

import 'tasks_test_helpers.dart';

/// Header counters of the Tasks tab (pending / overdue / done this week and
/// the weekly progress), computed from the first pages of the scope's
/// pending and done lists.
void main() {
  // Wednesday, 30 Sep 2026 (local midnight); the week started Monday 28th.
  final today = DateTime(2026, 9, 30);
  DateTime day(int d) => DateTime(2026, 9, d).toUtc();

  TaskListState list(List<FamilyTask> items, {int? total, bool? hasMore}) {
    final t = total ?? items.length;
    return TaskListState(
      page: Paged(
        items: items,
        page: 1,
        limit: 20,
        total: t,
        hasMore: hasMore ?? items.length < t,
      ),
    );
  }

  FamilyTask done(String id, DateTime completedAt) => makeTask(
    id,
    status: TaskStatus.done,
  ).copyWith(completedAt: () => completedAt);

  test('counts pending, overdue and tasks done since Monday', () {
    final stats = TasksHeaderStats.compute(
      pendingList: list([
        makeTask('a', due: day(20)),
        makeTask('b', due: day(29)),
        makeTask('c', due: day(30)),
        makeTask('d'),
      ]),
      doneList: list([
        done('x', DateTime(2026, 9, 29, 18).toUtc()),
        done('y', DateTime(2026, 9, 28).toUtc()), // Monday 00:00 counts
        done('z', DateTime(2026, 9, 27, 23, 59).toUtc()), // last Sunday
      ]),
      mutations: const TaskMutations(),
      today: today,
    );
    expect(stats.pending, 4);
    expect(stats.overdue, 2);
    expect(stats.overdueAtLeast, isFalse);
    expect(stats.doneThisWeek, 2);
    expect(stats.doneAtLeast, isFalse);
    expect(stats.weekProgress, closeTo(2 / 6, 1e-9));
  });

  test('unknown while a list is loading; no progress without tasks', () {
    final loading = TasksHeaderStats.compute(
      pendingList: null,
      doneList: list([]),
      mutations: const TaskMutations(),
      today: today,
    );
    expect(loading.pending, isNull);
    expect(loading.overdue, isNull);
    expect(loading.doneThisWeek, 0);
    expect(loading.weekProgress, isNull);

    final empty = TasksHeaderStats.compute(
      pendingList: list([]),
      doneList: list([]),
      mutations: const TaskMutations(),
      today: today,
    );
    expect(empty.pending, 0);
    expect(empty.weekProgress, isNull);
  });

  test('marks counts that continue on unloaded pages as lower bounds', () {
    final stats = TasksHeaderStats.compute(
      // Every loaded pending task is overdue and more pages exist.
      pendingList: list([
        makeTask('a', due: day(1)),
        makeTask('b', due: day(2)),
      ], total: 30),
      doneList: list([done('x', DateTime(2026, 9, 30, 9).toUtc())], total: 12),
      mutations: const TaskMutations(),
      today: today,
    );
    expect(stats.pending, 30);
    expect(stats.overdue, 2);
    expect(stats.overdueAtLeast, isTrue);
    expect(stats.doneThisWeek, 1);
    expect(stats.doneAtLeast, isTrue);
  });

  test('applies local changes: ticked off, reopened and deleted tasks', () {
    final pendingA = makeTask('a', due: day(20));
    final pendingB = makeTask('b');
    final doneX = done('x', DateTime(2026, 9, 29).toUtc());
    final mutations = TaskMutations(
      latest: {
        // Ticked off on this phone, the lists are not refetched yet.
        'a': pendingA.copyWith(
          status: TaskStatus.done,
          completedAt: () => DateTime(2026, 9, 30, 8).toUtc(),
          updatedAt: () => DateTime.utc(2026, 9, 30, 8),
        ),
        // Reopened on this phone.
        'x': doneX.copyWith(
          status: TaskStatus.pending,
          completedAt: () => null,
          updatedAt: () => DateTime.utc(2026, 9, 30, 8),
        ),
      },
      deleted: {'b'},
    );
    final stats = TasksHeaderStats.compute(
      pendingList: list([pendingA, pendingB]),
      doneList: list([doneX]),
      mutations: mutations,
      today: today,
    );
    expect(stats.pending, 0);
    expect(stats.overdue, 0);
    expect(stats.doneThisWeek, 1, reason: 'a counts, x was reopened');
  });

  test('weekStart is the Monday of the week, also across months', () {
    expect(
      TasksHeaderStats.weekStart(DateTime(2026, 9, 28)),
      DateTime(2026, 9, 28),
    );
    expect(
      TasksHeaderStats.weekStart(DateTime(2026, 10, 4)),
      DateTime(2026, 9, 28),
    );
    expect(
      TasksHeaderStats.weekStart(DateTime(2027, 1, 1)),
      DateTime(2026, 12, 28),
    );
  });
}
