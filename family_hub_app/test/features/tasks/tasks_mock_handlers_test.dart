import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/network/mock/mock_backend.dart';
import 'package:family_hub/features/tasks/data/tasks_mock_handlers.dart';

const _aaravUserId = '64f1a0000000000000000103';

RequestOptions _req(
  String method,
  String path, {
  Object? data,
  Map<String, dynamic>? query,
  String userId = MockSeed.amitUserId,
}) => RequestOptions(
  method: method,
  baseUrl: MockBackend.baseUrl,
  path: path,
  data: data,
  queryParameters: query,
  headers: {'Authorization': 'Bearer ${MockRequest.accessTokenFor(userId)}'},
);

Future<MockException> _error(Future<Object?> f) async {
  try {
    await f;
  } on MockException catch (e) {
    return e;
  }
  fail('expected a MockException');
}

List<Map<String, dynamic>> _items(MockResponse r) =>
    (r.data! as List).cast<Map<String, dynamic>>();

void main() {
  late MockBackend b;

  setUp(() {
    b = MockBackend();
    registerTaskMocks(b);
    // Aarav (member role) gets an account so member permissions can be tested.
    b.db.insert(MockDb.users, {
      'id': _aaravUserId,
      'email': MockSeed.aaravEmail,
      'name': 'Aarav Sharma',
      'familyId': MockSeed.familyId,
      'memberId': MockSeed.aaravMemberId,
      'emailVerified': true,
    });
    b.db.update(MockDb.members, MockSeed.aaravMemberId, {
      'userId': _aaravUserId,
    });
  });

  Future<MockResponse> list([Map<String, dynamic>? query]) =>
      b.handle(_req('GET', '/tasks', query: query));

  group('GET /tasks', () {
    test('seeds realistic tasks and returns contract Task objects', () async {
      final r = await list({'limit': '100'});
      final items = _items(r);
      expect(items.length, greaterThanOrEqualTo(12));
      expect(r.meta?['total'], items.length);
      final first = items.first;
      expect(
        first.keys,
        containsAll([
          'id',
          'title',
          'assigneeId',
          'assigneeName',
          'createdById',
          'createdByName',
          'dueDate',
          'category',
          'priority',
          'status',
          'completedAt',
          'completedById',
          'createdAt',
          'updatedAt',
        ]),
      );
      expect(first.containsKey('familyId'), isFalse);
      expect(items.any((t) => t['status'] == 'done'), isTrue);
      expect(
        items.map((t) => t['assigneeId']).toSet(),
        containsAll(MockSeed.memberIds),
      );
    });

    test('pending: dueDate asc, no due date last', () async {
      final items = _items(await list({'status': 'pending', 'limit': '100'}));
      expect(items.every((t) => t['status'] == 'pending'), isTrue);
      final dues = [for (final t in items) MockDb.parse(t['dueDate'])];
      final firstNull = dues.indexOf(null);
      expect(firstNull, greaterThan(0));
      expect(dues.skip(firstNull).every((d) => d == null), isTrue);
      final dated = dues.take(firstNull).cast<DateTime>().toList();
      for (var i = 1; i < dated.length; i++) {
        expect(dated[i].isBefore(dated[i - 1]), isFalse);
      }
    });

    test('done: completedAt desc; all: pending first', () async {
      final done = _items(await list({'status': 'done'}));
      final completed = [for (final t in done) MockDb.parse(t['completedAt'])!];
      for (var i = 1; i < completed.length; i++) {
        expect(completed[i].isAfter(completed[i - 1]), isFalse);
      }
      final all = _items(await list({'status': 'all', 'limit': '100'}));
      final firstDone = all.indexWhere((t) => t['status'] == 'done');
      expect(all.skip(firstDone).every((t) => t['status'] == 'done'), isTrue);
    });

    test('due filters use the device day', () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = DateTime(now.year, now.month, now.day + 1);

      final overdue = _items(await list({'due': 'overdue', 'status': 'all'}));
      expect(overdue, isNotEmpty);
      for (final t in overdue) {
        expect(t['status'], 'pending');
        expect(MockDb.parse(t['dueDate'])!.isBefore(today), isTrue);
      }

      final dueToday = _items(await list({'due': 'today', 'status': 'all'}));
      expect(dueToday, isNotEmpty);
      for (final t in dueToday) {
        final d = MockDb.parse(t['dueDate'])!;
        expect(!d.isBefore(today) && d.isBefore(tomorrow), isTrue);
      }

      final week = _items(await list({'due': 'week', 'status': 'all'}));
      final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
      final nextMonday = DateTime(monday.year, monday.month, monday.day + 7);
      for (final t in week) {
        final d = MockDb.parse(t['dueDate'])!;
        expect(!d.isBefore(monday) && d.isBefore(nextMonday), isTrue);
      }
    });

    test('assigneeId filter and pagination meta', () async {
      final r = await list({
        'assigneeId': MockSeed.aaravMemberId,
        'status': 'all',
        'limit': '2',
      });
      expect(_items(r), hasLength(2));
      expect(
        _items(r).every((t) => t['assigneeId'] == MockSeed.aaravMemberId),
        isTrue,
      );
      expect(r.meta?['hasMore'], isTrue);
      final page2 = await list({
        'assigneeId': MockSeed.aaravMemberId,
        'status': 'all',
        'limit': '2',
        'page': '2',
      });
      expect(page2.meta?['page'], 2);
    });

    test('assigneeId: malformed → 422, matched case-insensitively', () async {
      final e = await _error(list({'assigneeId': 'Aarav'}));
      expect(e.status, 422);
      expect(e.details?.keys, ['assigneeId']);
      final upper = _items(
        await list({
          'assigneeId': MockSeed.aaravMemberId.toUpperCase(),
          'status': 'all',
        }),
      );
      expect(upper, isNotEmpty);
      expect(
        upper.every((t) => t['assigneeId'] == MockSeed.aaravMemberId),
        isTrue,
      );
      // Blank values count as "not given".
      final blank = await list({'assigneeId': ' ', 'due': '', 'status': ''});
      expect(blank.status, 200);
    });

    test('invalid filters → 422', () async {
      expect((await _error(list({'status': 'open'}))).status, 422);
      expect((await _error(list({'due': 'soon'}))).code, 'VALIDATION_ERROR');
      expect((await _error(list({'limit': '500'}))).status, 422);
    });

    test('requires a signed-in family member', () async {
      final e = await _error(
        b.handle(
          RequestOptions(
            method: 'GET',
            baseUrl: MockBackend.baseUrl,
            path: '/tasks',
          ),
        ),
      );
      expect(e.status, 401);
    });
  });

  group('POST /tasks', () {
    Map<String, dynamic> body([Map<String, dynamic> extra = const {}]) => {
      'title': '  Water the plants ',
      'assigneeId': MockSeed.anayaMemberId,
      'category': 'chore',
      'priority': 'low',
      ...extra,
    };

    test('admin creates for anyone (201) with resolved names', () async {
      final r = await b.handle(
        _req(
          'POST',
          '/tasks',
          data: body({
            'dueDate': DateTime(2026, 10, 1).toUtc().toIso8601String(),
          }),
        ),
      );
      expect(r.status, 201);
      final task = r.data! as Map<String, dynamic>;
      expect(task['title'], 'Water the plants');
      expect(task['assigneeName'], 'Anaya');
      expect(task['createdById'], MockSeed.amitMemberId);
      expect(task['createdByName'], 'Amit');
      expect(task['status'], 'pending');
      expect(task['description'], isNull);
      expect(task['dueDate'], isNotNull);
    });

    test('member may only create for themselves', () async {
      final e = await _error(
        b.handle(_req('POST', '/tasks', data: body(), userId: _aaravUserId)),
      );
      expect(e.code, 'FORBIDDEN');
      final ok = await b.handle(
        _req(
          'POST',
          '/tasks',
          data: body({'assigneeId': MockSeed.aaravMemberId}),
          userId: _aaravUserId,
        ),
      );
      expect(ok.status, 201);
    });

    test('validation errors → 422 with field details', () async {
      final e = await _error(
        b.handle(
          _req(
            'POST',
            '/tasks',
            data: {
              'title': ' ',
              'assigneeId': '64f1a0000000000000009999',
              'category': 'gardening',
              'dueDate': 'nope',
              'description': 'x' * 1001,
            },
          ),
        ),
      );
      expect(e.status, 422);
      // Like the backend: the body shape first; family membership of the
      // assignee is checked only once the body is valid.
      expect(
        e.details?.keys,
        unorderedEquals(['title', 'category', 'dueDate', 'description']),
      );
      final long = await _error(
        b.handle(_req('POST', '/tasks', data: body({'title': 'x' * 121}))),
      );
      expect(long.details?.keys, ['title']);

      final malformed = await _error(
        b.handle(_req('POST', '/tasks', data: body({'assigneeId': 'Anaya'}))),
      );
      expect(malformed.details?.keys, ['assigneeId']);
      final missing = await _error(
        b.handle(_req('POST', '/tasks', data: body({'assigneeId': null}))),
      );
      expect(missing.details?.keys, ['assigneeId']);
    });

    test(
      'text rules: control characters, invisible titles, UTF-16 length',
      () async {
        final r = await b.handle(
          _req(
            'POST',
            '/tasks',
            data: body({
              'title': ' Buy\tmilk\n\nand eggs ',
              'description': 'Line 1\r\nLine 2\u0000\tend',
            }),
          ),
        );
        final task = r.data! as Map<String, dynamic>;
        expect(task['title'], 'Buy milk and eggs');
        expect(task['description'], 'Line 1\nLine 2\tend');

        final invisible = await _error(
          b.handle(
            _req('POST', '/tasks', data: body({'title': '\u200B\u200D\u00AD'})),
          ),
        );
        expect(invisible.details?.keys, ['title']);
        // RTL text and emoji are fine; 61 emoji = 122 UTF-16 units → too long.
        final rtl = await b.handle(
          _req('POST', '/tasks', data: body({'title': 'اشترِ الحليب 🥛'})),
        );
        expect((rtl.data! as Map)['title'], 'اشترِ الحليب 🥛');
        final emoji = await _error(
          b.handle(_req('POST', '/tasks', data: body({'title': '🧹' * 61}))),
        );
        expect(emoji.details?.keys, ['title']);
      },
    );

    test('an assignee outside the family → 422 details.assigneeId', () async {
      final outsider = await _error(
        b.handle(
          _req(
            'POST',
            '/tasks',
            data: body({'assigneeId': '64f1a0000000000000009999'}),
          ),
        ),
      );
      expect(outsider.status, 422);
      expect(outsider.details?.keys, ['assigneeId']);
      // 422 (not in family) wins over 403 (member assigning someone else).
      final member = await _error(
        b.handle(
          _req(
            'POST',
            '/tasks',
            data: body({'assigneeId': '64f1a0000000000000009999'}),
            userId: _aaravUserId,
          ),
        ),
      );
      expect(member.status, 422);
    });

    test('dueDate: ISO with offset, date-only, 2000–2100, blank', () async {
      Future<Object?> due(Object? value) async {
        final r = await b.handle(
          _req('POST', '/tasks', data: body({'dueDate': value})),
        );
        return (r.data! as Map)['dueDate'];
      }

      expect(
        DateTime.parse((await due('2026-10-01T00:00:00+05:30'))! as String),
        DateTime.utc(2026, 9, 30, 18, 30),
      );
      // Date-only → local midnight of that day (family time zone approx.).
      expect(
        DateTime.parse((await due('2026-10-01'))! as String),
        DateTime(2026, 10, 1).toUtc(),
      );
      expect(await due(''), isNull);
      expect(await due(null), isNull);

      // Local midnight of the first valid day east of UTC (+05:30, +14).
      expect(await due('1999-12-31T18:30:00.000Z'), isNotNull);
      expect(await due('1999-12-31T10:00:00.000Z'), isNotNull);
      expect(await due('2000-01-01'), isNotNull);

      for (final bad in [
        '2026-10-01T10:00:00', // no offset: ambiguous
        '2026-02-31',
        '1999-12-31',
        '1999-12-31T09:59:59Z',
        '2101-01-01T00:00:00Z',
        'tomorrow',
        20261001,
      ]) {
        final e = await _error(
          b.handle(_req('POST', '/tasks', data: body({'dueDate': bad}))),
        );
        expect(e.details?.keys, ['dueDate'], reason: '$bad');
      }
    });
  });

  group('/tasks/:id', () {
    String path(String id, [String suffix = '']) => '/tasks/$id$suffix';

    test('GET one; unknown → 404; malformed id → 400', () async {
      final r = await b.handle(_req('GET', path(MockTaskSeed.tidyRoomId)));
      expect((r.data! as Map)['title'], 'Tidy up your room');
      expect(
        (await _error(
          b.handle(_req('GET', path('64f1a0000000000000009999'))),
        )).status,
        404,
      );
      expect((await _error(b.handle(_req('GET', path('nope'))))).status, 400);
    });

    test('another family\'s task → 404', () async {
      b.db.insert(MockDb.tasks, {
        'id': '64f1a0000000000000009001',
        'familyId': '64f1a0000000000000009000',
        'title': 'Secret',
        'assigneeId': 'x',
        'createdById': 'x',
        'status': 'pending',
      });
      final e = await _error(
        b.handle(_req('GET', path('64f1a0000000000000009001'))),
      );
      expect(e.status, 404);
      final listed = _items(await list({'status': 'all', 'limit': '100'}));
      expect(listed.any((t) => t['title'] == 'Secret'), isFalse);
    });

    test('complete / reopen: idempotent, assignee or admin only', () async {
      const id = MockTaskSeed.mathsHomeworkId; // assigned to Aarav
      final done = await b.handle(
        _req('POST', path(id, '/complete'), userId: _aaravUserId),
      );
      final task = done.data! as Map<String, dynamic>;
      expect(task['status'], 'done');
      expect(task['completedById'], MockSeed.aaravMemberId);
      expect(task['completedAt'], isNotNull);

      final again = await b.handle(
        _req('POST', path(id, '/complete'), userId: _aaravUserId),
      );
      expect((again.data! as Map)['completedAt'], task['completedAt']);

      final reopened = await b.handle(_req('POST', path(id, '/reopen')));
      expect((reopened.data! as Map)['status'], 'pending');
      expect((reopened.data! as Map)['completedById'], isNull);
      final reopenedAgain = await b.handle(_req('POST', path(id, '/reopen')));
      expect((reopenedAgain.data! as Map)['status'], 'pending');

      // Aarav may not complete Kamla's task.
      final e = await _error(
        b.handle(
          _req(
            'POST',
            path(MockTaskSeed.bpTabletId, '/complete'),
            userId: _aaravUserId,
          ),
        ),
      );
      expect(e.code, 'FORBIDDEN');
    });

    test(
      'PATCH: admin or creator; members keep themselves as assignee',
      () async {
        // Created by Priya (admin) for Aarav: Aarav may not edit it.
        final forbidden = await _error(
          b.handle(
            _req(
              'PATCH',
              path(MockTaskSeed.mathsHomeworkId),
              data: {'title': 'Nope'},
              userId: _aaravUserId,
            ),
          ),
        );
        expect(forbidden.code, 'FORBIDDEN');

        final r = await b.handle(
          _req(
            'PATCH',
            path(MockTaskSeed.mathsHomeworkId),
            data: {
              'title': 'Maths homework',
              'dueDate': null,
              'description': null,
              'assigneeId': MockSeed.anayaMemberId,
              'priority': 'low',
            },
          ),
        );
        final task = r.data! as Map<String, dynamic>;
        expect(task['title'], 'Maths homework');
        expect(task['dueDate'], isNull);
        expect(task['description'], isNull);
        expect(task['assigneeName'], 'Anaya');
        expect(task['priority'], 'low');

        // Aarav's own task: may edit, but not hand it to someone else.
        final own = await b.handle(
          _req(
            'POST',
            '/tasks',
            data: {
              'title': 'Mine',
              'assigneeId': MockSeed.aaravMemberId,
              'category': 'skill',
              'priority': 'medium',
            },
            userId: _aaravUserId,
          ),
        );
        final ownId = (own.data! as Map)['id'] as String;
        final moved = await _error(
          b.handle(
            _req(
              'PATCH',
              path(ownId),
              data: {'assigneeId': MockSeed.anayaMemberId},
              userId: _aaravUserId,
            ),
          ),
        );
        expect(moved.code, 'FORBIDDEN');
        final renamed = await b.handle(
          _req(
            'PATCH',
            path(ownId),
            data: {'title': 'Still mine'},
            userId: _aaravUserId,
          ),
        );
        expect((renamed.data! as Map)['title'], 'Still mine');
      },
    );

    test(
      'PATCH check order: 400 id → 422 body → 404 → 403 → assignee',
      () async {
        const unknown = '64f1a0000000000000009999';
        Future<MockException> patch(
          String id,
          Map<String, dynamic> data, {
          String userId = MockSeed.amitUserId,
        }) => _error(
          b.handle(_req('PATCH', path(id), data: data, userId: userId)),
        );

        expect((await patch('nope', {'title': ''})).status, 400);
        expect((await patch(unknown, {'title': ''})).status, 422);
        expect((await patch(unknown, {'title': 'ok'})).status, 404);
        // Not the creator: 403 before looking at the (unknown) assignee.
        final notCreator = await patch(MockTaskSeed.mathsHomeworkId, {
          'assigneeId': unknown,
        }, userId: _aaravUserId);
        expect(notCreator.status, 403);
        // Admin moving a task to someone outside the family.
        final outsider = await patch(MockTaskSeed.mathsHomeworkId, {
          'assigneeId': unknown,
        });
        expect(outsider.status, 422);
        expect(outsider.details?.keys, ['assigneeId']);
      },
    );

    test('PATCH re-sending the current assignee is a no-op, even for a '
        'member-creator of someone else\'s task', () async {
      // Aarav created it (e.g. while he was an admin) for Anaya.
      final task = b.db.insert(MockDb.tasks, {
        'familyId': MockSeed.familyId,
        'title': 'Water the plants',
        'assigneeId': MockSeed.anayaMemberId,
        'createdById': MockSeed.aaravMemberId,
        'category': 'chore',
        'priority': 'low',
        'status': 'pending',
      });
      final r = await b.handle(
        _req(
          'PATCH',
          path(task['id'] as String),
          data: {'assigneeId': MockSeed.anayaMemberId, 'title': 'Water them'},
          userId: _aaravUserId,
        ),
      );
      expect((r.data! as Map)['title'], 'Water them');
      expect((r.data! as Map)['assigneeId'], MockSeed.anayaMemberId);
      // Taking it over is allowed; handing it to someone else is not.
      final mine = await b.handle(
        _req(
          'PATCH',
          path(task['id'] as String),
          data: {'assigneeId': MockSeed.aaravMemberId},
          userId: _aaravUserId,
        ),
      );
      expect((mine.data! as Map)['assigneeId'], MockSeed.aaravMemberId);
    });

    test('a removed assignee: names become null, reopen → 422, re-assign '
        'works', () async {
      // Kamla leaves the family; her done task stays (pending ones would be
      // deleted by the family mock).
      b.db.remove(MockDb.members, MockSeed.kamlaMemberId);
      final got = await b.handle(_req('GET', path(MockTaskSeed.morningWalkId)));
      final task = got.data! as Map<String, dynamic>;
      expect(task['assigneeId'], MockSeed.kamlaMemberId);
      expect(task['assigneeName'], isNull);
      expect(task['createdByName'], 'Amit');

      final reopen = await _error(
        b.handle(_req('POST', path(MockTaskSeed.morningWalkId, '/reopen'))),
      );
      expect(reopen.status, 422);
      expect(reopen.details?.keys, ['assigneeId']);

      // Editing other fields while keeping the former assignee works.
      final edited = await b.handle(
        _req(
          'PATCH',
          path(MockTaskSeed.morningWalkId),
          data: {'title': 'Evening walk', 'assigneeId': MockSeed.kamlaMemberId},
        ),
      );
      expect((edited.data! as Map)['title'], 'Evening walk');

      await b.handle(
        _req(
          'PATCH',
          path(MockTaskSeed.morningWalkId),
          data: {'assigneeId': MockSeed.priyaMemberId},
        ),
      );
      final reopened = await b.handle(
        _req('POST', path(MockTaskSeed.morningWalkId, '/reopen')),
      );
      expect((reopened.data! as Map)['status'], 'pending');
      expect((reopened.data! as Map)['assigneeName'], 'Priya');
    });

    test('a renamed member shows the current name', () async {
      b.db.update(MockDb.members, MockSeed.aaravMemberId, {'name': 'Aaru'});
      final r = await b.handle(_req('GET', path(MockTaskSeed.mathsHomeworkId)));
      expect((r.data! as Map)['assigneeName'], 'Aaru');
    });

    test('DELETE: admin or creator', () async {
      final e = await _error(
        b.handle(
          _req(
            'DELETE',
            path(MockTaskSeed.mathsHomeworkId),
            userId: _aaravUserId,
          ),
        ),
      );
      expect(e.code, 'FORBIDDEN');
      final r = await b.handle(_req('DELETE', path(MockTaskSeed.tidyRoomId)));
      expect(r.status, 200);
      expect(r.data, isNull);
      expect(
        (await _error(
          b.handle(_req('GET', path(MockTaskSeed.tidyRoomId))),
        )).status,
        404,
      );
    });
  });

  test('mockTaskJson: current names, null for members who left', () {
    final json = mockTaskJson(b.db, {
      'id': '1',
      'familyId': MockSeed.familyId,
      'assigneeId': 'gone',
      'assigneeName': 'Old Name',
      'createdById': MockSeed.amitMemberId,
      'createdByName': 'Stale',
    });
    expect(json['assigneeName'], isNull, reason: 'like the backend');
    expect(json['createdByName'], 'Amit');
    expect(json['category'], 'other');
    expect(json['status'], 'pending');
  });
}
