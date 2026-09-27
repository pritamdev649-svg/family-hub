import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/network/mock/mock_backend.dart';
import 'package:family_hub/core/utils/validators.dart';
import 'package:family_hub/features/family/data/family_mock_handlers.dart';

/// Contract rules of the `/family` mock (docs/03-API_CONTRACT.md §6) on the
/// core demo seed: Amit + Priya (admins), Kamla, Aarav (pre-added with an
/// email, no account) and Anaya (child, no account) in "Sharma Family" (IN).
void main() {
  late MockBackend b;
  late MockDb db;

  /// Kamla gets an account so a non-admin can call the API.
  const kamlaUserId = '64f1a0000000000000000199';

  setUp(() {
    db = MockDb();
    b = MockBackend(db);
    registerFamilyMocks(b);
    db.insert(MockDb.users, {
      'id': kamlaUserId,
      'email': 'kamla@familyhub.app',
      'name': 'Kamla',
      'familyId': MockSeed.familyId,
      'memberId': MockSeed.kamlaMemberId,
      'emailVerified': true,
    });
    db.update(MockDb.members, MockSeed.kamlaMemberId, {'userId': kamlaUserId});
  });

  Future<MockResponse> call(
    String method,
    String path, {
    String? as = MockSeed.amitUserId,
    Object? body,
  }) => b.handle(
    RequestOptions(
      method: method,
      baseUrl: MockBackend.baseUrl,
      path: path,
      data: body,
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

  /// A signed-in user without a family.
  String newUser(String email, {String name = 'New Person'}) =>
      db.insert(MockDb.users, {
            'email': email,
            'name': name,
            'familyId': null,
            'memberId': null,
            'emailVerified': true,
          })['id']
          as String;

  String isoAgo(int years) {
    final now = DateTime.now();
    return MockDb.iso(DateTime(now.year - years, now.month, 1));
  }

  Map<String, dynamic> data(MockResponse r) =>
      (r.data! as Map).cast<String, dynamic>();

  group('GET/PATCH /family', () {
    test('invite code only for admins, computed member count', () async {
      final admin = data(await call('GET', '/family'))['family'] as Map;
      expect(admin['inviteCode'], MockSeed.inviteCode);
      expect(admin['memberCount'], 5);
      final member =
          data(await call('GET', '/family', as: kamlaUserId))['family'] as Map;
      expect(member['inviteCode'], isNull);
      expect(member['name'], 'Sharma Family');
    });

    test('unauthenticated → 401, without family → 403 NO_FAMILY', () async {
      expect((await error(call('GET', '/family', as: null))).status, 401);
      final loner = newUser('loner@example.com');
      expect(
        (await error(call('GET', '/family', as: loner))).code,
        'NO_FAMILY',
      );
    });

    test('PATCH is admin-only and validated', () async {
      final forbidden = await error(
        call('PATCH', '/family', as: kamlaUserId, body: {'name': 'X'}),
      );
      expect(forbidden.code, 'FORBIDDEN');

      final invalid = await error(
        call(
          'PATCH',
          '/family',
          body: {
            'name': ' ',
            'country': 'XX',
            'currency': 'ABC',
            'timezone': 'Mars/Base',
          },
        ),
      );
      expect(invalid.code, 'VALIDATION_ERROR');
      expect(
        invalid.details!.keys,
        containsAll(['name', 'country', 'currency', 'timezone']),
      );

      final ok =
          data(
                await call(
                  'PATCH',
                  '/family',
                  body: {
                    'name': ' Sharmas ',
                    'country': 'us',
                    'currency': 'usd',
                    'timezone': 'America/New_York',
                  },
                ),
              )['family']
              as Map;
      expect(ok['name'], 'Sharmas');
      expect(ok['country'], 'US');
      expect(ok['currency'], 'USD');
      expect(ok['timezone'], 'America/New_York');
      expect(ok['inviteCode'], MockSeed.inviteCode);
    });
  });

  group('invite code & join', () {
    test(
      'rotation: new 8-char code from the alphabet, old one stops working',
      () async {
        final family =
            data(await call('POST', '/family/invite-code'))['family'] as Map;
        final code = family['inviteCode'] as String;
        expect(code, hasLength(8));
        expect(code, isNot(MockSeed.inviteCode));
        expect(
          code.split('').every(Validators.inviteAlphabet.contains),
          isTrue,
        );

        final user = newUser('someone@example.com');
        final old = await error(
          call(
            'POST',
            '/family/join',
            as: user,
            body: {'inviteCode': MockSeed.inviteCode},
          ),
        );
        expect(old.code, 'INVALID_INVITE_CODE');
        expect(old.status, 400);

        final joined = data(
          await call(
            'POST',
            '/family/join',
            as: user,
            body: {
              'inviteCode':
                  ' ${code.substring(0, 4).toLowerCase()}-${code.substring(4)} ',
            },
          ),
        );
        expect((joined['member'] as Map)['role'], 'member');
        expect((joined['user'] as Map)['familyId'], MockSeed.familyId);
        expect((joined['family'] as Map)['inviteCode'], isNull); // not admin
      },
    );

    test('non-admins cannot rotate the code', () async {
      expect(
        (await error(
          call('POST', '/family/invite-code', as: kamlaUserId),
        )).code,
        'FORBIDDEN',
      );
    });

    test('join links the pre-added member with the same email', () async {
      final user = newUser(MockSeed.aaravEmail, name: 'Aarav S');
      final res = data(
        await call(
          'POST',
          '/family/join',
          as: user,
          body: {'inviteCode': MockSeed.inviteCode},
        ),
      );
      final member = res['member'] as Map;
      expect(member['id'], MockSeed.aaravMemberId);
      expect(member['hasAccount'], isTrue);
      expect(
        db.findById(MockDb.users, user)!['memberId'],
        MockSeed.aaravMemberId,
      );
    });

    test('POST /family creates family + admin; already in one → 409', () async {
      final user = newUser('founder@example.com', name: 'Founder');
      final res = await call(
        'POST',
        '/family',
        as: user,
        body: {
          'name': 'Rao Family',
          'country': 'DE',
          'currency': 'EUR',
          'timezone': 'Europe/Berlin',
        },
      );
      expect(res.status, 201);
      final session = data(res);
      expect((session['member'] as Map)['role'], 'admin');
      expect((session['member'] as Map)['designation'], 'Head of Family');
      expect((session['family'] as Map)['inviteCode'], hasLength(8));
      expect((session['family'] as Map)['memberCount'], 1);

      final again = await error(
        call(
          'POST',
          '/family',
          as: user,
          body: {
            'name': 'Second',
            'country': 'DE',
            'currency': 'EUR',
            'timezone': 'Europe/Berlin',
          },
        ),
      );
      expect(again.code, 'ALREADY_IN_FAMILY');
      final join = await error(
        call(
          'POST',
          '/family/join',
          as: user,
          body: {'inviteCode': MockSeed.inviteCode},
        ),
      );
      expect(join.code, 'ALREADY_IN_FAMILY');
    });

    test("another family's members are 404", () async {
      final user = newUser('other@example.com');
      await call(
        'POST',
        '/family',
        as: user,
        body: {
          'name': 'Other',
          'country': 'IN',
          'currency': 'INR',
          'timezone': 'Asia/Kolkata',
        },
      );
      for (final (method, body) in [
        ('GET', null),
        ('PATCH', {'name': 'X'}),
        ('DELETE', null),
      ]) {
        final e = await error(
          call(
            method,
            '/family/members/${MockSeed.amitMemberId}',
            as: user,
            body: body,
          ),
        );
        expect(e.code, 'NOT_FOUND', reason: method);
      }
    });
  });

  group('GET /family/members', () {
    test('admins first, then oldest → youngest', () async {
      final list = (await call('GET', '/family/members')).data! as List;
      expect(
        [for (final m in list) (m as Map)['id']],
        [
          MockSeed.amitMemberId,
          MockSeed.priyaMemberId,
          MockSeed.kamlaMemberId,
          MockSeed.aaravMemberId,
          MockSeed.anayaMemberId,
        ],
      );
      final amit = list.first as Map;
      expect(amit.containsKey('guardianConsentAt'), isFalse);
      // Amit shares "always" → location visible; Priya shares sos_only → null.
      expect(amit['lastLocation'], isNotNull);
      expect((list[1] as Map)['lastLocation'], isNull);
    });
  });

  group('POST /family/members', () {
    test('admin only', () async {
      final e = await error(
        call('POST', '/family/members', as: kamlaUserId, body: {'name': 'X'}),
      );
      expect(e.code, 'FORBIDDEN');
    });

    test('minor without consent → 422 GUARDIAN_CONSENT_REQUIRED', () async {
      final e = await error(
        call(
          'POST',
          '/family/members',
          body: {'name': 'Kid', 'dateOfBirth': isoAgo(15)},
        ),
      );
      expect(e.status, 422);
      expect(e.code, 'GUARDIAN_CONSENT_REQUIRED');

      final res = await call(
        'POST',
        '/family/members',
        body: {
          'name': 'Kid',
          'dateOfBirth': isoAgo(15),
          'guardianConsent': true,
          'gender': 'other',
        },
      );
      expect(res.status, 201);
      final m = data(res);
      expect(m['guardianConsent'], isTrue);
      expect(m['hasAccount'], isFalse);
      expect(m['locationSharing'], 'never');
      final stored = db.findById(MockDb.members, m['id'])!;
      expect(stored['guardianConsentById'], MockSeed.amitMemberId);
      expect(stored['guardianConsentAt'], isNotNull);
    });

    test('consent age follows the family country (US: 13)', () async {
      await call('PATCH', '/family', body: {'country': 'US'});
      final res = await call(
        'POST',
        '/family/members',
        body: {'name': 'Teen', 'dateOfBirth': isoAgo(15)},
      );
      expect(res.status, 201);
      final child = await error(
        call(
          'POST',
          '/family/members',
          body: {'name': 'Child', 'dateOfBirth': isoAgo(10)},
        ),
      );
      expect(child.code, 'GUARDIAN_CONSENT_REQUIRED');
    });

    test('duplicate email (any case) → 409 MEMBER_EMAIL_EXISTS', () async {
      final e = await error(
        call(
          'POST',
          '/family/members',
          body: {'name': 'Twin', 'email': ' AARAV@familyhub.app '},
        ),
      );
      expect(e.code, 'MEMBER_EMAIL_EXISTS');
      expect(e.status, 409);
    });

    test('validation details per field', () async {
      final e = await error(
        call(
          'POST',
          '/family/members',
          body: {
            'name': '  ',
            'email': 'nope',
            'phone': '12',
            'gender': 'robot',
            'role': 'owner',
            'dateOfBirth': 'soon',
          },
        ),
      );
      expect(e.code, 'VALIDATION_ERROR');
      expect(
        e.details!.keys,
        containsAll([
          'name',
          'email',
          'phone',
          'gender',
          'role',
          'dateOfBirth',
        ]),
      );
    });

    test('normalises email / phone and stores a managed profile', () async {
      final m = data(
        await call(
          'POST',
          '/family/members',
          body: {
            'name': ' Dadi ',
            'email': 'Dadi@Example.COM',
            'phone': '+91 98765-43219',
            'designation': ' Family Advisor ',
            'role': 'member',
          },
        ),
      );
      expect(m['name'], 'Dadi');
      expect(m['email'], 'dadi@example.com');
      expect(m['phone'], '+919876543219');
      expect(m['designation'], 'Family Advisor');
      expect(m['userId'], isNull);
    });
  });

  group('PATCH /family/members/:id', () {
    String path(String id) => '/family/members/$id';

    test(
      'a member may patch only themselves and only allowed fields',
      () async {
        final ok = data(
          await call(
            'PATCH',
            path(MockSeed.kamlaMemberId),
            as: kamlaUserId,
            body: {
              'name': 'Kamla Devi',
              'phone': '+919999999999',
              'gender': 'female',
            },
          ),
        );
        expect(ok['name'], 'Kamla Devi');
        expect(ok['phone'], '+919999999999');
        // Renaming yourself renames the account too.
        expect(db.findById(MockDb.users, kamlaUserId)!['name'], 'Kamla Devi');

        final designation = await error(
          call(
            'PATCH',
            path(MockSeed.kamlaMemberId),
            as: kamlaUserId,
            body: {'designation': 'Boss'},
          ),
        );
        expect(designation.code, 'FORBIDDEN');
        final role = await error(
          call(
            'PATCH',
            path(MockSeed.kamlaMemberId),
            as: kamlaUserId,
            body: {'role': 'admin'},
          ),
        );
        expect(role.code, 'FORBIDDEN');
        final other = await error(
          call(
            'PATCH',
            path(MockSeed.aaravMemberId),
            as: kamlaUserId,
            body: {'name': 'X'},
          ),
        );
        expect(other.code, 'FORBIDDEN');
      },
    );

    test('admin changes any field; email uniqueness is checked', () async {
      final m = data(
        await call(
          'PATCH',
          path(MockSeed.anayaMemberId),
          body: {
            'designation': 'Chief Fun Officer',
            'email': 'anaya@example.com',
            'phone': null,
          },
        ),
      );
      expect(m['designation'], 'Chief Fun Officer');
      expect(m['email'], 'anaya@example.com');

      final e = await error(
        call(
          'PATCH',
          path(MockSeed.anayaMemberId),
          body: {'email': MockSeed.priyaEmail},
        ),
      );
      expect(e.code, 'MEMBER_EMAIL_EXISTS');
      // Keeping your own email is fine.
      await call(
        'PATCH',
        path(MockSeed.anayaMemberId),
        body: {'email': 'ANAYA@example.com'},
      );
    });

    test('location sharing is not patchable here', () async {
      final m = data(
        await call(
          'PATCH',
          path(MockSeed.kamlaMemberId),
          body: {'locationSharing': 'always'},
        ),
      );
      expect(m['locationSharing'], 'never');
    });

    test(
      'avatar must be a Cloudinary URL (or a mock-mode local path)',
      () async {
        final bad = await error(
          call(
            'PATCH',
            path(MockSeed.kamlaMemberId),
            body: {'avatarUrl': 'https://evil.example.com/a.png'},
          ),
        );
        expect(bad.details!.keys, contains('avatarUrl'));
        for (final url in [
          'https://res.cloudinary.com/demo/image/upload/a.jpg',
          '/data/user/0/app/cache/picked.jpg',
        ]) {
          final m = data(
            await call(
              'PATCH',
              path(MockSeed.kamlaMemberId),
              body: {'avatarUrl': url},
            ),
          );
          expect(m['avatarUrl'], url);
        }
      },
    );

    test('demoting the last admin → 409 LAST_ADMIN', () async {
      // Two admins: demoting Priya is fine.
      final priya = data(
        await call(
          'PATCH',
          path(MockSeed.priyaMemberId),
          body: {'role': 'member'},
        ),
      );
      expect(priya['role'], 'member');
      final e = await error(
        call('PATCH', path(MockSeed.amitMemberId), body: {'role': 'member'}),
      );
      expect(e.code, 'LAST_ADMIN');
      expect(e.status, 409);
    });
  });

  group('DELETE /family/members/:id', () {
    String path(String id) => '/family/members/$id';

    test('admin only; deleting the last admin → 409 LAST_ADMIN', () async {
      expect(
        (await error(
          call('DELETE', path(MockSeed.anayaMemberId), as: kamlaUserId),
        )).code,
        'FORBIDDEN',
      );
      await call(
        'PATCH',
        path(MockSeed.priyaMemberId),
        body: {'role': 'member'},
      );
      expect(
        (await error(call('DELETE', path(MockSeed.amitMemberId)))).code,
        'LAST_ADMIN',
      );
    });

    test(
      'cascade: unlink user, pending tasks, card, SOS; ledger stays',
      () async {
        const kamla = MockSeed.kamlaMemberId;
        const fid = MockSeed.familyId;
        final refresh = MockTokens.issue(db, kamlaUserId)['refreshToken'];
        db.insert(MockDb.devices, {
          'userId': kamlaUserId,
          'token': 'fcm-1',
          'platform': 'android',
        });
        final pending = db.insert(MockDb.tasks, {
          'familyId': fid,
          'assigneeId': kamla,
          'status': 'pending',
          'title': 'Walk',
        });
        final done = db.insert(MockDb.tasks, {
          'familyId': fid,
          'assigneeId': kamla,
          'status': 'done',
          'title': 'Pray',
        });
        final other = db.insert(MockDb.tasks, {
          'familyId': fid,
          'assigneeId': MockSeed.aaravMemberId,
          'status': 'pending',
          'title': 'Study',
        });
        db.insert(MockDb.emergencyCards, {
          'familyId': fid,
          'memberId': kamla,
          'bloodGroup': 'O+',
        });
        final sos = db.insert(MockDb.sosAlerts, {
          'familyId': fid,
          'memberId': kamla,
          'status': 'active',
        });
        final entry = db.insert(MockDb.ledgerEntries, {
          'familyId': fid,
          'memberId': kamla,
          'amount': 100,
          'type': 'expense',
        });

        final res = await call('DELETE', path(kamla));
        expect(res.status, 200);
        expect(res.data, isNull);

        final user = db.findById(MockDb.users, kamlaUserId)!;
        expect(user['familyId'], isNull);
        expect(user['memberId'], isNull);
        expect(
          () => MockTokens.rotate(db, refresh),
          throwsA(isA<MockException>()),
        );
        expect(db.count(MockDb.devices, (d) => d['userId'] == kamlaUserId), 0);
        expect(db.findById(MockDb.tasks, pending['id']), isNull);
        expect(db.findById(MockDb.tasks, done['id']), isNotNull);
        expect(db.findById(MockDb.tasks, other['id']), isNotNull);
        expect(
          db.count(MockDb.emergencyCards, (c) => c['memberId'] == kamla),
          0,
        );
        final resolved = db.findById(MockDb.sosAlerts, sos['id'])!;
        expect(resolved['status'], 'resolved');
        expect(resolved['resolvedById'], MockSeed.amitMemberId);
        expect(resolved['resolvedAt'], isNotNull);
        final kept = db.findById(MockDb.ledgerEntries, entry['id'])!;
        expect(kept['memberName'], 'Kamla');

        expect((await error(call('GET', path(kamla)))).code, 'NOT_FOUND');
        final family = data(await call('GET', '/family'))['family'] as Map;
        expect(family['memberCount'], 4);
        // The removed user no longer has a family.
        expect(
          (await error(call('GET', '/family/members', as: kamlaUserId))).code,
          'NO_FAMILY',
        );
      },
    );
  });

  group('edge cases', () {
    test('a malformed member id → 400 BAD_REQUEST (after auth)', () async {
      for (final method in ['GET', 'PATCH', 'DELETE']) {
        final e = await error(
          call(method, '/family/members/not-an-id', body: {'name': 'X'}),
        );
        expect(e.status, 400, reason: method);
        expect(e.code, 'BAD_REQUEST', reason: method);
        final anonymous = await error(
          call(method, '/family/members/not-an-id', as: null),
        );
        expect(anonymous.status, 401, reason: method);
      }
      // A well-formed id of nobody is 404, never 400.
      final missing = await error(
        call('GET', '/family/members/64f1a00000000000000009ff'),
      );
      expect(missing.code, 'NOT_FOUND');
    });

    test('dates of birth are checked by calendar day', () async {
      Future<MockResponse> add(String dob) => call(
        'POST',
        '/family/members',
        body: {'name': 'Old Timer', 'dateOfBirth': dob},
      );
      // 1 Jan 1900, local midnight in India (+05:30) sent as UTC.
      final created = data(await add('1899-12-31T18:30:00.000Z'));
      expect(created['dateOfBirth'], '1899-12-31T18:30:00.000Z');
      final tooOld = await error(add('1899-12-30T00:00:00.000Z'));
      expect(tooOld.details!.keys, contains('dateOfBirth'));
      final now = DateTime.now();
      final future = await error(
        add(MockDb.iso(DateTime(now.year, now.month, now.day + 3))),
      );
      expect(future.details!.keys, contains('dateOfBirth'));
      final garbage = await error(add('31/12/2000'));
      expect(garbage.details!['dateOfBirth'], 'Invalid date');
    });

    test('very long names are rejected with field details', () async {
      final e = await error(
        call('POST', '/family/members', body: {'name': 'A' * 61}),
      );
      expect(e.code, 'VALIDATION_ERROR');
      expect(e.details!.keys, contains('name'));
      final ok = data(
        await call('POST', '/family/members', body: {'name': 'A' * 60}),
      );
      expect((ok['name'] as String).length, 60);
    });

    test('deleting an already removed member → 404 (client: done)', () async {
      await call('DELETE', '/family/members/${MockSeed.anayaMemberId}');
      final again = await error(
        call('DELETE', '/family/members/${MockSeed.anayaMemberId}'),
      );
      expect(again.code, 'NOT_FOUND');
    });
  });

  test('FamilyMockService.ageOf uses the calendar day', () {
    final now = DateTime(2026, 9, 26);
    expect(
      FamilyMockService.ageOf(MockDb.iso(DateTime(2008, 9, 27)), now: now),
      17,
    );
    expect(
      FamilyMockService.ageOf(MockDb.iso(DateTime(2008, 9, 26)), now: now),
      18,
    );
    expect(FamilyMockService.ageOf(null), isNull);
    expect(FamilyMockService.ageOf('garbage'), isNull);
  });
}
