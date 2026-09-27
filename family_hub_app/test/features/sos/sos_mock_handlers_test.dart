import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/network/mock/mock_backend.dart';
import 'package:family_hub/features/sos/data/sos_mock_handlers.dart';

/// Contract rules of the `/sos` mock (docs/03-API_CONTRACT.md §10) on the
/// core demo seed: Amit (admin, shares `always`), Priya (admin, `sos_only`),
/// Kamla (member, `never`, given an account here).
void main() {
  late MockBackend b;
  late MockDb db;

  const kamlaUserId = '64f1a0000000000000000199';
  const otherFamilyUserId = '64f1a0000000000000000198';
  const otherMemberId = '64f1a0000000000000000298';

  setUp(() {
    db = MockDb();
    b = MockBackend(db);
    registerSosMocks(b);
    db.insert(MockDb.users, {
      'id': kamlaUserId,
      'email': 'kamla@familyhub.app',
      'name': 'Kamla',
      'familyId': MockSeed.familyId,
      'memberId': MockSeed.kamlaMemberId,
      'emailVerified': true,
    });
    db.update(MockDb.members, MockSeed.kamlaMemberId, {'userId': kamlaUserId});
    // A member of another family.
    db.insert(MockDb.families, {'id': 'ffffffffffffffffffffffff', 'name': 'X'});
    db.insert(MockDb.members, {
      'id': otherMemberId,
      'familyId': 'ffffffffffffffffffffffff',
      'userId': otherFamilyUserId,
      'name': 'Stranger',
      'role': 'admin',
      'locationSharing': 'sos_only',
    });
    db.insert(MockDb.users, {
      'id': otherFamilyUserId,
      'email': 'x@example.com',
      'name': 'Stranger',
      'familyId': 'ffffffffffffffffffffffff',
      'memberId': otherMemberId,
    });
  });

  Future<MockResponse> call(
    String method,
    String path, {
    String? as = MockSeed.priyaUserId,
    Object? body,
    Map<String, dynamic>? query,
  }) => b.handle(
    RequestOptions(
      method: method,
      baseUrl: MockBackend.baseUrl,
      path: path,
      data: body,
      queryParameters: query,
      headers: {
        if (as != null)
          'Authorization': 'Bearer ${MockRequest.accessTokenFor(as)}',
      },
    ),
  );

  Future<MockException> error(Future<Object?> f) async {
    try {
      await f;
    } on MockException catch (e) {
      return e;
    }
    fail('expected a MockException');
  }

  Map<String, dynamic> data(MockResponse r) =>
      (r.data! as Map).cast<String, dynamic>();

  List<Map<String, dynamic>> list(MockResponse r) => [
    for (final e in r.data! as List) (e as Map).cast<String, dynamic>(),
  ];

  const here = {'lat': 28.6, 'lng': 77.2, 'accuracy': 12};

  /// Moves the last trail point of [id] into the past, so the next
  /// location update is not throttled.
  void ageLastPoint(String id, Duration by) {
    final doc = db.findById(MockDb.sosAlerts, id)!;
    final trail = [...doc['trail'] as List];
    final last = Map<String, dynamic>.from(trail.last as Map);
    final at = DateTime.parse(last['recordedAt'] as String).subtract(by);
    last['recordedAt'] = MockDb.iso(at);
    trail[trail.length - 1] = last;
    db.update(MockDb.sosAlerts, id, {'trail': trail, 'lastLocation': last});
  }

  group('seed', () {
    test('no active alert, one resolved alert in the history', () async {
      expect(list(await call('GET', '/sos/active')), isEmpty);
      final history = await call('GET', '/sos/history');
      final items = list(history);
      expect(items, hasLength(1));
      expect(items.single['id'], mockSeededSosAlertId);
      expect(items.single['status'], 'resolved');
      expect(items.single['resolution'], 'safe');
      expect(items.single['memberName'], 'Priya');
      expect(items.single['trail'], isEmpty, reason: 'lists carry no trail');
      expect(history.meta?['total'], 1);
    });

    test('GET /sos/:id includes the trail, oldest first', () async {
      final a = data(await call('GET', '/sos/$mockSeededSosAlertId'));
      final trail = (a['trail'] as List).cast<Map<String, dynamic>>();
      expect(trail, hasLength(4));
      final times = trail.map((p) => p['recordedAt'] as String).toList();
      expect(times, [...times]..sort());
    });
  });

  group('POST /sos', () {
    test('creates (201) and is idempotent (200, same alert)', () async {
      final first = await call('POST', '/sos', body: {'location': here});
      expect(first.status, 201);
      final a = data(first);
      expect(a['status'], 'active');
      expect(a['memberId'], MockSeed.priyaMemberId);
      expect(a['memberPhone'], '+919876543211');
      expect(a['locationShared'], isTrue);
      expect((a['lastLocation'] as Map)['lat'], 28.6);
      final started = DateTime.parse(a['startedAt'] as String);
      final expires = DateTime.parse(a['expiresAt'] as String);
      expect(expires.difference(started), const Duration(minutes: 15));

      final again = await call('POST', '/sos', body: {'message': 'ignored'});
      expect(again.status, 200);
      expect(data(again)['id'], a['id']);
      expect(data(again)['message'], isNull);
      expect(db.count(MockDb.sosAlerts, (d) => d['status'] == 'active'), 1);
    });

    test('mode never drops the location', () async {
      final a = data(
        await call('POST', '/sos', as: kamlaUserId, body: {'location': here}),
      );
      expect(a['locationShared'], isFalse);
      expect(a['lastLocation'], isNull);
      final stored = db.findById(MockDb.sosAlerts, a['id'])!;
      expect(stored['trail'], isEmpty);
    });

    test('validates location and message', () async {
      final e = await error(
        call(
          'POST',
          '/sos',
          body: {
            'location': {'lat': 91, 'lng': '77'},
            'message': 'x' * 141,
          },
        ),
      );
      expect(e.status, 422);
      expect(e.details?.keys, containsAll(['location.lat', 'location.lng']));
      expect(e.details?.keys, contains('message'));
      expect(db.count(MockDb.sosAlerts), 1, reason: 'nothing written');
    });

    test('a blank message is stored as null', () async {
      final a = data(await call('POST', '/sos', body: {'message': '   '}));
      expect(a['message'], isNull);
    });

    test('401 without token', () async {
      final e = await error(call('POST', '/sos', as: null));
      expect(e.status, 401);
    });
  });

  group('POST /sos/:id/location', () {
    late String id;

    setUp(() async {
      id =
          data(await call('POST', '/sos', body: {'location': here}))['id']
              as String;
    });

    test('stores points, throttles < 3 s, returns no trail', () async {
      // Right after the create: throttled (accepted, not stored).
      final throttled = await call(
        'POST',
        '/sos/$id/location',
        body: {'lat': 28.7, 'lng': 77.3},
      );
      expect(data(throttled)['trail'], isEmpty);
      expect(
        (db.findById(MockDb.sosAlerts, id)!['trail'] as List),
        hasLength(1),
      );

      ageLastPoint(id, const Duration(seconds: 5));
      final stored = await call(
        'POST',
        '/sos/$id/location',
        body: {'lat': 28.7, 'lng': 77.3, 'accuracy': 5},
      );
      expect((data(stored)['lastLocation'] as Map)['lat'], 28.7);
      expect(
        (db.findById(MockDb.sosAlerts, id)!['trail'] as List),
        hasLength(2),
      );
    });

    test('keeps at most 100 trail points', () async {
      final old = MockDb.iso(DateTime.now().subtract(const Duration(hours: 1)));
      db.update(MockDb.sosAlerts, id, {
        'trail': [
          for (var i = 0; i < 100; i++)
            {'lat': 1.0, 'lng': 1.0, 'accuracy': null, 'recordedAt': old},
        ],
      });
      await call('POST', '/sos/$id/location', body: {'lat': 2, 'lng': 2});
      final trail = db.findById(MockDb.sosAlerts, id)!['trail'] as List;
      expect(trail, hasLength(100));
      expect((trail.last as Map)['lat'], 2.0);
      final full = data(await call('GET', '/sos/$id'));
      expect(full['trail'] as List, hasLength(100));
    });

    test('only the owner may post (admins included → 403)', () async {
      final e = await error(
        call('POST', '/sos/$id/location', as: MockSeed.amitUserId, body: here),
      );
      expect(e.status, 403);
      expect(e.code, 'FORBIDDEN');
    });

    test('409 SOS_NOT_ACTIVE after resolve', () async {
      await call('POST', '/sos/$id/resolve', body: {'resolution': 'safe'});
      final e = await error(call('POST', '/sos/$id/location', body: here));
      expect(e.status, 409);
      expect(e.code, 'SOS_NOT_ACTIVE');
    });

    test('403 LOCATION_SHARING_DISABLED when the mode is never', () async {
      db.update(MockDb.members, MockSeed.priyaMemberId, {
        'locationSharing': 'never',
      });
      final e = await error(call('POST', '/sos/$id/location', body: here));
      expect(e.status, 403);
      expect(e.code, 'LOCATION_SHARING_DISABLED');
      // Consent withdrawn: the stored points are hidden.
      final a = data(await call('GET', '/sos/$id'));
      expect(a['locationShared'], isFalse);
      expect(a['lastLocation'], isNull);
      expect(a['trail'], isEmpty);
    });

    test('404 for another family, 400 for a malformed id', () async {
      final e404 = await error(
        call('POST', '/sos/$id/location', as: otherFamilyUserId, body: here),
      );
      expect(e404.status, 404);
      final e400 = await error(call('POST', '/sos/nope/location', body: here));
      expect(e400.status, 400);
    });

    test('422 for invalid coordinates', () async {
      final e = await error(
        call('POST', '/sos/$id/location', body: {'lat': 12}),
      );
      expect(e.status, 422);
      expect(e.details?.keys, contains('lng'));
    });
  });

  group('POST /sos/:id/resolve', () {
    late String id;

    setUp(() async {
      id = data(await call('POST', '/sos'))['id'] as String;
    });

    test('owner resolves; repeat is idempotent (first wins)', () async {
      final r = data(
        await call('POST', '/sos/$id/resolve', body: {'resolution': 'safe'}),
      );
      expect(r['status'], 'resolved');
      expect(r['resolution'], 'safe');
      expect(r['resolvedById'], MockSeed.priyaMemberId);
      final again = data(
        await call(
          'POST',
          '/sos/$id/resolve',
          as: MockSeed.amitUserId,
          body: {'resolution': 'helped'},
        ),
      );
      expect(again['resolution'], 'safe');
      expect(list(await call('GET', '/sos/active')), isEmpty);
    });

    test('an admin may resolve as helped; a member may not', () async {
      final e = await error(
        call(
          'POST',
          '/sos/$id/resolve',
          as: kamlaUserId,
          body: {'resolution': 'safe'},
        ),
      );
      expect(e.status, 403);
      final r = data(
        await call(
          'POST',
          '/sos/$id/resolve',
          as: MockSeed.amitUserId,
          body: {'resolution': 'helped'},
        ),
      );
      expect(r['resolution'], 'helped');
      expect(r['resolvedById'], MockSeed.amitMemberId);
    });

    test('validates the resolution', () async {
      final e = await error(
        call('POST', '/sos/$id/resolve', body: {'resolution': 'maybe'}),
      );
      expect(e.status, 422);
      expect(e.details?.keys, contains('resolution'));
    });

    test('an expired alert answers 409', () async {
      final past = DateTime.now().subtract(const Duration(minutes: 1));
      db.update(MockDb.sosAlerts, id, {'expiresAt': MockDb.iso(past)});
      final e = await error(
        call('POST', '/sos/$id/resolve', body: {'resolution': 'safe'}),
      );
      expect(e.code, 'SOS_NOT_ACTIVE');
    });
  });

  group('lazy expiry & listing', () {
    test('an alert past expiresAt moves to the history as expired', () async {
      final id = data(await call('POST', '/sos'))['id'] as String;
      expect(list(await call('GET', '/sos/active')), hasLength(1));
      db.update(MockDb.sosAlerts, id, {
        'expiresAt': MockDb.iso(
          DateTime.now().subtract(const Duration(seconds: 1)),
        ),
      });
      expect(list(await call('GET', '/sos/active')), isEmpty);
      expect(db.findById(MockDb.sosAlerts, id)!['status'], 'expired');
      final history = list(await call('GET', '/sos/history'));
      expect(history.first['id'], id, reason: 'newest first');
      expect(history.first['status'], 'expired');
      // A new alert can be raised afterwards.
      final next = await call('POST', '/sos');
      expect(next.status, 201);
    });

    test('active lists every member of the family, newest first', () async {
      await call('POST', '/sos');
      await call('POST', '/sos', as: MockSeed.amitUserId);
      final active = list(await call('GET', '/sos/active', as: kamlaUserId));
      expect(active, hasLength(2));
      expect(active.map((a) => a['memberId']).toSet(), {
        MockSeed.priyaMemberId,
        MockSeed.amitMemberId,
      });
      // Another family sees none of them.
      expect(
        list(await call('GET', '/sos/active', as: otherFamilyUserId)),
        isEmpty,
      );
      expect(mockActiveSosAlerts(db, MockSeed.familyId), hasLength(2));
    });

    test('history pagination', () async {
      for (var i = 0; i < 3; i++) {
        final id = data(await call('POST', '/sos'))['id'] as String;
        await call('POST', '/sos/$id/resolve', body: {'resolution': 'safe'});
      }
      final page = await call(
        'GET',
        '/sos/history',
        query: {'page': '2', 'limit': '2'},
      );
      expect(list(page), hasLength(2));
      expect(page.meta, {'page': 2, 'limit': 2, 'total': 4, 'hasMore': false});
      final e = await error(
        call('GET', '/sos/history', query: {'limit': '101'}),
      );
      expect(e.status, 422);
    });

    test('a removed member has no name any more', () async {
      final id = data(await call('POST', '/sos'))['id'] as String;
      db.remove(MockDb.members, MockSeed.priyaMemberId);
      final a = data(await call('GET', '/sos/$id', as: MockSeed.amitUserId));
      expect(a['memberName'], isNull);
      expect(a['locationShared'], isFalse);
    });
  });
}
