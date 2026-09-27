import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/network/mock/mock_backend.dart';
import 'package:family_hub/features/settings/data/settings_mock_handlers.dart';

RequestOptions _req(
  String method,
  String path, {
  Object? data,
  String? token,
}) => RequestOptions(
  method: method,
  baseUrl: MockBackend.baseUrl,
  path: path,
  data: data,
  headers: {if (token != null) 'Authorization': 'Bearer $token'},
);

final _amit = MockRequest.accessTokenFor(MockSeed.amitUserId);
final _priya = MockRequest.accessTokenFor(MockSeed.priyaUserId);

Future<MockException> _error(Future<Object?> f) async {
  try {
    await f;
  } on MockException catch (e) {
    return e;
  }
  fail('expected a MockException');
}

void main() {
  late MockBackend b;
  late MockDb db;

  Future<Object?> call(
    String method,
    String path, {
    Object? data,
    String? token,
  }) async =>
      (await b.handle(_req(method, path, data: data, token: token))).data;

  Map<String, dynamic> member(String id) => db.findById(MockDb.members, id)!;

  setUp(() {
    db = MockDb();
    b = MockBackend(db);
    registerMeMocks(b);
    registerUploadMocks(b);
  });

  group('PATCH /me', () {
    test('updates account + profile and returns contract shapes', () async {
      final res =
          await call(
                'PATCH',
                '/me',
                token: _amit,
                data: {
                  'name': '  Amit Kumar ',
                  'phone': '+91 98765-00000',
                  'locale': 'hi',
                  'gender': null,
                  'dateOfBirth': '1985-01-31T18:30:00.000Z',
                },
              )
              as Map<String, dynamic>;

      final user = res['user'] as Map<String, dynamic>;
      final m = res['member'] as Map<String, dynamic>;
      expect(user['name'], 'Amit Kumar');
      expect(user['locale'], 'hi');
      expect(user.containsKey('password'), isFalse);
      expect(m['name'], 'Amit Kumar');
      expect(m['phone'], '+919876500000');
      expect(m['gender'], isNull);
      expect(m['dateOfBirth'], '1985-01-31T18:30:00.000Z');
      expect(m['hasAccount'], isTrue);
    });

    test(
      'validation: unknown fields, bad phone, locale, mode, gender, DOB',
      () async {
        final e = await _error(
          call(
            'PATCH',
            '/me',
            token: _amit,
            data: {
              'role': 'admin',
              'phone': 'call me',
              'locale': 'xx',
              'locationSharing': 'sometimes',
              'gender': 'robot',
              'dateOfBirth': '2999-01-01T00:00:00.000Z',
              'name': '',
            },
          ),
        );
        expect(e.status, 422);
        expect(e.code, 'VALIDATION_ERROR');
        expect(
          (e.details ?? const {}).keys,
          containsAll([
            'role',
            'phone',
            'locale',
            'locationSharing',
            'gender',
            'dateOfBirth',
            'name',
          ]),
        );
        expect(member(MockSeed.amitMemberId)['phone'], '+919876543210');
      },
    );

    test('avatarUrl: Cloudinary or local mock path only', () async {
      final bad = await _error(
        call(
          'PATCH',
          '/me',
          token: _amit,
          data: {'avatarUrl': 'https://evil.example.com/a.jpg'},
        ),
      );
      expect(bad.code, 'VALIDATION_ERROR');

      const cloud = 'https://res.cloudinary.com/demo/image/upload/a.jpg';
      await call('PATCH', '/me', token: _amit, data: {'avatarUrl': cloud});
      expect(member(MockSeed.amitMemberId)['avatarUrl'], cloud);

      const local = '/data/user/0/app/cache/image_picker_1.jpg';
      await call('PATCH', '/me', token: _amit, data: {'avatarUrl': local});
      expect(member(MockSeed.amitMemberId)['avatarUrl'], local);

      await call('PATCH', '/me', token: _amit, data: {'avatarUrl': null});
      expect(member(MockSeed.amitMemberId)['avatarUrl'], isNull);
    });

    test('leaving "always" clears the last location (privacy)', () async {
      expect(member(MockSeed.amitMemberId)['lastLocation'], isNotNull);
      final res =
          await call(
                'PATCH',
                '/me',
                token: _amit,
                data: {'locationSharing': 'sos_only'},
              )
              as Map<String, dynamic>;
      expect((res['member'] as Map)['locationSharing'], 'sos_only');
      expect(member(MockSeed.amitMemberId)['lastLocation'], isNull);
    });

    test(
      'member fields without a family → NO_FAMILY; name still works',
      () async {
        db.update(MockDb.users, MockSeed.priyaUserId, {
          'familyId': null,
          'memberId': null,
        });
        final e = await _error(
          call('PATCH', '/me', token: _priya, data: {'phone': '+911234567'}),
        );
        expect(e.code, 'NO_FAMILY');

        final res =
            await call('PATCH', '/me', token: _priya, data: {'name': 'P'})
                as Map<String, dynamic>;
        expect((res['user'] as Map)['name'], 'P');
        expect(res['member'], isNull);
      },
    );

    test('requires authentication', () async {
      final e = await _error(call('PATCH', '/me', data: {'name': 'x'}));
      expect(e.status, 401);
    });
  });

  group('PUT /me/location', () {
    test('"always" stores the fix and returns recordedAt', () async {
      final res =
          await call(
                'PUT',
                '/me/location',
                token: _amit,
                data: {'lat': 12.97, 'lng': 77.59, 'accuracy': 8},
              )
              as Map<String, dynamic>;
      final stored =
          member(MockSeed.amitMemberId)['lastLocation'] as Map<String, dynamic>;
      expect(stored['lat'], 12.97);
      expect(stored['accuracy'], 8.0);
      expect(stored['recordedAt'], res['recordedAt']);
    });

    test('other modes → 403 LOCATION_SHARING_DISABLED', () async {
      final e = await _error(
        call('PUT', '/me/location', token: _priya, data: {'lat': 1, 'lng': 2}),
      );
      expect(e.status, 403);
      expect(e.code, 'LOCATION_SHARING_DISABLED');
    });

    test('invalid coordinates → 422 (validated first)', () async {
      final e = await _error(
        call(
          'PUT',
          '/me/location',
          token: _priya,
          data: {'lat': 91, 'lng': -181, 'accuracy': -1},
        ),
      );
      expect(e.code, 'VALIDATION_ERROR');
      expect(e.details!.keys, containsAll(['lat', 'lng', 'accuracy']));
    });
  });

  group('/me/devices', () {
    test(
      'upsert by token moves it to the latest user; delete is scoped',
      () async {
        await call(
          'POST',
          '/me/devices',
          token: _amit,
          data: {'token': 'fcm-1', 'platform': 'android', 'locale': 'hi'},
        );
        await call(
          'POST',
          '/me/devices',
          token: _priya,
          data: {'token': 'fcm-1', 'platform': 'ios'},
        );
        final devices = db.col(MockDb.devices);
        expect(devices, hasLength(1));
        expect(devices.single['userId'], MockSeed.priyaUserId);
        expect(devices.single['platform'], 'ios');

        // Amit can no longer delete Priya's token.
        await call('DELETE', '/me/devices/fcm-1', token: _amit);
        expect(db.col(MockDb.devices), hasLength(1));
        await call('DELETE', '/me/devices/fcm-1', token: _priya);
        expect(db.col(MockDb.devices), isEmpty);
      },
    );

    test('validation', () async {
      final e = await _error(
        call(
          'POST',
          '/me/devices',
          token: _amit,
          data: {'token': ' ', 'platform': 'web'},
        ),
      );
      expect(e.details!.keys, containsAll(['token', 'platform']));
    });
  });

  group('GET /me/export', () {
    test('contains the caller\'s data only', () async {
      db.insert(MockDb.tasks, {
        'familyId': MockSeed.familyId,
        'assigneeId': MockSeed.amitMemberId,
        'createdById': MockSeed.priyaMemberId,
        'status': 'pending',
      });
      db.insert(MockDb.tasks, {
        'familyId': MockSeed.familyId,
        'assigneeId': MockSeed.aaravMemberId,
        'createdById': MockSeed.priyaMemberId,
        'status': 'pending',
      });
      db.insert(MockDb.notices, {
        'familyId': MockSeed.familyId,
        'authorId': MockSeed.amitMemberId,
      });

      final res =
          await call('GET', '/me/export', token: _amit) as Map<String, dynamic>;
      expect(
        res.keys,
        containsAll([
          'exportedAt',
          'user',
          'member',
          'tasks',
          'ledgerEntries',
          'notices',
          'emergencyCard',
          'sosAlerts',
        ]),
      );
      expect((res['user'] as Map).containsKey('password'), isFalse);
      expect(res['tasks'], hasLength(1));
      expect(res['notices'], hasLength(1));
      expect((res['member'] as Map)['lastLocation'], isNotNull);
    });
  });

  group('DELETE /me', () {
    test('password required / wrong password → INVALID_CREDENTIALS', () async {
      expect(
        (await _error(call('DELETE', '/me', token: _amit, data: {}))).code,
        'VALIDATION_ERROR',
      );
      final e = await _error(
        call('DELETE', '/me', token: _amit, data: {'password': 'nope'}),
      );
      expect(e.status, 401);
      expect(e.code, 'INVALID_CREDENTIALS');
      expect(db.findById(MockDb.users, MockSeed.amitUserId), isNotNull);
    });

    test(
      'deletes the account; the last admin with others gets LAST_ADMIN',
      () async {
        db.insert(MockDb.devices, {
          'userId': MockSeed.amitUserId,
          'token': 't',
        });
        await call(
          'DELETE',
          '/me',
          token: _amit,
          data: {'password': MockSeed.demoPassword},
        );
        expect(db.findById(MockDb.users, MockSeed.amitUserId), isNull);
        expect(db.findById(MockDb.members, MockSeed.amitMemberId), isNull);
        expect(db.col(MockDb.devices), isEmpty);
        expect(db.findById(MockDb.families, MockSeed.familyId), isNotNull);

        // Priya is now the only admin while Aarav, Anaya and Kamla remain.
        final e = await _error(
          call(
            'DELETE',
            '/me',
            token: _priya,
            data: {'password': MockSeed.demoPassword},
          ),
        );
        expect(e.status, 409);
        expect(e.code, 'LAST_ADMIN');
        expect(db.findById(MockDb.users, MockSeed.priyaUserId), isNotNull);
      },
    );

    test('the only member deletes the whole family', () async {
      for (final id in MockSeed.memberIds) {
        if (id != MockSeed.amitMemberId) db.remove(MockDb.members, id);
      }
      db.insert(MockDb.tasks, {
        'familyId': MockSeed.familyId,
        'assigneeId': MockSeed.amitMemberId,
      });
      await call(
        'DELETE',
        '/me',
        token: _amit,
        data: {'password': MockSeed.demoPassword},
      );
      expect(db.findById(MockDb.families, MockSeed.familyId), isNull);
      expect(db.col(MockDb.tasks), isEmpty);
    });
  });

  group('POST /me/leave-family', () {
    test(
      'unlinks the user and removes the profile; keeps the account',
      () async {
        db.insert(MockDb.tasks, {
          'familyId': MockSeed.familyId,
          'assigneeId': MockSeed.amitMemberId,
          'status': 'pending',
        });
        db.insert(MockDb.tasks, {
          'familyId': MockSeed.familyId,
          'assigneeId': MockSeed.amitMemberId,
          'status': 'done',
        });
        final res =
            await call('POST', '/me/leave-family', token: _amit)
                as Map<String, dynamic>;
        final user = res['user'] as Map<String, dynamic>;
        expect(user['familyId'], isNull);
        expect(user['memberId'], isNull);
        expect(user['role'], isNull);
        expect(db.findById(MockDb.members, MockSeed.amitMemberId), isNull);
        expect(db.col(MockDb.tasks).map((t) => t['status']), ['done']);
        expect(db.findById(MockDb.users, MockSeed.amitUserId), isNotNull);

        // Now Priya is the last admin.
        final e = await _error(call('POST', '/me/leave-family', token: _priya));
        expect(e.code, 'LAST_ADMIN');

        // And Amit has no family any more.
        final noFamily = await _error(
          call('POST', '/me/leave-family', token: _amit),
        );
        expect(noFamily.code, 'NO_FAMILY');
      },
    );
  });

  group('POST /uploads/signature', () {
    test('returns a signed-upload shape for the caller\'s family', () async {
      final res =
          await call(
                'POST',
                '/uploads/signature',
                token: _amit,
                data: {'folder': 'avatars'},
              )
              as Map<String, dynamic>;
      expect(res['folder'], 'familyhub/${MockSeed.familyId}/avatars');
      expect(res['cloudName'], isNotEmpty);
      expect(res['timestamp'], isA<int>());
      expect(res['signature'], hasLength(40));

      final e = await _error(
        call(
          'POST',
          '/uploads/signature',
          token: _amit,
          data: {'folder': 'secrets'},
        ),
      );
      expect(e.code, 'VALIDATION_ERROR');
    });
  });

  // ── Backend parity (family_hub_backend/src/modules/me) ────────────────────

  group('PATCH /me backend rules', () {
    test('blank strings clear nullable fields (shared PATCH rule)', () async {
      db.update(MockDb.members, MockSeed.amitMemberId, {
        'avatarUrl': 'https://res.cloudinary.com/demo/image/upload/a.jpg',
      });
      final res =
          await call(
                'PATCH',
                '/me',
                token: _amit,
                data: {
                  'avatarUrl': '  ',
                  'gender': '',
                  'phone': ' ',
                  'dateOfBirth': '',
                },
              )
              as Map<String, dynamic>;
      final m = res['member'] as Map<String, dynamic>;
      expect(m['avatarUrl'], isNull);
      expect(m['gender'], isNull);
      expect(m['phone'], isNull);
      expect(m['dateOfBirth'], isNull);
    });

    test(
      'date of birth: ISO with offset, not future, not before 1900',
      () async {
        Future<String?> dobError(String value) async {
          final e = await _error(
            call('PATCH', '/me', token: _amit, data: {'dateOfBirth': value}),
          );
          expect(e.code, 'VALIDATION_ERROR');
          return e.details?['dateOfBirth'] as String?;
        }

        expect(
          await dobError('1985-01-31T00:00:00'),
          isNotNull,
          reason: 'no zone',
        );
        expect(await dobError('31/01/1985'), isNotNull);
        expect(await dobError('1985-02-31'), isNotNull, reason: 'no such day');
        expect(await dobError('1899-12-31T18:30:00.000Z'), isNotNull);
        final tomorrowPlus = DateTime.now().toUtc().add(
          const Duration(days: 2),
        );
        expect(await dobError(MockDb.iso(tomorrowPlus)), isNotNull);

        // Local midnight "today" east of UTC is still accepted (1 day slack).
        await call(
          'PATCH',
          '/me',
          token: _amit,
          data: {'dateOfBirth': '1985-01-31'},
        );
        expect(
          member(MockSeed.amitMemberId)['dateOfBirth'],
          '1985-01-31T00:00:00.000Z',
        );
      },
    );

    test('a DOB below the consent age needs guardian consent', () async {
      final child = MockDb.iso(
        DateTime.now().toUtc().subtract(const Duration(days: 365 * 10)),
      );
      final e = await _error(
        call('PATCH', '/me', token: _amit, data: {'dateOfBirth': child}),
      );
      expect(e.status, 422);
      expect(e.code, 'GUARDIAN_CONSENT_REQUIRED');
      expect(member(MockSeed.amitMemberId)['dateOfBirth'], isNot(child));

      // With recorded consent (an admin added the child) it is allowed.
      db.update(MockDb.members, MockSeed.amitMemberId, {
        'guardianConsent': true,
      });
      await call('PATCH', '/me', token: _amit, data: {'dateOfBirth': child});
      expect(member(MockSeed.amitMemberId)['dateOfBirth'], child);
    });
  });

  group('location + devices backend rules', () {
    test('PUT /me/location: NO_FAMILY first, accuracy ≤ 100 km', () async {
      final tooVague = await _error(
        call(
          'PUT',
          '/me/location',
          token: _amit,
          data: {'lat': 1, 'lng': 2, 'accuracy': 100001},
        ),
      );
      expect(tooVague.details!.keys, ['accuracy']);
      await call(
        'PUT',
        '/me/location',
        token: _amit,
        data: {'lat': 1, 'lng': 2, 'accuracy': null},
      );
      expect(
        (member(MockSeed.amitMemberId)['lastLocation'] as Map)['accuracy'],
        isNull,
      );

      db.update(MockDb.users, MockSeed.amitUserId, {
        'familyId': null,
        'memberId': null,
      });
      final noFamily = await _error(
        call('PUT', '/me/location', token: _amit, data: {'lat': 999}),
      );
      expect(noFamily.code, 'NO_FAMILY', reason: 'before validation');
      final upload = await _error(
        call(
          'POST',
          '/uploads/signature',
          token: _amit,
          data: {'folder': 'avatars'},
        ),
      );
      expect(upload.code, 'NO_FAMILY');
    });

    test('device tokens are trimmed, validated and capped per user', () async {
      await call(
        'POST',
        '/me/devices',
        token: _amit,
        data: {'token': '  fcm-a  ', 'platform': 'android'},
      );
      await call(
        'POST',
        '/me/devices',
        token: _amit,
        data: {'token': 'fcm-a', 'platform': 'android', 'locale': 'ta'},
      );
      final device = db.col(MockDb.devices).single;
      expect(device['token'], 'fcm-a');
      expect(device['locale'], 'ta');

      final spaced = await _error(
        call(
          'POST',
          '/me/devices',
          token: _amit,
          data: {'token': 'two words', 'platform': 'ios'},
        ),
      );
      expect(spaced.details!.keys, ['token']);
      final badDelete = await _error(
        call('DELETE', '/me/devices/two%20words', token: _amit),
      );
      expect(badDelete.code, 'VALIDATION_ERROR');

      for (var i = 0; i < 12; i++) {
        await call(
          'POST',
          '/me/devices',
          token: _amit,
          data: {'token': 'fcm-$i', 'platform': 'ios'},
        );
      }
      final mine = db.where(
        MockDb.devices,
        (d) => d['userId'] == MockSeed.amitUserId,
      );
      expect(mine, hasLength(10));
      expect(mine.map((d) => d['token']), contains('fcm-11'));
    });
  });

  group('GET /me/export backend shape', () {
    test('contract objects, masked devices, sessions, no secrets', () async {
      db.insert(MockDb.ledgerEntries, {
        'familyId': MockSeed.familyId,
        'type': 'expense',
        'amountMinor': 125050,
        'category': 'groceries',
        'date': '2026-09-01T00:00:00.000Z',
        'memberId': MockSeed.amitMemberId,
        'memberName': 'Amit',
        'createdById': MockSeed.amitMemberId,
      });
      db.insert(MockDb.tasks, {
        'familyId': MockSeed.familyId,
        'title': 'Water plants',
        'assigneeId': MockSeed.aaravMemberId,
        'createdById': MockSeed.priyaMemberId,
        'completedById': MockSeed.amitMemberId,
        'status': 'done',
      });
      db.insert(MockDb.sosAlerts, {
        'familyId': MockSeed.familyId,
        'memberId': MockSeed.amitMemberId,
        'status': 'active',
        'startedAt': '2026-01-01T10:00:00.000Z',
        'expiresAt': '2026-01-01T10:15:00.000Z',
      });
      db.insert(MockDb.devices, {
        'userId': MockSeed.amitUserId,
        'token': 'secret-token-123456',
        'platform': 'android',
      });
      MockTokens.issue(db, MockSeed.amitUserId);

      final res =
          await call('GET', '/me/export', token: _amit) as Map<String, dynamic>;
      expect(res['formatVersion'], 1);
      expect((res['family'] as Map)['inviteCode'], isNull);
      expect(res['currency'], 'INR');
      final entry = (res['ledgerEntries'] as List).single as Map;
      expect(entry['amount'], 1250.5);
      expect(entry.containsKey('amountMinor'), isFalse);
      expect(
        (res['tasks'] as List).map((t) => (t as Map)['title']),
        contains('Water plants'),
        reason: 'tasks the caller completed are theirs too',
      );
      expect(
        ((res['sosAlerts'] as List).single as Map)['status'],
        'expired',
        reason: 'lazy expiry',
      );
      final device = (res['devices'] as List).single as Map;
      expect(device['tokenSuffix'], '123456');
      expect(device.containsKey('token'), isFalse);
      final session = (res['sessions'] as List).single as Map;
      expect(session['active'], isTrue);
      expect(session.containsKey('token'), isFalse);
      expect(res.toString(), isNot(contains(MockSeed.demoPassword)));
    });

    test('works without a family (account data only)', () async {
      db.update(MockDb.users, MockSeed.amitUserId, {
        'familyId': null,
        'memberId': null,
      });
      final res =
          await call('GET', '/me/export', token: _amit) as Map<String, dynamic>;
      expect(res['member'], isNull);
      expect(res['family'], isNull);
      expect((res['user'] as Map)['role'], isNull);
      expect(res['tasks'], isEmpty);
    });
  });

  group('leave / delete cascade (removeSelfFromFamily)', () {
    void seedMemberData() {
      db.insert(MockDb.tasks, {
        'familyId': MockSeed.familyId,
        'assigneeId': MockSeed.amitMemberId,
        'status': 'pending',
      });
      db.insert(MockDb.sosAlerts, {
        'familyId': MockSeed.familyId,
        'memberId': MockSeed.amitMemberId,
        'status': 'active',
        'expiresAt': MockDb.iso(DateTime.now().add(const Duration(minutes: 5))),
      });
      db.insert(MockDb.emergencyCards, {
        'familyId': MockSeed.familyId,
        'memberId': MockSeed.amitMemberId,
      });
      db.insert(MockDb.devices, {
        'userId': MockSeed.amitUserId,
        'token': 'fcm-amit',
        'platform': 'android',
      });
      MockTokens.issue(db, MockSeed.amitUserId);
    }

    void expectCascade() {
      expect(db.findById(MockDb.members, MockSeed.amitMemberId), isNull);
      expect(
        db.where(MockDb.tasks, (t) => t['assigneeId'] == MockSeed.amitMemberId),
        isEmpty,
      );
      final sos = db.col(MockDb.sosAlerts).single;
      expect(sos['status'], 'resolved');
      expect(sos['resolution'], isNull, reason: 'nobody confirmed "safe"');
      expect(sos['resolvedById'], MockSeed.amitMemberId);
      expect(db.col(MockDb.emergencyCards), isEmpty);
      expect(
        db.findById(MockDb.families, MockSeed.familyId)!['ownerId'],
        MockSeed.priyaUserId,
        reason: 'ownership moves to the remaining admin',
      );
    }

    test('leaving keeps the account signed in (tokens + devices)', () async {
      seedMemberData();
      await call('POST', '/me/leave-family', token: _amit);
      expectCascade();
      expect(
        db.where(MockDb.refreshTokens, (t) => t['revokedAt'] == null),
        hasLength(1),
      );
      expect(db.col(MockDb.devices), hasLength(1));
      final user = db.findById(MockDb.users, MockSeed.amitUserId)!;
      expect(user['familyId'], isNull);
    });

    test(
      'deleting the account applies the same cascade + ends sessions',
      () async {
        seedMemberData();
        await call(
          'DELETE',
          '/me',
          token: _amit,
          data: {'password': MockSeed.demoPassword},
        );
        expectCascade();
        expect(db.col(MockDb.refreshTokens), isEmpty);
        expect(db.col(MockDb.devices), isEmpty);
        expect(db.findById(MockDb.users, MockSeed.amitUserId), isNull);
      },
    );

    test('a managed-profile admin does not count as another admin', () async {
      // Priya becomes a member, Kamla (no account) an admin.
      db.update(MockDb.members, MockSeed.priyaMemberId, {'role': 'member'});
      db.update(MockDb.members, MockSeed.kamlaMemberId, {'role': 'admin'});
      final e = await _error(call('POST', '/me/leave-family', token: _amit));
      expect(e.code, 'LAST_ADMIN');
      expect(db.findById(MockDb.members, MockSeed.amitMemberId), isNotNull);
    });

    test(
      'the last member leaving deletes the family, keeps the account',
      () async {
        for (final id in MockSeed.memberIds) {
          if (id != MockSeed.amitMemberId) db.remove(MockDb.members, id);
        }
        MockTokens.issue(db, MockSeed.amitUserId);
        final res =
            await call('POST', '/me/leave-family', token: _amit)
                as Map<String, dynamic>;
        expect((res['user'] as Map)['familyId'], isNull);
        expect(db.findById(MockDb.families, MockSeed.familyId), isNull);
        expect(db.col(MockDb.refreshTokens), hasLength(1));
      },
    );

    test('DELETE /me: password longer than 128 → 422', () async {
      final e = await _error(
        call('DELETE', '/me', token: _amit, data: {'password': 'x' * 129}),
      );
      expect(e.code, 'VALIDATION_ERROR');
    });
  });
}
