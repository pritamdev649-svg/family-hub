import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:family_hub/core/utils/date_x.dart';
import 'package:family_hub/features/ledger/domain/ledger_summary.dart';
import 'package:family_hub/features/ledger/domain/savings_goal.dart';
import 'package:family_hub/features/notices/domain/notice.dart';
import 'package:family_hub/features/sos/domain/sos_alert.dart';
import 'package:family_hub/features/tasks/domain/family_task.dart';
import 'package:family_hub/shared/json.dart';
import 'package:family_hub/shared/models/family.dart';
import 'package:family_hub/shared/models/member.dart';

/// One row of the dashboard's "Family board": a member with their task
/// counters (contract §11 `members[]`).
///
/// Counters are per **assignee** and use the family time zone on the server:
/// * [pendingTasks]: tasks still `pending`;
/// * [overdueTasks]: pending with a due date before today (never more than
///   [pendingTasks]);
/// * [completedThisWeek]: `done` with `completedAt` in the current week
///   (Monday 00:00 → next Monday 00:00).
@immutable
class MemberStats {
  const MemberStats({
    required this.member,
    this.pendingTasks = 0,
    this.overdueTasks = 0,
    this.completedThisWeek = 0,
  });

  /// Parses `{ member: Member, pendingTasks, overdueTasks, completedThisWeek }`.
  ///
  /// Defensive: a flattened row (the member's fields next to the counters)
  /// is accepted too, counters are never negative and [overdueTasks] never
  /// exceeds [pendingTasks] (an inconsistent server row would otherwise read
  /// "1 pending · 2 overdue").
  factory MemberStats.fromJson(Map<String, dynamic> json) {
    final rawMember = json['member'];
    final pending = _count(json['pendingTasks']);
    return MemberStats(
      member: Member.fromJson(rawMember is Map ? asMap(rawMember) : json),
      pendingTasks: pending,
      overdueTasks: math.min(_count(json['overdueTasks']), pending),
      completedThisWeek: _count(json['completedThisWeek']),
    );
  }

  static int _count(Object? v) => math.max(0, asInt(v));

  final Member member;
  final int pendingTasks;
  final int overdueTasks;
  final int completedThisWeek;

  /// Nothing pending and nothing finished this week.
  bool get isIdle => pendingTasks == 0 && completedThisWeek == 0;

  bool get hasOverdue => overdueTasks > 0;

  Map<String, dynamic> toJson() => {
    'member': member.toJson(),
    'pendingTasks': pendingTasks,
    'overdueTasks': overdueTasks,
    'completedThisWeek': completedThisWeek,
  };

  MemberStats copyWith({
    Member? member,
    int? pendingTasks,
    int? overdueTasks,
    int? completedThisWeek,
  }) => MemberStats(
    member: member ?? this.member,
    pendingTasks: pendingTasks ?? this.pendingTasks,
    overdueTasks: overdueTasks ?? this.overdueTasks,
    completedThisWeek: completedThisWeek ?? this.completedThisWeek,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MemberStats &&
          other.member == member &&
          other.pendingTasks == pendingTasks &&
          other.overdueTasks == overdueTasks &&
          other.completedThisWeek == completedThisWeek;

  @override
  int get hashCode =>
      Object.hash(member, pendingTasks, overdueTasks, completedThisWeek);

  @override
  String toString() =>
      'MemberStats(${member.name}: $pendingTasks pending, $overdueTasks '
      'overdue, $completedThisWeek done this week)';
}

/// Everything the home screen shows, from one `GET /dashboard`
/// (docs/03-API_CONTRACT.md §11). Reuses the feature models of tasks,
/// ledger, notices and SOS.
///
/// Parsing never throws: missing lists are empty, list entries without an
/// id are dropped, duplicate ids keep their first occurrence and a missing
/// `monthSummary` becomes an all-zero summary of the current month (family
/// scope for admins, personal for members).
@immutable
class DashboardData {
  const DashboardData({
    required this.family,
    required this.me,
    this.members = const [],
    this.myTasks = const [],
    this.goals = const [],
    this.latestNotices = const [],
    this.activeSos = const [],
    required this.monthSummary,
  });

  /// Contract limits of the lists (the UI never shows more).
  static const int myTasksLimit = 5;
  static const int goalsLimit = 3;
  static const int noticesLimit = 3;

  factory DashboardData.fromJson(Map<String, dynamic> json, {DateTime? now}) {
    final family = Family.fromJson(asMap(json['family']));
    final me = Member.fromJson(asMap(json['me']));
    final summaryJson = json['monthSummary'];
    return DashboardData(
      family: family,
      me: me,
      members: _unique(
        asMapList(json['members'], MemberStats.fromJson),
        (s) => s.member.id,
      ),
      myTasks: _unique(
        asMapList(json['myTasks'], FamilyTask.fromJson),
        (t) => t.id,
      ),
      goals: _unique(
        asMapList(json['goals'], SavingsGoal.fromJson),
        (g) => g.id,
      ),
      latestNotices: _unique(
        asMapList(json['latestNotices'], Notice.fromJson),
        (n) => n.id,
      ),
      activeSos: _unique(
        asMapList(json['activeSos'], SosAlert.fromJson),
        (a) => a.id,
      ),
      monthSummary: summaryJson is Map
          ? LedgerSummary.fromJson(asMap(summaryJson))
          : LedgerSummary.empty(
              month: (now ?? DateTime.now()).toLocal().monthKey,
              currency: family.currency,
              scope: me.isAdmin ? SummaryScope.family : SummaryScope.personal,
            ),
    );
  }

  /// Unmodifiable list without blank ids and without repeated ids.
  static List<T> _unique<T>(List<T> items, String Function(T) id) {
    final seen = <String>{};
    return List<T>.unmodifiable([
      for (final item in items)
        if (id(item).isNotEmpty && seen.add(id(item))) item,
    ]);
  }

  /// The caller's family (`inviteCode` only for admins).
  final Family family;

  /// The caller's own member profile.
  final Member me;

  /// Every member in contract order (admins first, oldest → youngest).
  final List<MemberStats> members;

  /// The caller's pending tasks, `dueDate` ascending, at most
  /// [myTasksLimit].
  final List<FamilyTask> myTasks;

  /// Active goals, at most [goalsLimit].
  final List<SavingsGoal> goals;

  /// Pinned first, then newest, at most [noticesLimit].
  final List<Notice> latestNotices;

  /// Active SOS alerts of the family (the caller's own included).
  final List<SosAlert> activeSos;

  /// `/ledger/summary` of the current month (family scope for admins,
  /// personal scope for members).
  final LedgerSummary monthSummary;

  bool get isAdmin => me.isAdmin;

  /// Board row of [memberId], or `null`.
  MemberStats? statsOf(String memberId) {
    for (final s in members) {
      if (s.member.id == memberId) return s;
    }
    return null;
  }

  /// The caller's own board row, or `null` when the server left it out.
  MemberStats? get myStats => statsOf(me.id);

  /// How many tasks the caller has pending in total (the board counter, or
  /// the listed tasks when that is larger / missing).
  int get myPendingCount =>
      math.max(myStats?.pendingTasks ?? 0, myTasks.length);

  /// Pending tasks of the caller that the "My tasks" preview does not show.
  int get hiddenMyTasksCount =>
      math.max(0, myPendingCount - math.min(myTasks.length, myTasksLimit));

  int get familyPendingTasks =>
      members.fold(0, (sum, s) => sum + s.pendingTasks);

  int get familyOverdueTasks =>
      members.fold(0, (sum, s) => sum + s.overdueTasks);

  int get familyCompletedThisWeek =>
      members.fold(0, (sum, s) => sum + s.completedThisWeek);

  /// The family has other members besides the caller.
  bool get hasOtherMembers => members.any((s) => s.member.id != me.id);

  /// Any task on the board (pending or finished this week).
  bool get hasAnyTasks =>
      myTasks.isNotEmpty ||
      familyPendingTasks > 0 ||
      familyCompletedThisWeek > 0;

  /// A family that has just been set up: nobody else joined yet, or nothing
  /// has been organised (no tasks, goals or notices). Drives the
  /// "getting started" hints.
  bool get isNewFamily =>
      !hasOtherMembers ||
      (!hasAnyTasks && goals.isEmpty && latestNotices.isEmpty);

  /// A copy without location data (member last locations, SOS positions and
  /// trails) for storing on the device: the offline dashboard never needs
  /// them, and positions are the most sensitive part of the payload.
  DashboardData withoutLocations() => DashboardData(
    family: family,
    me: me.copyWith(lastLocation: () => null),
    members: [
      for (final s in members)
        s.copyWith(member: s.member.copyWith(lastLocation: () => null)),
    ],
    myTasks: myTasks,
    goals: goals,
    latestNotices: latestNotices,
    activeSos: [
      for (final a in activeSos)
        a.copyWith(lastLocation: () => null, trail: const []),
    ],
    monthSummary: monthSummary,
  );

  Map<String, dynamic> toJson() => {
    'family': family.toJson(),
    'me': me.toJson(),
    'members': [for (final s in members) s.toJson()],
    'myTasks': [for (final t in myTasks) t.toJson()],
    'goals': [for (final g in goals) g.toJson()],
    'latestNotices': [for (final n in latestNotices) n.toJson()],
    'activeSos': [for (final a in activeSos) a.toJson()],
    'monthSummary': monthSummary.toJson(),
  };

  DashboardData copyWith({
    Family? family,
    Member? me,
    List<MemberStats>? members,
    List<FamilyTask>? myTasks,
    List<SavingsGoal>? goals,
    List<Notice>? latestNotices,
    List<SosAlert>? activeSos,
    LedgerSummary? monthSummary,
  }) => DashboardData(
    family: family ?? this.family,
    me: me ?? this.me,
    members: members == null ? this.members : List.unmodifiable(members),
    myTasks: myTasks == null ? this.myTasks : List.unmodifiable(myTasks),
    goals: goals == null ? this.goals : List.unmodifiable(goals),
    latestNotices: latestNotices == null
        ? this.latestNotices
        : List.unmodifiable(latestNotices),
    activeSos: activeSos == null
        ? this.activeSos
        : List.unmodifiable(activeSos),
    monthSummary: monthSummary ?? this.monthSummary,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DashboardData &&
          other.family == family &&
          other.me == me &&
          listEquals(other.members, members) &&
          listEquals(other.myTasks, myTasks) &&
          listEquals(other.goals, goals) &&
          listEquals(other.latestNotices, latestNotices) &&
          listEquals(other.activeSos, activeSos) &&
          other.monthSummary == monthSummary;

  @override
  int get hashCode => Object.hash(
    family,
    me,
    Object.hashAll(members),
    Object.hashAll(myTasks),
    Object.hashAll(goals),
    Object.hashAll(latestNotices),
    Object.hashAll(activeSos),
    monthSummary,
  );

  @override
  String toString() =>
      'DashboardData(${family.name}, me: ${me.name}, '
      '${members.length} members, ${myTasks.length} tasks)';
}

/// What `dashboardProvider` holds: the [data] of one account plus where it
/// came from.
///
/// * [userId] is the signed-in account the data was loaded for, so a screen
///   never shows one account's dashboard to another (see
///   `dashboardViewProvider`).
/// * [savedAt] is set when the data is the **offline copy** saved on the
///   device (the server could not be reached); it says when it was saved.
@immutable
class DashboardSnapshot {
  const DashboardSnapshot({
    required this.userId,
    required this.data,
    this.savedAt,
  });

  final String userId;
  final DashboardData data;
  final DateTime? savedAt;

  bool get isOfflineCopy => savedAt != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DashboardSnapshot &&
          other.userId == userId &&
          other.data == data &&
          other.savedAt == savedAt;

  @override
  int get hashCode => Object.hash(userId, data, savedAt);

  @override
  String toString() =>
      'DashboardSnapshot($userId, offline: $isOfflineCopy, $data)';
}
