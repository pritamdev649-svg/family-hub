import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:family_hub/features/tasks/application/task_providers.dart';
import 'package:family_hub/features/tasks/domain/family_task.dart';

/// Counters of the Tasks tab header for one scope (me, the family or one
/// member): pending, overdue and done this week, plus the weekly progress.
///
/// Computed from the first page(s) of the scope's pending list (sorted by
/// due date, so overdue tasks come first) and done list (sorted by
/// completion, newest first) — no extra endpoint. When a count may continue
/// on a page that is not loaded yet it is a lower bound ("20+").
/// Local (optimistic) changes of this session are applied, so ticking a
/// task off updates the header immediately.
@immutable
class TasksHeaderStats {
  const TasksHeaderStats({
    this.pending,
    this.overdue,
    this.overdueAtLeast = false,
    this.doneThisWeek,
    this.doneAtLeast = false,
  });

  /// Pending tasks of the scope; `null` while unknown.
  final int? pending;

  /// Overdue tasks of the scope; `null` while unknown.
  final int? overdue;

  /// [overdue] is a lower bound (more may be on later pages).
  final bool overdueAtLeast;

  /// Tasks completed since Monday 00:00 (device time); `null` while unknown.
  final int? doneThisWeek;

  /// [doneThisWeek] is a lower bound.
  final bool doneAtLeast;

  /// Done this week ÷ (done this week + pending), or `null` while unknown or
  /// when there is nothing to measure.
  double? get weekProgress {
    final done = doneThisWeek;
    final open = pending;
    if (done == null || open == null) return null;
    final total = done + open;
    return total == 0 ? null : done / total;
  }

  /// Monday 00:00 (local) of the week containing [today] — the same
  /// Monday-based week as the API's `due=week` filter.
  static DateTime weekStart(DateTime today) =>
      DateTime(today.year, today.month, today.day - (today.weekday - 1));

  /// Builds the counters from the scope's [pendingList] and [doneList]
  /// (either `null` while loading / failed) with [mutations] applied.
  /// [today] is local midnight.
  factory TasksHeaderStats.compute({
    required TaskListState? pendingList,
    required TaskListState? doneList,
    required TaskMutations mutations,
    required DateTime today,
  }) {
    final monday = weekStart(today);
    bool doneSinceMonday(FamilyTask t) {
      final at = t.completedAt;
      return t.isDone && at != null && !at.toLocal().isBefore(monday);
    }

    int? pending;
    int? overdue;
    var overdueAtLeast = false;
    final doneIds = <String>{};

    if (pendingList != null) {
      final items = pendingList.items;
      final resolved = mutations.apply(items);
      final open = [
        for (final t in resolved)
          if (t.isPending) t,
      ];
      // Ticked off or deleted here but still in the server's list.
      final removedLocally = items.length - open.length;
      pending = math.max(0, pendingList.total - removedLocally);
      overdue = open.where((t) => t.isOverdueOn(today)).length;
      overdueAtLeast =
          pendingList.hasMore &&
          open.isNotEmpty &&
          open.last.isOverdueOn(today);
      // Completed on this phone, not refetched yet.
      for (final t in resolved) {
        if (doneSinceMonday(t)) doneIds.add(t.id);
      }
    }

    int? doneThisWeek;
    var doneAtLeast = false;
    if (doneList != null) {
      for (final t in mutations.apply(doneList.items)) {
        if (doneSinceMonday(t)) doneIds.add(t.id);
      }
      doneThisWeek = doneIds.length;
      final last = doneList.items.isEmpty ? null : doneList.items.last;
      doneAtLeast = doneList.hasMore && last != null && doneSinceMonday(last);
    }

    return TasksHeaderStats(
      pending: pending,
      overdue: overdue,
      overdueAtLeast: overdueAtLeast,
      doneThisWeek: doneThisWeek,
      doneAtLeast: doneAtLeast,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TasksHeaderStats &&
      other.pending == pending &&
      other.overdue == overdue &&
      other.overdueAtLeast == overdueAtLeast &&
      other.doneThisWeek == doneThisWeek &&
      other.doneAtLeast == doneAtLeast;

  @override
  int get hashCode =>
      Object.hash(pending, overdue, overdueAtLeast, doneThisWeek, doneAtLeast);
}
