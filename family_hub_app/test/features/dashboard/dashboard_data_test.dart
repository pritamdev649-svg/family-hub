import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/providers/core_providers.dart';
import 'package:family_hub/features/dashboard/data/dashboard_cache.dart';
import 'package:family_hub/features/dashboard/domain/dashboard_data.dart';
import 'package:family_hub/features/dashboard/domain/dashboard_greeting.dart';
import 'package:family_hub/features/ledger/domain/ledger_summary.dart';
import 'package:family_hub/features/sos/domain/sos_alert.dart';
import 'package:family_hub/shared/models/member.dart';

import 'dashboard_test_utils.dart';

void main() {
  group('DashboardData.fromJson', () {
    test('parses a contract payload with every section', () {
      final data = dashboardData(dashboardJson(activeSos: [sosJson()]));

      expect(data.family.id, testFamilyId);
      expect(data.family.name, 'Sharma Family');
      expect(data.family.inviteCode, 'DEMO2345');
      expect(data.me.id, testMemberId);
      expect(data.me.role, MemberRole.admin);
      expect(data.isAdmin, isTrue);

      expect(data.members, hasLength(3));
      expect(data.members.first.member.name, 'Amit Sharma');
      expect(data.members.first.pendingTasks, 2);
      expect(data.members.first.overdueTasks, 1);
      expect(data.members.first.completedThisWeek, 3);
      expect(data.members.last.member.hasAccount, isFalse);

      expect(data.myTasks.map((t) => t.id), ['t1', 't2']);
      expect(data.myTasks.first.dueDate, isNotNull);
      expect(data.goals.single.title, 'Goa vacation');
      expect(data.goals.single.progress, closeTo(0.2083, 0.0001));
      expect(data.latestNotices.single.pinned, isTrue);
      expect(data.activeSos.single.status, SosStatus.active);
      expect(data.monthSummary.scope, SummaryScope.family);
      expect(data.monthSummary.net, closeTo(107999.5, 0.001));
    });

    test('never throws on missing, null or wrongly typed fields', () {
      final data = DashboardData.fromJson({
        'family': 'nope',
        'me': null,
        'members': 'x',
        'myTasks': [null, 3, 'task'],
        'goals': {'id': 'g'},
        'latestNotices': null,
        'activeSos': [
          {'id': ''},
        ],
        'monthSummary': 42,
        'extra': {'ignored': true},
      }, now: DateTime(2026, 3, 9));

      expect(data.family.id, isEmpty);
      expect(data.me.id, isEmpty);
      expect(data.members, isEmpty);
      expect(data.myTasks, isEmpty);
      expect(data.goals, isEmpty);
      expect(data.latestNotices, isEmpty);
      expect(data.activeSos, isEmpty, reason: 'entries without id dropped');
      expect(data.monthSummary.month, '2026-03');
      expect(data.monthSummary.isEmpty, isTrue);
      expect(
        data.monthSummary.scope,
        SummaryScope.personal,
        reason: 'unknown role → member → personal scope',
      );
    });

    test('missing month summary uses the family scope for admins', () {
      final json = dashboardJson()..remove('monthSummary');
      final data = DashboardData.fromJson(json, now: DateTime(2026, 12, 31));
      expect(data.monthSummary.month, '2026-12');
      expect(data.monthSummary.scope, SummaryScope.family);
      expect(data.monthSummary.currency, 'INR');
    });

    test('drops duplicate ids, keeping the first occurrence', () {
      final data = dashboardData(
        dashboardJson(
          myTasks: [
            taskJson(id: 't1', title: 'First'),
            taskJson(id: 't1', title: 'Duplicate'),
          ],
        ),
      );
      expect(data.myTasks.single.title, 'First');
    });

    test('lists are unmodifiable', () {
      final data = dashboardData();
      expect(() => data.members.clear(), throwsUnsupportedError);
      expect(() => data.myTasks.clear(), throwsUnsupportedError);
    });

    test('toJson / fromJson round-trips', () {
      final data = dashboardData(dashboardJson(activeSos: [sosJson()]));
      expect(DashboardData.fromJson(data.toJson()), data);
      expect(DashboardData.fromJson(data.toJson()).hashCode, data.hashCode);
    });
  });

  group('MemberStats.fromJson', () {
    test('clamps negative counters and overdue above pending', () {
      final stats = MemberStats.fromJson(
        statsJson(memberJson(), pending: 1, overdue: 4, done: -2),
      );
      expect(stats.pendingTasks, 1);
      expect(stats.overdueTasks, 1);
      expect(stats.completedThisWeek, 0);
    });

    test('accepts numeric strings and a flattened member row', () {
      final stats = MemberStats.fromJson({
        ...memberJson(id: 'm-x', name: 'Kamla'),
        'pendingTasks': '3',
        'overdueTasks': 2.0,
        'completedThisWeek': '1',
      });
      expect(stats.member.id, 'm-x');
      expect(stats.member.name, 'Kamla');
      expect(stats.pendingTasks, 3);
      expect(stats.overdueTasks, 2);
      expect(stats.completedThisWeek, 1);
    });

    test('isIdle / hasOverdue', () {
      final idle = MemberStats(member: testMe);
      expect(idle.isIdle, isTrue);
      expect(idle.hasOverdue, isFalse);
      expect(idle.copyWith(overdueTasks: 1).hasOverdue, isTrue);
      expect(idle.copyWith(completedThisWeek: 1).isIdle, isFalse);
    });
  });

  group('derived values', () {
    test('family totals and the caller\'s hidden tasks', () {
      final data = dashboardData();
      expect(data.familyPendingTasks, 3);
      expect(data.familyOverdueTasks, 1);
      expect(data.familyCompletedThisWeek, 5);
      expect(data.myStats?.pendingTasks, 2);
      expect(data.myPendingCount, 2);
      expect(data.hiddenMyTasksCount, 0);

      final busy = dashboardData(
        dashboardJson(
          members: [statsJson(memberJson(), pending: 9)],
          myTasks: [
            for (var i = 0; i < 5; i++) taskJson(id: 't$i', title: 'T$i'),
          ],
        ),
      );
      expect(busy.hiddenMyTasksCount, 4);
    });

    test('a family where the caller is alone is new', () {
      final alone = dashboardData(
        dashboardJson(members: [statsJson(memberJson(), done: 3)]),
      );
      expect(alone.hasOtherMembers, isFalse);
      expect(alone.isNewFamily, isTrue);
    });

    test('a family with members but nothing organised yet is new', () {
      final idle = dashboardData(
        dashboardJson(
          members: [
            statsJson(memberJson()),
            statsJson(memberJson(id: 'm-2', name: 'Priya')),
          ],
          myTasks: const [],
          goals: const [],
          notices: const [],
        ),
      );
      expect(idle.hasAnyTasks, isFalse);
      expect(idle.isNewFamily, isTrue);
      expect(dashboardData().isNewFamily, isFalse);
    });

    test('withoutLocations strips member and SOS positions', () {
      const point = {'lat': 28.6, 'lng': 77.2, 'accuracy': 10};
      final data = dashboardData(
        dashboardJson(
          me: memberJson(lastLocation: point, locationSharing: 'always'),
          members: [
            statsJson(
              memberJson(lastLocation: point, locationSharing: 'always'),
            ),
          ],
          activeSos: [sosJson(lastLocation: point)],
        ),
      );
      expect(data.me.lastLocation, isNotNull);
      expect(data.activeSos.single.lastLocation, isNotNull);

      final stripped = data.withoutLocations();
      expect(stripped.me.lastLocation, isNull);
      expect(stripped.members.single.member.lastLocation, isNull);
      expect(stripped.activeSos.single.lastLocation, isNull);
      expect(stripped.activeSos.single.trail, isEmpty);
      expect(stripped.me.name, data.me.name);
    });
  });

  group('greeting', () {
    test('GreetingPeriod boundaries', () {
      GreetingPeriod at(int h, [int m = 0]) =>
          GreetingPeriod.of(DateTime(2026, 9, 21, h, m));
      expect(at(4, 59), GreetingPeriod.night);
      expect(at(5), GreetingPeriod.morning);
      expect(at(11, 59), GreetingPeriod.morning);
      expect(at(12), GreetingPeriod.afternoon);
      expect(at(16, 59), GreetingPeriod.afternoon);
      expect(at(17), GreetingPeriod.evening);
      expect(at(21, 59), GreetingPeriod.evening);
      expect(at(22), GreetingPeriod.night);
      expect(at(0), GreetingPeriod.night);
    });

    test('firstNameOf', () {
      expect(firstNameOf('Amit Sharma'), 'Amit');
      expect(firstNameOf('  Priya  '), 'Priya');
      expect(firstNameOf('अमित शर्मा'), 'अमित');
      expect(firstNameOf('Ana María'), 'Ana');
      expect(firstNameOf(''), '');
      expect(firstNameOf(null), '');
      expect(firstNameOf('   '), '');
      // No-break and ideographic spaces separate words too.
      expect(firstNameOf('Ana\u00A0María'), 'Ana');
      expect(firstNameOf('山田\u3000太郎'), '山田');
    });

    test('nextChangeAfter: the next period start or midnight', () {
      DateTime next(DateTime t) => GreetingPeriod.nextChangeAfter(t);
      expect(next(DateTime(2026, 9, 21, 0, 30)), DateTime(2026, 9, 21, 5));
      expect(next(DateTime(2026, 9, 21, 4, 59)), DateTime(2026, 9, 21, 5));
      expect(next(DateTime(2026, 9, 21, 5)), DateTime(2026, 9, 21, 12));
      expect(next(DateTime(2026, 9, 21, 11, 59)), DateTime(2026, 9, 21, 12));
      expect(next(DateTime(2026, 9, 21, 16)), DateTime(2026, 9, 21, 17));
      expect(next(DateTime(2026, 9, 21, 21)), DateTime(2026, 9, 21, 22));
      expect(next(DateTime(2026, 9, 21, 22)), DateTime(2026, 9, 22));
      // Month and year roll over.
      expect(next(DateTime(2026, 9, 30, 23, 59)), DateTime(2026, 10));
      expect(next(DateTime(2026, 12, 31, 23)), DateTime(2027));
    });

    test('sameSlot: same local date and greeting period', () {
      final morning = DateTime(2026, 9, 21, 9);
      expect(GreetingPeriod.sameSlot(morning, DateTime(2026, 9, 21, 11)), true);
      expect(
        GreetingPeriod.sameSlot(morning, DateTime(2026, 9, 21, 12)),
        false,
        reason: 'afternoon',
      );
      expect(
        GreetingPeriod.sameSlot(
          DateTime(2026, 9, 21, 23),
          DateTime(2026, 9, 22, 1),
        ),
        false,
        reason: 'both night, but another day',
      );
    });
  });

  group('DashboardCache', () {
    test('round-trips the copy of the same account and family only', () async {
      final cache = DashboardCache(LocalCache(await mockPrefs()));
      final data = dashboardData();
      await cache.write(testUserId, data);

      final copy = cache.read(testUserId, testFamilyId);
      expect(copy, isNotNull);
      expect(copy!.data, data);
      expect(copy.userId, testUserId);
      expect(copy.isOfflineCopy, isTrue);

      expect(cache.read('someone-else', testFamilyId), isNull);
      expect(cache.read(testUserId, 'other-family'), isNull);
      expect(cache.read('', testFamilyId), isNull);
    });

    test('never stores locations', () async {
      final prefs = await mockPrefs();
      final cache = DashboardCache(LocalCache(prefs));
      const point = {'lat': 28.6, 'lng': 77.2};
      await cache.write(
        testUserId,
        dashboardData(
          dashboardJson(
            me: memberJson(lastLocation: point, locationSharing: 'always'),
            activeSos: [sosJson(lastLocation: point)],
          ),
        ),
      );
      final raw = prefs.getString(
        '${LocalCache.prefix}${DashboardCache.cacheKey}',
      );
      expect(raw, isNotNull);
      expect(raw, isNot(contains('28.6')));
      expect(raw, isNot(contains('77.2')));
    });

    test('a saved time in the future is clamped to now', () async {
      final cache = DashboardCache(LocalCache(await mockPrefs()));
      await cache.write(testUserId, dashboardData());
      final past = DateTime.now().toUtc().subtract(const Duration(days: 1));
      final copy = cache.read(testUserId, testFamilyId, now: past);
      expect(copy!.savedAt, past);
    });

    test('ignores corrupt entries and other format versions', () async {
      final prefs = await mockPrefs();
      final local = LocalCache(prefs);
      final cache = DashboardCache(local);

      await local.write(DashboardCache.cacheKey, {
        'v': DashboardCache.version + 1,
        'u': testUserId,
        'f': testFamilyId,
        'data': dashboardJson(),
      });
      expect(cache.read(testUserId, testFamilyId), isNull);

      await local.write(DashboardCache.cacheKey, {
        'v': DashboardCache.version,
        'u': testUserId,
        'f': testFamilyId,
        'data': 'garbage',
      });
      expect(cache.read(testUserId, testFamilyId), isNull);

      await prefs.setString(
        '${LocalCache.prefix}${DashboardCache.cacheKey}',
        '{not json',
      );
      expect(cache.read(testUserId, testFamilyId), isNull);

      await cache.write(testUserId, dashboardData());
      await cache.clear();
      expect(cache.read(testUserId, testFamilyId), isNull);
    });
  });
}
