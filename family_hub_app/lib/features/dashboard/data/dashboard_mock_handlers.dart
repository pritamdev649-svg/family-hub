import 'package:family_hub/core/network/mock/mock_backend.dart';
import 'package:family_hub/core/utils/date_x.dart';
import 'package:family_hub/features/ledger/data/ledger_mock_handlers.dart';
import 'package:family_hub/features/notices/data/notices_mock_handlers.dart';
import 'package:family_hub/features/sos/data/sos_mock_handlers.dart';
import 'package:family_hub/features/tasks/data/tasks_mock_handlers.dart';

/// Registers `GET /dashboard` (docs/03-API_CONTRACT.md §11), computed from
/// the mock collections `families`, `members`, `tasks`, `goals`, `notices`,
/// `sosAlerts` and `ledgerEntries`. Mirrors
/// `family_hub_backend/src/modules/dashboard` (docs/progress/b-dashboard.md):
///
/// * `family` — `inviteCode` only for admins; `me` — the caller's Member.
/// * `members` — every member in `GET /family/members` order with the
///   per-**assignee** counters (see [mockDashboardPayload]).
/// * `myTasks` — the caller's pending tasks in `GET /tasks` order, max 5.
/// * `goals` — active goals, newest first, max 3.
/// * `latestNotices` — pinned first, then newest, max 3.
/// * `activeSos` — like `GET /sos/active` (lazy expiry persisted first).
/// * `monthSummary` — `GET /ledger/summary` of the current month (of the
///   same clock as the counters): family scope for admins, personal scope
///   for members.
///
/// `401` without a valid token, `403 NO_FAMILY` without a family. Query
/// parameters are ignored (the endpoint takes none). The feature mocks that
/// own the collections seed them when they are registered (before this one
/// in `registerAllMocks`); a collection nobody seeded is simply empty.
void registerDashboardMocks(MockBackend b) {
  b.on(
    'GET',
    '/dashboard',
    (req) => MockResponse.ok(mockDashboardPayload(req)),
  );
}

/// Number of pending tasks of the caller in `myTasks`.
const mockDashboardMyTasksLimit = 5;

/// Number of active goals in `goals`.
const mockDashboardGoalsLimit = 3;

/// Number of notices in `latestNotices`.
const mockDashboardNoticesLimit = 3;

/// The `GET /dashboard` payload for the caller of [req]. [now] is injectable
/// for tests (day / week boundaries).
///
/// Counter rules (device local time, the mock's stand-in for the family
/// time zone — same definitions as the tasks mock's `?due=` filters):
/// * `pendingTasks` — status `pending`;
/// * `overdueTasks` — pending with a due date before local midnight today (a
///   task due today is not overdue, one without due date never is);
/// * `completedThisWeek` — status `done` with `completedAt` in
///   `[Monday 00:00, next Monday 00:00)`.
///
/// Tasks of members who left the family are not counted.
Map<String, dynamic> mockDashboardPayload(MockRequest req, {DateTime? now}) {
  final me = req.requireMember();
  final family = req.requireFamily();
  final db = req.db;
  final familyId = '${family['id']}';
  final isAdmin = me['role'] == 'admin';
  final clock = (now ?? DateTime.now()).toLocal();
  final week = _MockWeek(clock);

  final stats = <String, _Counters>{};
  final myPending = <Map<String, dynamic>>[];
  for (final task in req.familyDocs(MockDb.tasks)) {
    final assigneeId = '${task['assigneeId'] ?? ''}';
    final counters = stats.putIfAbsent(assigneeId, _Counters.new);
    if (task['status'] == 'done') {
      final completedAt = MockDb.parse(task['completedAt']);
      if (completedAt != null && week.contains(completedAt)) {
        counters.completedThisWeek++;
      }
      continue;
    }
    if (task['status'] != 'pending') continue;
    counters.pending++;
    final due = MockDb.parse(task['dueDate']);
    if (due != null && due.isBefore(week.startOfToday)) counters.overdue++;
    if (assigneeId == me['id']) myPending.add(task);
  }
  myPending.sort(compareMockTasks);

  final memberDocs = db.where(MockDb.members, (m) => m['familyId'] == familyId)
    ..sort(MockSerializers.compareMembers);

  return {
    'family': MockSerializers.family(db, family, isAdmin: isAdmin),
    'me': MockSerializers.member(me),
    'members': [
      for (final m in memberDocs)
        {
          'member': MockSerializers.member(m),
          ...(stats[m['id']] ?? _Counters()).toJson(),
        },
    ],
    'myTasks': [
      for (final t in myPending.take(mockDashboardMyTasksLimit))
        mockTaskJson(db, t),
    ],
    'goals': mockGoalsList(
      req,
      status: 'active',
    ).take(mockDashboardGoalsLimit).toList(),
    'latestNotices': mockFamilyNotices(
      db,
      familyId,
    ).take(mockDashboardNoticesLimit).toList(),
    'activeSos': mockActiveSosAlerts(db, familyId),
    'monthSummary': mockLedgerSummary(req, month: clock.monthKey),
  };
}

class _Counters {
  int pending = 0;
  int overdue = 0;
  int completedThisWeek = 0;

  Map<String, dynamic> toJson() => {
    'pendingTasks': pending,
    'overdueTasks': overdue,
    'completedThisWeek': completedThisWeek,
  };
}

/// Today and the current Monday-based week in local time.
class _MockWeek {
  _MockWeek(DateTime now)
    : startOfToday = DateTime(now.year, now.month, now.day),
      start = DateTime(now.year, now.month, now.day - (now.weekday - 1)),
      end = DateTime(now.year, now.month, now.day - (now.weekday - 1) + 7);

  final DateTime startOfToday;
  final DateTime start;
  final DateTime end;

  bool contains(DateTime d) => !d.isBefore(start) && d.isBefore(end);
}
