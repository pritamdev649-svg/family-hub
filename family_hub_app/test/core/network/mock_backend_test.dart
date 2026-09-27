import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/network/mock/mock_backend.dart';

RequestOptions _req(
  String method,
  String path, {
  Object? data,
  Map<String, dynamic>? query,
  String? token,
}) => RequestOptions(
  method: method,
  baseUrl: MockBackend.baseUrl,
  path: path,
  data: data,
  queryParameters: query,
  headers: {if (token != null) 'Authorization': 'Bearer $token'},
);

Future<MockException> _error(Future<Object?> f) async {
  try {
    await f;
  } on MockException catch (e) {
    return e;
  }
  fail('expected a MockException');
}

void main() {
  group('MockBackend routing', () {
    late MockBackend b;

    setUp(() => b = MockBackend(MockDb(seedCore: false)));

    test('matches literal routes and extracts :params (URL-decoded)', () async {
      b.on('GET', '/tasks', (r) => const MockResponse.ok('list'));
      b.on(
        'POST',
        '/tasks/:id/complete',
        (r) => MockResponse.ok({'id': r.param('id')}),
      );
      b.on(
        'DELETE',
        '/me/devices/:token',
        (r) => MockResponse.ok(r.pathParams['token']),
      );

      expect((await b.handle(_req('GET', '/tasks'))).data, 'list');
      expect((await b.handle(_req('POST', '/tasks/abc123/complete'))).data, {
        'id': 'abc123',
      });
      final token = Uri.encodeComponent('fcm:tok/en');
      expect(
        (await b.handle(_req('DELETE', '/me/devices/$token'))).data,
        'fcm:tok/en',
      );
    });

    test('unknown path → 404 NOT_FOUND', () async {
      b.on('GET', '/tasks', (r) => const MockResponse.ok());
      final e = await _error(b.handle(_req('GET', '/nope')));
      expect(e.status, 404);
      expect(e.code, 'NOT_FOUND');
    });

    test('known path with other method → 404 (like Express)', () async {
      b.on('GET', '/tasks/:id', (r) => const MockResponse.ok());
      final e = await _error(b.handle(_req('PUT', '/tasks/1')));
      expect(e.status, 404);
    });

    test('segment count must match; empty param never matches', () async {
      b.on('GET', '/tasks/:id', (r) => const MockResponse.ok());
      expect((await _error(b.handle(_req('GET', '/tasks/1/x')))).status, 404);
      expect((await _error(b.handle(_req('GET', '/tasks/')))).status, 404);
    });

    test('literal segments win over params regardless of order', () async {
      b.on('GET', '/sos/:id', (r) => const MockResponse.ok('byId'));
      b.on('GET', '/sos/active', (r) => const MockResponse.ok('active'));
      expect((await b.handle(_req('GET', '/sos/active'))).data, 'active');
      expect((await b.handle(_req('GET', '/sos/42'))).data, 'byId');
    });

    test('re-registering a route replaces the handler', () async {
      b.on('GET', '/x', (r) => const MockResponse.ok(1));
      b.on('get', '/x/', (r) => const MockResponse.ok(2));
      expect(b.routes, ['GET /x']);
      expect((await b.handle(_req('GET', '/x'))).data, 2);
    });

    test('strips /api/v1 and trailing slashes; method case-insensitive', () {
      expect(
        MockBackend.relativePath(Uri.parse('${MockBackend.baseUrl}/tasks/')),
        '/tasks',
      );
      expect(
        MockBackend.relativePath(Uri.parse('http://x/api/v1/family/members')),
        '/family/members',
      );
      expect(MockBackend.relativePath(Uri.parse('http://x/api/v1')), '/');
    });

    test('passes query (strings) and a JSON-copied body', () async {
      late MockRequest seen;
      b.on('POST', '/echo', (r) {
        seen = r;
        return const MockResponse.ok();
      });
      final body = {
        'a': 1,
        'nested': {'b': true},
      };
      await b.handle(_req('POST', '/echo', data: body, query: {'page': 2}));
      expect(seen.query, {'page': '2'});
      expect(seen.body, body);
      (seen.body['nested'] as Map)['b'] = false;
      expect(body['nested'], {'b': true}, reason: 'body is a copy');
    });

    test('string JSON body is decoded; malformed → 400 BAD_REQUEST', () async {
      b.on('POST', '/echo', (r) => MockResponse.ok(r.body));
      expect((await b.handle(_req('POST', '/echo', data: '{"x":1}'))).data, {
        'x': 1,
      });
      final e = await _error(b.handle(_req('POST', '/echo', data: '{oops')));
      expect(e.code, 'BAD_REQUEST');
      final list = await _error(b.handle(_req('POST', '/echo', data: [1])));
      expect(list.code, 'BAD_REQUEST');
    });
  });

  group('MockRequest auth helpers', () {
    late MockBackend b;

    setUp(() {
      b = MockBackend();
      b.on('GET', '/me-user', (r) => MockResponse.ok(r.requireUser()['id']));
      b.on(
        'GET',
        '/me-member',
        (r) => MockResponse.ok(r.requireMember()['id']),
      );
      b.on('GET', '/admin', (r) => MockResponse.ok(r.requireAdmin()['id']));
      b.on('GET', '/is-admin', (r) => MockResponse.ok(r.isAdmin));
    });

    test('missing / malformed / unknown token → 401 UNAUTHORIZED', () async {
      for (final token in [
        null,
        'garbage',
        'mock-access.',
        'mock-access.nobody',
      ]) {
        final e = await _error(b.handle(_req('GET', '/me-user', token: token)));
        expect(e.status, 401, reason: 'token=$token');
        expect(e.code, 'UNAUTHORIZED');
      }
      final lower = RequestOptions(
        method: 'GET',
        baseUrl: MockBackend.baseUrl,
        path: '/me-user',
        headers: {'authorization': 'bearer mock-access.${MockSeed.amitUserId}'},
      );
      expect((await b.handle(lower)).data, MockSeed.amitUserId);
    });

    test('requireMember / requireAdmin / isAdmin', () async {
      final amit = MockRequest.accessTokenFor(MockSeed.amitUserId);
      expect(
        (await b.handle(_req('GET', '/me-member', token: amit))).data,
        MockSeed.amitMemberId,
      );
      expect(
        (await b.handle(_req('GET', '/is-admin', token: amit))).data,
        true,
      );

      // Demote Amit's member → FORBIDDEN on admin routes.
      b.db.update(MockDb.members, MockSeed.amitMemberId, {'role': 'member'});
      final e = await _error(b.handle(_req('GET', '/admin', token: amit)));
      expect(e.code, 'FORBIDDEN');
      expect(
        (await b.handle(_req('GET', '/is-admin', token: amit))).data,
        false,
      );
    });

    test('user without family → 403 NO_FAMILY', () async {
      final user = b.db.insert(MockDb.users, {
        'email': 'solo@x.io',
        'familyId': null,
        'memberId': null,
      });
      final e = await _error(
        b.handle(
          _req(
            'GET',
            '/me-member',
            token: MockRequest.accessTokenFor(user['id']),
          ),
        ),
      );
      expect(e.status, 403);
      expect(e.code, 'NO_FAMILY');
    });

    test('findInFamily hides other families (404)', () async {
      final other = b.db.insert(MockDb.tasks, {
        'familyId': 'other',
        'title': 'x',
      });
      final mine = b.db.insert(MockDb.tasks, {
        'familyId': MockSeed.familyId,
        'title': 'y',
      });
      b.on(
        'GET',
        '/tasks/:id',
        (r) => MockResponse.ok(r.findInFamily(MockDb.tasks, r.param('id'))),
      );
      final token = MockRequest.accessTokenFor(MockSeed.priyaUserId);
      final ok = await b.handle(
        _req('GET', '/tasks/${mine['id']}', token: token),
      );
      expect((ok.data as Map)['title'], 'y');
      final e = await _error(
        b.handle(_req('GET', '/tasks/${other['id']}', token: token)),
      );
      expect(e.code, 'NOT_FOUND');
    });

    test('refresh token helpers', () {
      final db = MockDb(seedCore: false);
      final t = MockRequest.refreshTokenFor(db, 'u1');
      expect(t, startsWith('mock-refresh.u1.'));
      expect(MockRequest.userIdFromRefreshToken(t), 'u1');
      expect(MockRequest.userIdFromRefreshToken('nope'), isNull);
      expect(MockRequest.userIdFromRefreshToken(null), isNull);
    });
  });

  group('MockResponse.paged', () {
    final items = List.generate(45, (i) => i);
    MockRequest req(Map<String, String> q) => MockRequest(
      method: 'GET',
      path: '/x',
      pathParams: const {},
      query: q,
      body: const {},
      db: MockDb(seedCore: false),
    );

    test('slices and sets meta', () {
      final first = MockResponse.paged(items, req(const {}));
      expect((first.data as List).length, 20);
      expect(first.meta, {
        'page': 1,
        'limit': 20,
        'total': 45,
        'hasMore': true,
      });
      final last = MockResponse.paged(items, req({'page': '3', 'limit': '20'}));
      expect(last.data, [40, 41, 42, 43, 44]);
      expect(last.meta!['hasMore'], false);
      final beyond = MockResponse.paged(items, req({'page': '9'}));
      expect(beyond.data, isEmpty);
      expect(beyond.meta!['hasMore'], false);
    });

    test('invalid page/limit → 422 VALIDATION_ERROR', () {
      for (final q in [
        {'page': '0'},
        {'limit': '101'},
        {'limit': 'x'},
      ]) {
        expect(
          () => MockResponse.paged(items, req(q)),
          throwsA(
            isA<MockException>().having(
              (e) => e.code,
              'code',
              'VALIDATION_ERROR',
            ),
          ),
        );
      }
    });
  });

  group('MockDb', () {
    test('newId is 24 lowercase hex and unique', () {
      final db = MockDb(seedCore: false);
      final ids = {for (var i = 0; i < 500; i++) db.newId()};
      expect(ids.length, 500);
      expect(ids.every(RegExp(r'^[0-9a-f]{24}$').hasMatch), isTrue);
    });

    test('nowIso has millisecond precision and Z suffix', () {
      expect(
        MockDb(seedCore: false).nowIso(),
        matches(RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$')),
      );
    });

    test('reads are deep copies; writes go through helpers', () {
      final db = MockDb(seedCore: false);
      final inserted = db.insert('things', {
        'name': 'a',
        'tags': ['x'],
      });
      expect(inserted['id'], isA<String>());
      expect(inserted['createdAt'], isA<String>());

      final read = db.findById('things', inserted['id'])!;
      read['name'] = 'mutated';
      (read['tags'] as List).add('y');
      db.col('things').first['name'] = 'mutated too';
      expect(db.findById('things', inserted['id'])!['name'], 'a');
      expect(db.findById('things', inserted['id'])!['tags'], ['x']);

      final updated = db.update('things', inserted['id'], {
        'name': 'b',
        'id': 'hijack',
      })!;
      expect(updated['name'], 'b');
      expect(updated['id'], inserted['id'], reason: 'ids are immutable');
      expect(db.update('things', 'missing', {'a': 1}), isNull);

      expect(db.count('things'), 1);
      expect(db.remove('things', inserted['id']), isTrue);
      expect(db.remove('things', inserted['id']), isFalse);
    });

    test('where / findOne / updateWhere / removeWhere', () {
      final db = MockDb(seedCore: false);
      for (var i = 0; i < 5; i++) {
        db.insert('n', {'v': i});
      }
      expect(db.where('n', (d) => (d['v'] as int).isEven).length, 3);
      expect(db.findOne('n', (d) => d['v'] == 3)!['v'], 3);
      expect(db.updateWhere('n', (d) => d['v'] == 1, {'v': 10}), 1);
      expect(db.exists('n', (d) => d['v'] == 10), isTrue);
      expect(db.removeWhere('n', (d) => (d['v'] as int) > 3), 2);
      expect(db.count('n'), 3);
    });

    test('seedOnce seeds a collection only once', () {
      final db = MockDb(seedCore: false);
      var calls = 0;
      List<Map<String, dynamic>> seed() {
        calls++;
        return [
          {'title': 'x'},
        ];
      }

      db.seedOnce('notes', seed);
      db.seedOnce('notes', seed);
      expect(calls, 1);
      expect(db.count('notes'), 1);
      expect(db.col('notes').single['id'], isA<String>());
    });

    test('core seed: Sharma family, demo users and five members', () {
      final db = MockDb();
      final family = db.findById(MockDb.families, MockSeed.familyId)!;
      expect(family['name'], 'Sharma Family');
      expect(family['inviteCode'], 'DEMO2345');
      expect(family['country'], 'IN');
      expect(family['currency'], 'INR');
      expect(family['timezone'], 'Asia/Kolkata');

      final demo = db.findOne(
        MockDb.users,
        (u) => u['email'] == MockSeed.demoEmail,
      )!;
      expect(demo['password'], 'demo1234');
      expect(demo['emailVerified'], isTrue);
      expect(demo['memberId'], MockSeed.amitMemberId);
      expect(
        db.findOne(MockDb.users, (u) => u['email'] == MockSeed.priyaEmail),
        isNotNull,
      );

      final members = MockSerializers.members(db, MockSeed.familyId);
      expect(members.map((m) => m['name']), [
        'Amit',
        'Priya',
        'Kamla',
        'Aarav',
        'Anaya',
      ]);
      final byName = {for (final m in members) m['name']: m};
      expect(byName['Amit']!['designation'], 'Head of Family');
      expect(byName['Priya']!['designation'], 'Finance Head');
      expect(byName['Kamla']!['designation'], 'Advisor');
      expect(byName['Anaya']!['hasAccount'], isFalse);
      expect(byName['Kamla']!['hasAccount'], isFalse);
      expect(byName['Amit']!['hasAccount'], isTrue);
      expect(
        DateTime.parse(byName['Aarav']!['dateOfBirth']).toLocal().year,
        2010,
      );
      // Privacy: lastLocation only for `always` sharers.
      expect(byName['Amit']!['lastLocation'], isNotNull);
      expect(byName['Priya']!['lastLocation'], isNull);
    });

    test('serializers: invite code only for admins, user role from member', () {
      final db = MockDb();
      final family = db.findById(MockDb.families, MockSeed.familyId)!;
      expect(
        MockSerializers.family(db, family, isAdmin: true)['inviteCode'],
        'DEMO2345',
      );
      final forMember = MockSerializers.family(db, family, isAdmin: false);
      expect(forMember['inviteCode'], isNull);
      expect(forMember['memberCount'], 5);

      final user = db.findById(MockDb.users, MockSeed.amitUserId)!;
      final json = MockSerializers.user(db, user);
      expect(json.containsKey('password'), isFalse);
      expect(json['role'], 'admin');

      final session = MockSerializers.session(db, user);
      expect((session['family'] as Map)['inviteCode'], 'DEMO2345');
      expect(MockSerializers.memberName(db, MockSeed.aaravMemberId), 'Aarav');
      expect(MockSerializers.memberName(db, 'nope'), '');
    });
  });

  group('MockTokens', () {
    test('issue / rotate / reuse detection / revoke', () {
      final db = MockDb();
      final first = MockTokens.issue(db, MockSeed.amitUserId);
      expect(first['accessToken'], 'mock-access.${MockSeed.amitUserId}');
      expect(
        first['refreshToken'],
        startsWith('mock-refresh.${MockSeed.amitUserId}.'),
      );
      expect(first['expiresIn'], 900);

      final second = MockTokens.rotate(db, first['refreshToken']);
      expect(second['refreshToken'], isNot(first['refreshToken']));

      // Reusing the rotated (revoked) token revokes everything.
      expect(
        () => MockTokens.rotate(db, first['refreshToken']),
        throwsA(
          isA<MockException>().having(
            (e) => e.code,
            'code',
            'INVALID_REFRESH_TOKEN',
          ),
        ),
      );
      expect(
        () => MockTokens.rotate(db, second['refreshToken']),
        throwsA(isA<MockException>().having((e) => e.status, 'status', 401)),
      );

      final third = MockTokens.issue(db, MockSeed.priyaUserId);
      MockTokens.revoke(db, third['refreshToken']);
      expect(
        () => MockTokens.rotate(db, third['refreshToken']),
        throwsA(isA<MockException>()),
      );
      expect(
        () => MockTokens.rotate(db, 'garbage'),
        throwsA(isA<MockException>()),
      );
      expect(() => MockTokens.rotate(db, null), throwsA(isA<MockException>()));
    });
  });
}
