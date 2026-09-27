// The `/auth` mock routes (docs/03-API_CONTRACT.md §4) called directly
// through MockBackend.handle — no Dio, no latency.
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/network/mock/mock_backend.dart';
import 'package:family_hub/core/utils/validators.dart';
import 'package:family_hub/features/auth/data/auth_mock_handlers.dart';
import 'package:family_hub/features/auth/domain/auth_rules.dart';
import 'package:family_hub/shared/models/models.dart';

class _Api {
  _Api() {
    registerAuthMocks(backend, clock: () => now);
  }

  final backend = MockBackend();
  DateTime now = DateTime.now();

  MockDb get db => backend.db;

  void advance(Duration d) => now = now.add(d);

  Future<MockResponse> call(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? userId,
  }) => backend.handle(
    RequestOptions(
      baseUrl: MockBackend.baseUrl,
      path: path,
      method: method,
      data: body,
      headers: {
        if (userId != null)
          'Authorization': 'Bearer ${MockRequest.accessTokenFor(userId)}',
      },
    ),
  );

  Future<Map<String, dynamic>> ok(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? userId,
  }) async {
    final res = await call(method, path, body: body, userId: userId);
    expect(res.status, anyOf(200, 201));
    return (res.data as Map?)?.cast<String, dynamic>() ?? const {};
  }

  Future<MockException> error(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? userId,
  }) async {
    try {
      await call(method, path, body: body, userId: userId);
    } on MockException catch (e) {
      return e;
    }
    fail('expected $method $path to fail');
  }

  Future<MockException> login(String email, String password) => error(
    'POST',
    '/auth/login',
    body: {'email': email, 'password': password},
  );
}

Map<String, dynamic> _createBody({
  String email = 'new@example.com',
  String password = 'secret123',
  Map<String, dynamic>? family,
  Object? consent = true,
  Object? dateOfBirth,
}) => {
  'name': ' Neha Gupta ',
  'email': email,
  'password': password,
  'locale': 'hi',
  'consentAccepted': consent,
  'dateOfBirth': dateOfBirth,
  'mode': 'create',
  'family':
      family ??
      {
        'name': 'Gupta Family',
        'country': 'de',
        'currency': 'eur',
        'timezone': 'Europe/Berlin',
      },
  'inviteCode': null,
};

Map<String, dynamic> _joinBody(String code, {String email = 'j@example.com'}) =>
    {
      'name': 'Joiner',
      'email': email,
      'password': 'secret123',
      'locale': 'en',
      'consentAccepted': true,
      'mode': 'join',
      'family': null,
      'inviteCode': code,
    };

void main() {
  late _Api api;

  setUp(() => api = _Api());

  test('registers every /auth endpoint of the contract', () {
    expect(
      api.backend.routes,
      containsAll(<String>[
        'POST /auth/register',
        'POST /auth/login',
        'POST /auth/refresh',
        'POST /auth/logout',
        'POST /auth/verify-email',
        'POST /auth/resend-verification',
        'POST /auth/forgot-password',
        'POST /auth/reset-password',
        'POST /auth/change-password',
        'GET /auth/me',
      ]),
    );
  });

  group('POST /auth/register', () {
    test('create mode → 201 with a new family and its admin', () async {
      final res = await api.call('POST', '/auth/register', body: _createBody());
      expect(res.status, 201);
      final data = res.data! as Map<String, dynamic>;

      final user = AuthUser.fromJson(data['user'] as Map<String, dynamic>);
      expect(user.name, 'Neha Gupta');
      expect(user.email, 'new@example.com');
      expect(user.emailVerified, isFalse);
      expect(user.locale, 'hi');
      expect(user.role, MemberRole.admin);
      expect((data['user'] as Map).containsKey('password'), isFalse);

      final family = Family.fromJson(data['family'] as Map<String, dynamic>);
      expect(family.name, 'Gupta Family');
      expect(family.country, 'DE');
      expect(family.currency, 'EUR');
      expect(family.timezone, 'Europe/Berlin');
      expect(family.ownerId, user.id);
      expect(family.memberCount, 1);
      expect(family.inviteCode, hasLength(8));
      expect(
        family.inviteCode!.split('').every(Validators.inviteAlphabet.contains),
        isTrue,
      );

      final member = Member.fromJson(data['member'] as Map<String, dynamic>);
      expect(member.role, MemberRole.admin);
      expect(member.designation, AuthMockRules.ownerDesignation);
      expect(member.hasAccount, isTrue);
      expect(member.locationSharing, LocationSharingMode.never);
      expect(user.memberId, member.id);
      expect(user.familyId, family.id);

      // The access token works and a verification code was "sent".
      final me = await api.ok('GET', '/auth/me', userId: user.id);
      expect((me['family'] as Map)['id'], family.id);
      expect(
        api.db.count(
          MockDb.otps,
          (o) =>
              o['userId'] == user.id &&
              o['purpose'] == AuthMockRules.purposeVerifyEmail,
        ),
        1,
      );
    });

    test(
      'join mode (code case-insensitive, dashes ignored) → member',
      () async {
        final data = await api.ok(
          'POST',
          '/auth/register',
          body: _joinBody('demo-2345'),
        );
        final member = Member.fromJson(data['member'] as Map<String, dynamic>);
        expect(member.familyId, MockSeed.familyId);
        expect(member.role, MemberRole.member);
        expect(member.designation, isNull);
        // Invite codes are only shown to admins.
        expect((data['family'] as Map)['inviteCode'], isNull);
        expect(api.db.count(MockDb.members), 6);
      },
    );

    test('join links the pre-added member with the same email', () async {
      final data = await api.ok(
        'POST',
        '/auth/register',
        body: _joinBody(MockSeed.inviteCode, email: ' AARAV@familyhub.app '),
      );
      final member = Member.fromJson(data['member'] as Map<String, dynamic>);
      expect(member.id, MockSeed.aaravMemberId);
      expect(member.name, 'Aarav'); // the admin's profile is kept
      expect(member.hasAccount, isTrue);
      expect(api.db.count(MockDb.members), 5); // no duplicate
      final user = data['user'] as Map<String, dynamic>;
      expect(user['memberId'], MockSeed.aaravMemberId);
    });

    test('existing email → 409 EMAIL_TAKEN (case-insensitive)', () async {
      final e = await api.error(
        'POST',
        '/auth/register',
        body: _createBody(email: ' Demo@FamilyHub.app '),
      );
      expect(e.status, 409);
      expect(e.code, 'EMAIL_TAKEN');
    });

    test('unknown invite code → 400 INVALID_INVITE_CODE', () async {
      final e = await api.error(
        'POST',
        '/auth/register',
        body: _joinBody('ZZZZ9999'),
      );
      expect(e.status, 400);
      expect(e.code, 'INVALID_INVITE_CODE');
      expect(api.db.count(MockDb.users), 2); // nothing was created
    });

    test('invalid body → 422 with field details, nothing created', () async {
      final e = await api.error(
        'POST',
        '/auth/register',
        body: _createBody(
          email: 'nope',
          password: 'short',
          consent: false,
          dateOfBirth: '2999-01-01T00:00:00.000Z',
          family: {
            'name': '',
            'country': 'XX',
            'currency': 'E',
            'timezone': '',
          },
        ),
      );
      expect(e.status, 422);
      expect(e.code, 'VALIDATION_ERROR');
      expect(
        e.details!.keys,
        containsAll(<String>[
          'email',
          'password',
          'consentAccepted',
          'dateOfBirth',
          'family.name',
          'family.country',
          'family.currency',
          'family.timezone',
        ]),
      );
      expect(api.db.count(MockDb.families), 1);
    });

    test('password needs a letter and a digit; join needs a code', () async {
      final weak = await api.error(
        'POST',
        '/auth/register',
        body: _createBody(password: '12345678'),
      );
      expect(weak.details!.keys, contains('password'));
      final noCode = await api.error(
        'POST',
        '/auth/register',
        body: _joinBody('')..['inviteCode'] = null,
      );
      expect(noCode.details!.keys, contains('inviteCode'));
    });
  });

  group('POST /auth/login lockout', () {
    test('5 failures lock the email for 15 minutes', () async {
      for (var i = 0; i < AuthMockRules.maxFailedLogins - 1; i++) {
        final e = await api.login(MockSeed.demoEmail, 'wrong-pass1');
        expect(e.code, 'INVALID_CREDENTIALS');
        expect(e.status, 401);
      }
      final locked = await api.login(MockSeed.demoEmail, 'wrong-pass1');
      expect(locked.status, 429);
      expect(locked.code, 'TOO_MANY_REQUESTS');
      expect(locked.details!['retryAfterSeconds'], 15 * 60);

      // Even the right password is refused while locked.
      api.advance(const Duration(minutes: 5));
      final still = await api.login(MockSeed.demoEmail, MockSeed.demoPassword);
      expect(still.code, 'TOO_MANY_REQUESTS');
      expect(still.details!['retryAfterSeconds'], 10 * 60);

      api.advance(const Duration(minutes: 10));
      final data = await api.ok(
        'POST',
        '/auth/login',
        body: {'email': MockSeed.demoEmail, 'password': MockSeed.demoPassword},
      );
      expect((data['user'] as Map)['id'], MockSeed.amitUserId);
    });

    test('a successful login resets the counter', () async {
      for (var i = 0; i < 4; i++) {
        await api.login(MockSeed.demoEmail, 'wrong-pass1');
      }
      await api.ok(
        'POST',
        '/auth/login',
        body: {'email': MockSeed.demoEmail, 'password': MockSeed.demoPassword},
      );
      for (var i = 0; i < 4; i++) {
        final e = await api.login(MockSeed.demoEmail, 'wrong-pass1');
        expect(e.code, 'INVALID_CREDENTIALS');
      }
    });

    test('failures outside the 15-minute window do not add up', () async {
      for (var i = 0; i < 4; i++) {
        await api.login(MockSeed.demoEmail, 'wrong-pass1');
      }
      api.advance(const Duration(minutes: 16));
      final e = await api.login(MockSeed.demoEmail, 'wrong-pass1');
      expect(e.code, 'INVALID_CREDENTIALS');
    });

    test(
      'unknown emails lock exactly like real ones (no enumeration)',
      () async {
        MockException? last;
        for (var i = 0; i < AuthMockRules.maxFailedLogins; i++) {
          last = await api.login('ghost@example.com', 'whatever1');
        }
        expect(last!.code, 'TOO_MANY_REQUESTS');
      },
    );
  });

  group('email verification', () {
    late String userId;

    setUp(() async {
      final data = await api.ok('POST', '/auth/register', body: _createBody());
      userId = (data['user'] as Map)['id'] as String;
    });

    Future<MockException> verifyError(String otp) => api.error(
      'POST',
      '/auth/verify-email',
      body: {'otp': otp},
      userId: userId,
    );

    test('wrong code → INVALID_OTP; the right one verifies', () async {
      expect((await verifyError('000000')).code, 'INVALID_OTP');
      final data = await api.ok(
        'POST',
        '/auth/verify-email',
        body: {'otp': AuthMockRules.otp},
        userId: userId,
      );
      expect((data['user'] as Map)['emailVerified'], isTrue);
      // Idempotent afterwards.
      final again = await api.ok(
        'POST',
        '/auth/verify-email',
        body: {'otp': '999999'},
        userId: userId,
      );
      expect((again['user'] as Map)['emailVerified'], isTrue);
    });

    test('5 wrong codes → INVALID_OTP, then the code is burnt', () async {
      for (var i = 0; i < AuthMockRules.otpMaxAttempts; i++) {
        expect((await verifyError('000000')).code, 'INVALID_OTP');
      }
      expect((await verifyError(AuthMockRules.otp)).code, 'OTP_EXPIRED');
    });

    test('spaces and dashes in the code are ignored', () async {
      final data = await api.ok(
        'POST',
        '/auth/verify-email',
        body: {'otp': '123-456'},
        userId: userId,
      );
      expect((data['user'] as Map)['emailVerified'], isTrue);
    });

    test('codes expire after 10 minutes', () async {
      api.advance(const Duration(minutes: 11));
      expect((await verifyError(AuthMockRules.otp)).code, 'OTP_EXPIRED');
    });

    test('malformed code → 422', () async {
      final e = await verifyError('12ab');
      expect(e.code, 'VALIDATION_ERROR');
      expect(e.details!.keys, contains('otp'));
    });

    test('resend honours the 60 s cooldown, then issues a new code', () async {
      final early = await api.error(
        'POST',
        '/auth/resend-verification',
        userId: userId,
      );
      expect(early.status, 429);
      final wait = early.details!['retryAfterSeconds'] as int;
      expect(wait, inInclusiveRange(1, 60));

      api.advance(const Duration(seconds: 61));
      final data = await api.ok(
        'POST',
        '/auth/resend-verification',
        userId: userId,
      );
      expect(data, {'sent': true, 'retryAfterSeconds': 60});

      // The expired window restarted with the new code.
      api.advance(const Duration(minutes: 9));
      final verified = await api.ok(
        'POST',
        '/auth/verify-email',
        body: {'otp': AuthMockRules.otp},
        userId: userId,
      );
      expect((verified['user'] as Map)['emailVerified'], isTrue);
    });

    test('requires authentication', () async {
      final e = await api.error('POST', '/auth/resend-verification');
      expect(e.status, 401);
      expect(e.code, 'UNAUTHORIZED');
    });
  });

  group('password reset', () {
    Future<Map<String, dynamic>> reset(String otp, String password) => api.ok(
      'POST',
      '/auth/reset-password',
      body: {'email': MockSeed.demoEmail, 'otp': otp, 'newPassword': password},
    );

    test('forgot-password always answers sent (no enumeration)', () async {
      final unknown = await api.ok(
        'POST',
        '/auth/forgot-password',
        body: {'email': 'ghost@example.com'},
      );
      expect(unknown, {'sent': true});
      // A never-sent decoy, so reset answers like for a real account.
      expect(api.db.count(MockDb.otps, (o) => o['userId'] == null), 1);

      final known = await api.ok(
        'POST',
        '/auth/forgot-password',
        body: {'email': ' DEMO@familyhub.app'},
      );
      expect(known, {'sent': true});
      expect(api.db.count(MockDb.otps), 2);
    });

    test('reset sets the password and revokes every session', () async {
      final login = await api.ok(
        'POST',
        '/auth/login',
        body: {'email': MockSeed.demoEmail, 'password': MockSeed.demoPassword},
      );
      final refresh = (login['tokens'] as Map)['refreshToken'];
      await api.ok(
        'POST',
        '/auth/forgot-password',
        body: {'email': MockSeed.demoEmail},
      );

      final wrong = await api.error(
        'POST',
        '/auth/reset-password',
        body: {
          'email': MockSeed.demoEmail,
          'otp': '000000',
          'newPassword': 'brandnew1',
        },
      );
      expect(wrong.code, 'INVALID_OTP');

      expect(await reset(AuthMockRules.otp, 'brandnew1'), {'reset': true});

      final revoked = await api.error(
        'POST',
        '/auth/refresh',
        body: {'refreshToken': refresh},
      );
      expect(revoked.code, 'INVALID_REFRESH_TOKEN');
      expect(
        (await api.login(MockSeed.demoEmail, MockSeed.demoPassword)).code,
        'INVALID_CREDENTIALS',
      );
      await api.ok(
        'POST',
        '/auth/login',
        body: {'email': MockSeed.demoEmail, 'password': 'brandnew1'},
      );
    });

    test('unknown emails answer exactly like real ones', () async {
      Future<String> resetCode(String email) async => (await api.error(
        'POST',
        '/auth/reset-password',
        body: {
          'email': email,
          'otp': AuthMockRules.otp,
          'newPassword': 'brandnew1',
        },
      )).code;

      // Nothing requested yet.
      expect(await resetCode('ghost@example.com'), 'OTP_EXPIRED');
      // After forgot-password: 5 × INVALID_OTP (the decoy never matches),
      // then OTP_EXPIRED.
      await api.ok(
        'POST',
        '/auth/forgot-password',
        body: {'email': 'ghost@example.com'},
      );
      for (var i = 0; i < AuthMockRules.otpMaxAttempts; i++) {
        expect(await resetCode('ghost@example.com'), 'INVALID_OTP');
      }
      expect(await resetCode('ghost@example.com'), 'OTP_EXPIRED');
      expect(api.db.count(MockDb.users), 2);
    });

    test('weak new password → 422 newPassword', () async {
      final e = await api.error(
        'POST',
        '/auth/reset-password',
        body: {
          'email': MockSeed.demoEmail,
          'otp': AuthMockRules.otp,
          'newPassword': 'abc',
        },
      );
      expect(e.details!.keys, contains('newPassword'));
    });
  });

  group('POST /auth/change-password', () {
    Future<MockException> change(String current, String next) => api.error(
      'POST',
      '/auth/change-password',
      body: {'currentPassword': current, 'newPassword': next},
      userId: MockSeed.amitUserId,
    );

    test('wrong current password → 401 INVALID_CREDENTIALS and counts '
        'towards the lockout', () async {
      for (var i = 0; i < AuthMockRules.maxFailedLogins - 1; i++) {
        final e = await change('nope1234', 'brandnew1');
        expect(e.status, 401);
        expect(e.code, 'INVALID_CREDENTIALS');
      }
      final locked = await change('nope1234', 'brandnew1');
      expect(locked.code, 'TOO_MANY_REQUESTS');
      expect(
        (await api.login(MockSeed.demoEmail, MockSeed.demoPassword)).code,
        'TOO_MANY_REQUESTS',
      );
    });

    test('weak or unchanged new password → 422', () async {
      expect(
        (await change(MockSeed.demoPassword, 'weak')).code,
        'VALIDATION_ERROR',
      );
      expect(
        (await change(MockSeed.demoPassword, MockSeed.demoPassword)).code,
        'VALIDATION_ERROR',
      );
    });

    test(
      'changes the password, ends other sessions, returns new tokens',
      () async {
        final login = await api.ok(
          'POST',
          '/auth/login',
          body: {
            'email': MockSeed.demoEmail,
            'password': MockSeed.demoPassword,
          },
        );
        final oldRefresh = (login['tokens'] as Map)['refreshToken'];

        final data = await api.ok(
          'POST',
          '/auth/change-password',
          body: {
            'currentPassword': MockSeed.demoPassword,
            'newPassword': 'brandnew1',
          },
          userId: MockSeed.amitUserId,
        );
        expect(data['changed'], isTrue);
        final tokens = AuthTokens.fromJson(
          (data['tokens'] as Map).cast<String, dynamic>(),
        );
        expect(
          (await api.error(
            'POST',
            '/auth/refresh',
            body: {'refreshToken': oldRefresh},
          )).code,
          'INVALID_REFRESH_TOKEN',
        );
        await api.ok(
          'POST',
          '/auth/refresh',
          body: {'refreshToken': tokens.refreshToken},
        );
        await api.ok(
          'POST',
          '/auth/login',
          body: {'email': MockSeed.demoEmail, 'password': 'brandnew1'},
        );
      },
    );
  });

  group('logout and me', () {
    test('logout revokes the refresh token and removes the device', () async {
      final login = await api.ok(
        'POST',
        '/auth/login',
        body: {'email': MockSeed.demoEmail, 'password': MockSeed.demoPassword},
      );
      final refresh = (login['tokens'] as Map)['refreshToken'] as String;
      api.db
        ..insert(MockDb.devices, {
          'userId': MockSeed.amitUserId,
          'token': 'device-1',
        })
        ..insert(MockDb.devices, {
          'userId': MockSeed.priyaUserId,
          'token': 'device-2',
        });

      await api.ok(
        'POST',
        '/auth/logout',
        body: {'refreshToken': refresh, 'deviceToken': 'device-1'},
        userId: MockSeed.amitUserId,
      );
      expect(
        (await api.error(
          'POST',
          '/auth/refresh',
          body: {'refreshToken': refresh},
        )).code,
        'INVALID_REFRESH_TOKEN',
      );
      expect(api.db.count(MockDb.devices), 1);
    });

    test('me → { user, member, family }; 401 without a token', () async {
      final me = await api.ok('GET', '/auth/me', userId: MockSeed.priyaUserId);
      final session = SessionState.fromJson(me);
      expect(session.isComplete, isTrue);
      expect(session.member?.id, MockSeed.priyaMemberId);
      final e = await api.error('GET', '/auth/me');
      expect(e.status, 401);
    });
  });

  group('register: consent age and duplicates', () {
    String dobYearsAgo(int years) {
      final now = DateTime.now();
      return MockDb.iso(DateTime(now.year - years, now.month, now.day));
    }

    test(
      'under the country consent age → 422 GUARDIAN_CONSENT_REQUIRED',
      () async {
        final india = await api.error(
          'POST',
          '/auth/register',
          body: _createBody(
            dateOfBirth: dobYearsAgo(15),
            family: {
              'name': 'Young Family',
              'country': 'IN', // consent age 18
              'currency': 'INR',
              'timezone': 'Asia/Kolkata',
            },
          ),
        );
        expect(india.status, 422);
        expect(india.code, 'GUARDIAN_CONSENT_REQUIRED');
        expect(india.details!['consentAge'], 18);
        expect(api.db.count(MockDb.users), 2); // nothing created

        // 15 is old enough in the US (13).
        await api.ok(
          'POST',
          '/auth/register',
          body: _createBody(
            dateOfBirth: dobYearsAgo(15),
            family: {
              'name': 'Young Family',
              'country': 'US',
              'currency': 'USD',
              'timezone': 'America/New_York',
            },
          ),
        );
      },
    );

    test(
      'join uses the family country; a consented profile may link',
      () async {
        final minor = await api.error(
          'POST',
          '/auth/register',
          body: {
            ..._joinBody(MockSeed.inviteCode),
            'dateOfBirth': dobYearsAgo(12),
          },
        );
        expect(minor.code, 'GUARDIAN_CONSENT_REQUIRED');

        // Aarav (16) was pre-added with guardian consent by an admin.
        final data = await api.ok(
          'POST',
          '/auth/register',
          body: {
            ..._joinBody(MockSeed.inviteCode, email: MockSeed.aaravEmail),
            'dateOfBirth': dobYearsAgo(16),
          },
        );
        expect((data['member'] as Map)['id'], MockSeed.aaravMemberId);
      },
    );

    test('a family profile with that email and an account → '
        'MEMBER_EMAIL_EXISTS, nothing left behind', () async {
      api.db.update(MockDb.members, MockSeed.kamlaMemberId, {
        'email': 'kamla@example.com',
        'userId': 'someone-else',
      });
      final e = await api.error(
        'POST',
        '/auth/register',
        body: _joinBody(MockSeed.inviteCode, email: 'kamla@example.com'),
      );
      expect(e.status, 409);
      expect(e.code, 'MEMBER_EMAIL_EXISTS');
      expect(
        api.db.exists(MockDb.users, (u) => u['email'] == 'kamla@example.com'),
        isFalse,
      );
    });
  });

  // Parity with the hardened server (docs/progress/b-auth.md, "Hardening
  // review"): the mock must answer like the backend.
  group('hardening: server parity', () {
    Future<String> registerUser({String email = 'new@example.com'}) async {
      final data = await api.ok(
        'POST',
        '/auth/register',
        body: _createBody(email: email),
      );
      return (data['user'] as Map)['id'] as String;
    }

    Future<MockException> verifyError(String userId, String otp) => api.error(
      'POST',
      '/auth/verify-email',
      body: {'otp': otp},
      userId: userId,
    );

    String dobYearsAgo(int years) {
      final now = DateTime.now();
      return MockDb.iso(DateTime(now.year - years, now.month, now.day));
    }

    test('resend cooldown grows with the wrong codes: max(60 s, '
        'wrong × 3 min)', () async {
      final userId = await registerUser();
      api.advance(const Duration(seconds: 61));
      for (var i = 0; i < 2; i++) {
        expect((await verifyError(userId, '000000')).code, 'INVALID_OTP');
      }
      final early = await api.error(
        'POST',
        '/auth/resend-verification',
        userId: userId,
      );
      expect(early.status, 429);
      // 2 wrong codes → 6 min after the code was sent (61 s ago).
      expect(early.details!['retryAfterSeconds'], 6 * 60 - 61);
      expect(OtpRules.resendCooldownAfter(2), const Duration(minutes: 6));

      api.advance(const Duration(minutes: 5));
      final sent = await api.ok(
        'POST',
        '/auth/resend-verification',
        userId: userId,
      );
      expect(sent, {'sent': true, 'retryAfterSeconds': 60});
      // A fresh code starts with the plain 60 s again.
      final next = await api.error(
        'POST',
        '/auth/resend-verification',
        userId: userId,
      );
      expect(next.details!['retryAfterSeconds'], 60);
    });

    test('5 wrong codes → OTP_EXPIRED and a 15-minute resend wait', () async {
      final userId = await registerUser();
      for (var i = 0; i < AuthMockRules.otpMaxAttempts; i++) {
        expect((await verifyError(userId, '000000')).code, 'INVALID_OTP');
      }
      expect(
        (await verifyError(userId, AuthMockRules.otp)).code,
        'OTP_EXPIRED',
      );
      final wait = await api.error(
        'POST',
        '/auth/resend-verification',
        userId: userId,
      );
      expect(wait.details!['retryAfterSeconds'], 15 * 60);
    });

    test('forgot-password inside a grown cooldown sends nothing; the live '
        'code keeps working', () async {
      Map<String, dynamic> body(String otp) => {
        'email': MockSeed.demoEmail,
        'otp': otp,
        'newPassword': 'brandnew1',
      };
      await api.ok(
        'POST',
        '/auth/forgot-password',
        body: {'email': MockSeed.demoEmail},
      );
      final wrong = await api.error(
        'POST',
        '/auth/reset-password',
        body: body('000000'),
      );
      expect(wrong.code, 'INVALID_OTP');

      // > 60 s but < 3 min (1 wrong code): still `sent`, nothing re-sent.
      api.advance(const Duration(minutes: 2));
      expect(
        await api.ok(
          'POST',
          '/auth/forgot-password',
          body: {'email': MockSeed.demoEmail},
        ),
        {'sent': true},
      );
      final row = api.db.findOne(
        MockDb.otps,
        (o) =>
            o['email'] == MockSeed.demoEmail &&
            o['purpose'] == AuthMockRules.purposeResetPassword,
      );
      expect(row?['attempts'], 1);
      expect(
        await api.ok('POST', '/auth/reset-password', body: body(MockSeed.otp)),
        {'reset': true},
      );
    });

    test('native digits are accepted in codes and invite codes', () async {
      final data = await api.ok(
        'POST',
        '/auth/register',
        body: _joinBody('demo-२३४५', email: 'native@example.com'),
      );
      expect((data['family'] as Map)['id'], MockSeed.familyId);
      final userId = (data['user'] as Map)['id'] as String;

      final verified = await api.ok(
        'POST',
        '/auth/verify-email',
        body: {'otp': '١٢٣ ٤٥٦'},
        userId: userId,
      );
      expect((verified['user'] as Map)['emailVerified'], isTrue);
      // Absurdly long input is rejected before normalising.
      final long = await verifyError(userId, '1' * 65);
      expect(long.code, 'VALIDATION_ERROR');
    });

    test('names: no control / bidi-override characters, something '
        'visible', () async {
      final rlo = String.fromCharCode(0x202E);
      final zeroWidth = String.fromCharCode(0x200B);
      final filler = String.fromCharCode(0x3164);
      for (final bad in [
        'Amit${rlo}ahsm',
        '$zeroWidth$filler',
        'Amit\tSharma',
      ]) {
        final e = await api.error(
          'POST',
          '/auth/register',
          body: {..._createBody(), 'name': bad},
        );
        expect(e.details!.keys, contains('name'), reason: bad);
      }
      final family = await api.error(
        'POST',
        '/auth/register',
        body: _createBody(
          family: {
            'name': zeroWidth,
            'country': 'IN',
            'currency': 'INR',
            'timezone': 'Asia/Kolkata',
          },
        ),
      );
      expect(family.details!.keys, contains('family.name'));

      // Every script, emoji and ZWJ sequences stay allowed.
      final ok = await api.ok(
        'POST',
        '/auth/register',
        body: {..._createBody(), 'name': 'अमित 👨‍👩‍👧'},
      );
      expect((ok['user'] as Map)['name'], 'अमित 👨‍👩‍👧');
    });

    test('new passwords are limited to 72 UTF-8 bytes', () async {
      // 26 Devanagari letters (3 bytes each) + a digit = 79 bytes.
      final tooLong = '${'क' * 26}1';
      expect(AuthInputs.passwordTooLong(tooLong), isTrue);
      final e = await api.error(
        'POST',
        '/auth/register',
        body: _createBody(password: tooLong),
      );
      expect(e.details!['password'], 'Password is too long');

      // 23 × 3 + 2 = 71 bytes.
      await api.ok(
        'POST',
        '/auth/register',
        body: _createBody(password: '${'क' * 23}a1'),
      );
    });

    test('dates of birth: ISO with an offset, calendar-checked, from 1900, '
        'not in the future', () async {
      final future = MockDb.iso(api.now.add(const Duration(days: 3)));
      for (final bad in [
        '2010-02-31',
        '2010-05-14T00:00:00', // no offset: ambiguous
        '1899-12-31',
        'yesterday',
        future,
      ]) {
        final e = await api.error(
          'POST',
          '/auth/register',
          body: _createBody(dateOfBirth: bad),
        );
        expect(e.details!.keys, contains('dateOfBirth'), reason: bad);
      }
      // Local midnight as UTC (what the app sends) and plain dates pass.
      await api.ok(
        'POST',
        '/auth/register',
        body: _createBody(
          email: 'd1@example.com',
          dateOfBirth: '1990-05-13T18:30:00.000Z',
        ),
      );
      await api.ok(
        'POST',
        '/auth/register',
        body: _createBody(email: 'd2@example.com', dateOfBirth: '1990-05-14'),
      );
    });

    test('logout: a late replay of the token is a plain '
        'INVALID_REFRESH_TOKEN and other devices stay signed in', () async {
      Future<String> login() async {
        final data = await api.ok(
          'POST',
          '/auth/login',
          body: {
            'email': MockSeed.demoEmail,
            'password': MockSeed.demoPassword,
          },
        );
        return (data['tokens'] as Map)['refreshToken'] as String;
      }

      final phone = await login();
      final tablet = await login();
      await api.ok(
        'POST',
        '/auth/logout',
        body: {'refreshToken': phone},
        userId: MockSeed.amitUserId,
      );
      // A refresh that was still in flight replays the logged-out token.
      final replay = await api.error(
        'POST',
        '/auth/refresh',
        body: {'refreshToken': phone},
      );
      expect(replay.code, 'INVALID_REFRESH_TOKEN');
      // No reuse detection: the tablet keeps its session.
      await api.ok('POST', '/auth/refresh', body: {'refreshToken': tablet});

      final missing = await api.error(
        'POST',
        '/auth/logout',
        body: {},
        userId: MockSeed.amitUserId,
      );
      expect(missing.code, 'VALIDATION_ERROR');
    });

    test('verify-email checks the code format before the idempotent '
        'answer', () async {
      final bad = await verifyError(MockSeed.amitUserId, 'abc');
      expect(bad.code, 'VALIDATION_ERROR');
      final ok = await api.ok(
        'POST',
        '/auth/verify-email',
        body: {'otp': '999999'},
        userId: MockSeed.amitUserId,
      );
      expect((ok['user'] as Map)['emailVerified'], isTrue);
    });

    test('a decoy code never resets a password (INVALID_OTP)', () async {
      const email = 'late@example.com';
      await api.ok('POST', '/auth/forgot-password', body: {'email': email});
      final decoy =
          api.db.findOne(MockDb.otps, (o) => o['email'] == email)!['code']
              as String;
      // The address registers after the (never sent) decoy was made.
      await registerUser(email: email);
      final e = await api.error(
        'POST',
        '/auth/reset-password',
        body: {'email': email, 'otp': decoy, 'newPassword': 'brandnew1'},
      );
      expect(e.code, 'INVALID_OTP');
    });

    test('reset-password drops a pending verification code and verifies '
        'the email', () async {
      const email = 'reset@example.com';
      final userId = await registerUser(email: email);
      await api.ok('POST', '/auth/forgot-password', body: {'email': email});
      await api.ok(
        'POST',
        '/auth/reset-password',
        body: {'email': email, 'otp': MockSeed.otp, 'newPassword': 'brandnew1'},
      );
      expect(api.db.count(MockDb.otps, (o) => o['email'] == email), 0);
      final me = await api.ok('GET', '/auth/me', userId: userId);
      expect((me['user'] as Map)['emailVerified'], isTrue);
    });

    test('EMAIL_TAKEN wins over a wrong invite code', () async {
      final e = await api.error(
        'POST',
        '/auth/register',
        body: _joinBody('ZZZZZZZZ', email: MockSeed.demoEmail),
      );
      expect(e.code, 'EMAIL_TAKEN');
    });

    test("join: the pre-added profile's date of birth decides the age "
        'gate', () async {
      // Kamla (1952, no account): a made-up young date does not block her.
      api.db.update(MockDb.members, MockSeed.kamlaMemberId, {
        'email': 'kamla@example.com',
      });
      final kamla = await api.ok(
        'POST',
        '/auth/register',
        body: {
          ..._joinBody(MockSeed.inviteCode, email: 'kamla@example.com'),
          'dateOfBirth': dobYearsAgo(10),
        },
      );
      expect((kamla['member'] as Map)['id'], MockSeed.kamlaMemberId);

      // A young profile without guardian consent: an adult date typed at
      // sign-up does not get around it.
      api.db.insert(MockDb.members, {
        'familyId': MockSeed.familyId,
        'userId': null,
        'name': 'Kid',
        'email': 'kid@example.com',
        'dateOfBirth': dobYearsAgo(10),
        'role': 'member',
        'guardianConsent': false,
      });
      final kid = await api.error(
        'POST',
        '/auth/register',
        body: {
          ..._joinBody(MockSeed.inviteCode, email: 'kid@example.com'),
          'dateOfBirth': dobYearsAgo(30),
        },
      );
      expect(kid.code, 'GUARDIAN_CONSENT_REQUIRED');
      expect(kid.details!['consentAge'], 18);
    });
  });
}
