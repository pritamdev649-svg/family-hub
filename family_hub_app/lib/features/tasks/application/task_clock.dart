import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Slack after midnight before the day rolls over (timers may fire a few
/// milliseconds early relative to `DateTime.now()` on some platforms).
const _rolloverSlack = Duration(seconds: 1);

/// Minimum time between two "the app came back to the foreground" refetches
/// of task data (no request storm when switching apps back and forth).
const taskResumeRefreshInterval = Duration(minutes: 1);

/// The clock of the tasks feature (overridable in tests).
final taskClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Today's date (device-local midnight). It rebuilds itself right after the
/// next local midnight (DST-safe), so screens that watch it re-evaluate
/// "overdue / due today / this week" when the app stays open overnight, and
/// task lists with a due filter refetch for the new day. Timers can fire late
/// after the phone slept, so the Tasks tab also invalidates it on resume.
final taskTodayProvider = Provider.autoDispose<DateTime>((ref) {
  final now = ref.watch(taskClockProvider)();
  final today = DateTime(now.year, now.month, now.day);
  final tomorrow = DateTime(now.year, now.month, now.day + 1);
  final timer = Timer(tomorrow.difference(now) + _rolloverSlack, () {
    if (ref.mounted) ref.invalidateSelf();
  });
  ref.onDispose(timer.cancel);
  return today;
});
