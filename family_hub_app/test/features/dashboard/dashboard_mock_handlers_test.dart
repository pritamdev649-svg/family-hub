import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/network/mock/mock_backend.dart';
import 'package:family_hub/core/providers/core_providers.dart';
import 'package:family_hub/features/dashboard/data/dashboard_mock_handlers.dart';
import 'package:family_hub/features/dashboard/data/dashboard_repository.dart';
import 'package:family_hub/features/dashboard/domain/dashboard_data.dart';
import 'package:family_hub/features/ledger/data/ledger_mock_handlers.dart';
import 'package:family_hub/features/ledger/domain/ledger_summary.dart';
import 'package:family_hub/features/notices/data/notices_mock_handlers.dart';
import 'package:family_hub/features/sos/data/sos_mock_handlers.dart';
import 'package:family_hub/features/tasks/data/tasks_mock_handlers.dart';
import 'package:family_hub/shared/models/member.dart';

import 'dashboard_test_utils.dart';

/// A backend with the demo seed and every route the dashboard aggregates.
MockBackend _backend() {
  final b = MockBackend();
  registerTaskMocks(b);
  registerLedgerMocks(b);
  registerNoticeMocks(b);
  registerSosMocks(b);
  registerDashboardMocks(b);
  return b;
}

/// Gives Aarav (a `member`) a login so member-scope rules can be tested.
const _aaravUserId = '64f1a0000000000000000103';

void _addAaravAccount(MockDb db) {
  db.insert(MockDb.users, {
    'id': _aaravUserId,
    'email': MockSeed.aaravEmail,
    'password': MockSeed.demoPassword,
    'name': 'Aarav',
    'emailVerified': true,
    'locale': 'en',
    'familyId': MockSeed.familyId,
    'memberId': MockSeed.aaravMemberId,
  });
  db.update(MockDb.members, MockSeed.aaravMemberId, {'userId': _aaravUserId});
}

Future<Map<String, dynamic>> _get(MockBackend b, String userId) async =>
    Map<String, dynamic>.from(
      await mockApiFor(b, userId: userId).get(DashboardRepository.path) as Map,
    );

void main() {
  group('GET /dashboard (mock)', () {
    test('admin: contract shape, member order and admin-only data', () async {
      final b = _backend();
      final json = await _get(b, MockSeed.amitUserId);

      expect(
        json.keys,
        containsAll([
          'family',
          'me',
          'members',
          'myTasks',
          'goals',
          'latestNotices',
          'activeSos',
          'monthSummary',
        ]),
      );
      final family = json['family'] as Map;
      expect(family['id'], MockSeed.familyId);
      expect(family['inviteCode'], MockSeed.inviteCode);
      expect(family['memberCount'], 5);
      expect((json['me'] as Map)['id'], MockSeed.amitMemberId);

      final memberIds = [
        for (final row in json['members'] as List)
          ((row as Map)['member'] as Map)['id'],
      ];
      expect(memberIds, MockSeed.memberIds);
      for (final row in json['members'] as List) {
        final r = row as Map;
        expect(r['pendingTasks'], isA<int>());
        expect(r['overdueTasks'], lessThanOrEqualTo(r['pendingTasks'] as int));
        expect(r['completedThisWeek'], isA<int>());
      }

      expect((json['monthSummary'] as Map)['scope'], 'family');

      // Parses without surprises through the real repository.
      final data = await DashboardRepository(
        mockApiFor(b, userId: MockSeed.amitUserId),
      ).fetch();
      expect(data.me.isAdmin, isTrue);
      expect(data.members, hasLength(5));
      expect(data.monthSummary.scope, SummaryScope.family);
    });

    test(
      'counters match the tasks mock (/tasks filters) per assignee',
      () async {
        final b = _backend();
        final api = mockApiFor(b, userId: MockSeed.amitUserId);
        final data = await DashboardRepository(api).fetch();

        for (final row in data.members) {
          final id = row.member.id;
          Future<int> count(Map<String, String> query) async {
            final page = await api.getPaged<Map<String, dynamic>>(
              '/tasks',
              (j) => j,
              query: {'assigneeId': id, ...query},
              limit: 100,
            );
            return page.total;
          }

          expect(
            row.pendingTasks,
            await count({'status': 'pending'}),
            reason: id,
          );
          expect(
            row.overdueTasks,
            await count({'status': 'pending', 'due': 'overdue'}),
            reason: id,
          );
        }
      },
    );

    test('myTasks: the caller\'s pending tasks in list order, max 5', () async {
      final b = _backend();
      final api = mockApiFor(b, userId: MockSeed.amitUserId);
      final data = await DashboardRepository(api).fetch();
      final page = await api.getPaged<Map<String, dynamic>>(
        '/tasks',
        (j) => j,
        query: {'assigneeId': MockSeed.amitMemberId, 'status': 'pending'},
        limit: mockDashboardMyTasksLimit,
      );

      expect(data.myTasks.length, lessThanOrEqualTo(mockDashboardMyTasksLimit));
      expect(data.myTasks.map((t) => t.id), page.items.map((t) => t['id']));
      expect(data.myTasks.every((t) => t.isPending), isTrue);
      expect(
        data.myTasks.every((t) => t.assigneeId == MockSeed.amitMemberId),
        isTrue,
      );
    });

    test('goals: active only, max 3; notices: pinned first, max 3', () async {
      final b = _backend();
      for (var i = 0; i < 4; i++) {
        b.db.insert(MockDb.goals, {
          'familyId': MockSeed.familyId,
          'title': 'Goal $i',
          'targetMinor': 100000,
          'savedMinor': 0,
          'status': i.isEven ? 'active' : 'archived',
          'createdById': MockSeed.amitMemberId,
        });
      }
      final data = await DashboardRepository(
        mockApiFor(b, userId: MockSeed.amitUserId),
      ).fetch();

      expect(data.goals.length, lessThanOrEqualTo(mockDashboardGoalsLimit));
      expect(data.goals.every((g) => g.isActive), isTrue);
      expect(
        data.latestNotices.length,
        lessThanOrEqualTo(mockDashboardNoticesLimit),
      );
      expect(data.latestNotices.first.title, mockPinnedNoticeTitle);
      expect(data.latestNotices.first.pinned, isTrue);
    });

    test('member: personal month summary, no invite code', () async {
      final b = _backend();
      _addAaravAccount(b.db);
      final data = await DashboardRepository(
        mockApiFor(b, userId: _aaravUserId),
      ).fetch();

      expect(data.me.id, MockSeed.aaravMemberId);
      expect(data.me.role, MemberRole.member);
      expect(data.family.inviteCode, isNull);
      expect(data.monthSummary.scope, SummaryScope.personal);
      expect(
        data.myTasks.every((t) => t.assigneeId == MockSeed.aaravMemberId),
        isTrue,
      );
    });

    test('completedThisWeek only counts the current Monday-based week', () {
      final b = _backend();
      final db = b.db;
      db.removeWhere(MockDb.tasks, (_) => true);
      final now = DateTime(2026, 9, 23, 12); // Wednesday
      String at(DateTime d) => MockDb.iso(d);
      void done(DateTime completedAt) => db.insert(MockDb.tasks, {
        'familyId': MockSeed.familyId,
        'title': 'Done',
        'assigneeId': MockSeed.priyaMemberId,
        'createdById': MockSeed.amitMemberId,
        'status': 'done',
        'category': 'chore',
        'priority': 'low',
        'completedAt': at(completedAt),
      });
      void pending(DateTime? due) => db.insert(MockDb.tasks, {
        'familyId': MockSeed.familyId,
        'title': 'Pending',
        'assigneeId': MockSeed.priyaMemberId,
        'createdById': MockSeed.amitMemberId,
        'status': 'pending',
        'category': 'chore',
        'priority': 'low',
        'dueDate': due == null ? null : at(due),
      });

      done(DateTime(2026, 9, 21)); // Monday 00:00 → counts
      done(DateTime(2026, 9, 23, 8)); // today → counts
      done(DateTime(2026, 9, 20, 23, 59)); // last Sunday → no
      done(DateTime(2026, 9, 28)); // next Monday → no
      pending(DateTime(2026, 9, 22)); // yesterday → overdue
      pending(DateTime(2026, 9, 23)); // today → not overdue
      pending(null); // no due date → never overdue

      final req = MockRequest(
        method: 'GET',
        path: '/dashboard',
        pathParams: const {},
        query: const {},
        body: const {},
        db: db,
        headers: {
          'authorization':
              'Bearer ${MockRequest.accessTokenFor(MockSeed.amitUserId)}',
        },
      );
      final data = DashboardData.fromJson(mockDashboardPayload(req, now: now));
      final priya = data.statsOf(MockSeed.priyaMemberId)!;
      expect(priya.completedThisWeek, 2);
      expect(priya.pendingTasks, 3);
      expect(priya.overdueTasks, 1);
      final amit = data.statsOf(MockSeed.amitMemberId)!;
      expect(amit.isIdle, isTrue);
      expect(data.myTasks, isEmpty);
    });

    test('activeSos lists a freshly raised alert', () async {
      final b = _backend();
      final priyaApi = mockApiFor(b, userId: MockSeed.priyaUserId);
      await priyaApi.post('/sos', body: {'message': 'Need a ride'});

      final data = await DashboardRepository(
        mockApiFor(b, userId: MockSeed.amitUserId),
      ).fetch();
      expect(data.activeSos, hasLength(1));
      expect(data.activeSos.single.memberId, MockSeed.priyaMemberId);
      expect(data.activeSos.single.isActive, isTrue);
    });

    test('401 without a token, 403 NO_FAMILY without a family', () async {
      final b = _backend();
      await expectLater(
        mockApiFor(b).get(DashboardRepository.path),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 401)),
      );

      b.db.update(MockDb.users, MockSeed.priyaUserId, {
        'familyId': null,
        'memberId': null,
      });
      await expectLater(
        mockApiFor(
          b,
          userId: MockSeed.priyaUserId,
        ).get(DashboardRepository.path),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            ApiErrorCode.noFamily,
          ),
        ),
      );
    });

    test('is registered by registerDashboardMocks', () {
      final b = MockBackend();
      registerDashboardMocks(b);
      expect(b.routes, contains('GET /dashboard'));
    });
  });
}
