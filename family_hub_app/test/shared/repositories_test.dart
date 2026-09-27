import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/network/api_exception.dart';
import 'package:family_hub/shared/data/auth_repository.dart';
import 'package:family_hub/shared/data/family_repository.dart';
import 'package:family_hub/shared/data/me_repository.dart';
import 'package:family_hub/shared/data/repository_utils.dart';
import 'package:family_hub/shared/models/models.dart';

import 'models_test.dart' show familyJson, memberJson, userJson;
import 'shared_fakes.dart';

Matcher _apiError(String code) =>
    throwsA(isA<ApiException>().having((e) => e.code, 'code', code));

void main() {
  group('normalisers', () {
    test('email / phone / invite code / otp', () {
      expect(normalizeEmail('  A@B.Co '), 'a@b.co');
      expect(normalizeEmail('   '), isNull);
      expect(normalizePhone('+91 98765-43210'), '+919876543210');
      expect(normalizePhone('(022) 1234.5678'), '02212345678');
      expect(normalizePhone(' - '), isNull);
      expect(normalizeInviteCode(' k7q2-m9xd '), 'K7Q2M9XD');
      expect(normalizeOtp('12 34-56'), '123456');
    });

    test('pathId encodes and rejects blank ids', () {
      expect(pathId('abc'), 'abc');
      expect(pathId('a/b c'), 'a%2Fb%20c');
      expect(() => pathId('  '), _apiError(ApiErrorCode.notFound));
    });
  });

  group('request bodies', () {
    test('RegisterRequest.join sends normalised code and null family', () {
      const r = RegisterRequest.join(
        name: 'Priya',
        email: 'Priya@Example.com',
        password: ' keep spaces 1 ',
        locale: 'ta',
        consentAccepted: true,
        inviteCode: 'demo 2345',
      );
      final json = r.toJson();
      expect(json['mode'], 'join');
      expect(json['inviteCode'], 'DEMO2345');
      expect(json['family'], isNull);
      expect(json['password'], ' keep spaces 1 ');
      expect(json['dateOfBirth'], isNull);
      expect(r.toString(), isNot(contains('keep spaces')));
    });

    test('NewMemberRequest matches the contract example', () {
      final json = NewMemberRequest(
        name: ' Anaya ',
        email: '  ',
        phone: '',
        dateOfBirth: DateTime.utc(2016, 8, 1),
        gender: Gender.female,
        designation: 'Junior Explorer',
        guardianConsent: true,
      ).toJson();
      expect(json, {
        'name': 'Anaya',
        'email': null,
        'phone': null,
        'dateOfBirth': '2016-08-01T00:00:00.000Z',
        'gender': 'female',
        'designation': 'Junior Explorer',
        'role': 'member',
        'guardianConsent': true,
      });
    });

    test('MemberPatch sends only given fields and explicit clears', () {
      final p = MemberPatch(
        role: MemberRole.admin,
        phone: '  ',
        clear: {MemberPatchField.avatarUrl},
      );
      expect(p.toJson(), {'role': 'admin', 'avatarUrl': null});
      expect(MemberPatch().isEmpty, isTrue);
      expect(
        MemberPatch(
          role: MemberRole.admin,
          clear: {MemberPatchField.avatarUrl},
        ),
        p,
      );
      // A value wins over a clear of the same field.
      expect(
        MemberPatch(phone: '+1 555', clear: {MemberPatchField.phone}).toJson(),
        {'phone': '+1555'},
      );
    });

    test('MemberPatch.diff: changed, cleared and unchanged fields', () {
      final before = Member.fromJson(memberJson());
      final after = before.copyWith(
        name: 'Aarav  S ',
        phone: () => null,
        designation: () => 'Captain',
        role: MemberRole.admin,
        email: () => ' AARAV@example.com ', // same after normalisation
      );
      expect(MemberPatch.diff(before, after).toJson(), {
        'name': 'Aarav  S',
        'phone': null,
        'designation': 'Captain',
        'role': 'admin',
      });
      expect(MemberPatch.diff(before, before).isEmpty, isTrue);
    });

    test('MePatch uses wire names and diff clears', () {
      expect(
        MePatch(
          locationSharing: LocationSharingMode.sosOnly,
          locale: 'ar',
        ).toJson(),
        {'locale': 'ar', 'locationSharing': 'sos_only'},
      );
      final before = Member.fromJson(memberJson());
      final after = before.copyWith(avatarUrl: () => null, gender: () => null);
      expect(MePatch.diff(before, after).toJson(), {
        'avatarUrl': null,
        'gender': null,
      });
    });

    test('FamilyPatch.diff only sends real changes', () {
      final f = Family.fromJson(familyJson());
      expect(
        FamilyPatch.diff(f, name: 'Sharma Family', country: 'in').isEmpty,
        isTrue,
      );
      expect(
        FamilyPatch.diff(
          f,
          name: ' Sharmas ',
          currency: 'usd',
          timezone: '',
        ).toJson(),
        {'name': 'Sharmas', 'currency': 'USD'},
      );
    });
  });

  group('FamilyRepository', () {
    test('getMembers drops junk; malformed list → UNKNOWN', () async {
      final api = FakeApiClient({
        'GET /family/members': (_) => [
          memberJson(),
          null,
          {'name': 'x'},
        ],
      });
      final repo = FamilyRepository(api);
      expect((await repo.getMembers()).length, 1);
      api.on('GET /family/members', (_) => {'not': 'a list'});
      await expectLater(repo.getMembers(), _apiError(ApiErrorCode.unknown));
    });

    test('updateMember PATCHes the encoded path with the patch body', () async {
      final api = FakeApiClient({
        'PATCH /family/members/m1': (c) => memberJson({'id': 'm1', ...c.json}),
      });
      final m = await FamilyRepository(
        api,
      ).updateMember('m1', MemberPatch(designation: 'CFO'));
      expect(m.designation, 'CFO');
      expect(api.calls.single.json, {'designation': 'CFO'});
    });

    test('family responses are unwrapped from { family }', () async {
      final api = FakeApiClient({
        'GET /family': (_) => {'family': familyJson()},
        'POST /family/invite-code': (_) => {
          'family': familyJson({'inviteCode': 'ZZZZ2345'}),
        },
        'PATCH /family': (_) => {'wrong': true},
      });
      final repo = FamilyRepository(api);
      expect((await repo.getFamily()).id, 'f1');
      expect((await repo.regenerateInviteCode()).inviteCode, 'ZZZZ2345');
      await expectLater(
        repo.updateFamily(FamilyPatch(name: 'x')),
        _apiError(ApiErrorCode.unknown),
      );
    });

    test('joinFamily requires { user, family, member }', () async {
      final api = FakeApiClient({
        'POST /family/join': (_) => {'user': userJson()},
      });
      await expectLater(
        FamilyRepository(api).joinFamily('DEMO2345'),
        _apiError(ApiErrorCode.unknown),
      );
    });
  });

  group('AuthRepository', () {
    test('login stores tokens; missing tokens is malformed', () async {
      final tokens = FakeTokenStorage();
      final api = FakeApiClient({
        'POST /auth/login': (_) => {
          'user': userJson(),
          'tokens': {'accessToken': 'a', 'refreshToken': 'r'},
        },
      });
      final repo = AuthRepository(api, tokens);
      final res = await repo.login(email: 'x@y.z', password: 'p');
      expect(res.user.id, 'u1');
      expect(res.hasMembership, isFalse);
      expect(tokens.tokens?.refreshToken, 'r');

      api.on('POST /auth/login', (_) => {'user': userJson()});
      tokens.tokens = null;
      await expectLater(
        repo.login(email: 'x@y.z', password: 'p'),
        _apiError(ApiErrorCode.unknown),
      );
      expect(tokens.tokens, isNull, reason: 'nothing stored on bad payload');
    });

    test('logout without tokens skips the request but clears', () async {
      final tokens = FakeTokenStorage();
      final api = FakeApiClient();
      await AuthRepository(api, tokens).logout();
      expect(api.calls, isEmpty);
      expect(tokens.clears, 1);
    });

    test('resendVerification returns the cooldown', () async {
      final api = FakeApiClient({
        'POST /auth/resend-verification': (_) => {
          'sent': true,
          'retryAfterSeconds': 45,
        },
      });
      expect(
        await AuthRepository(api, FakeTokenStorage()).resendVerification(),
        45,
      );
      api.on('POST /auth/resend-verification', (_) => {'sent': true});
      expect(
        await AuthRepository(api, FakeTokenStorage()).resendVerification(),
        60,
      );
    });
  });

  group('MeRepository', () {
    test('updateMe returns user + member', () async {
      final api = FakeApiClient({
        'PATCH /me': (c) {
          expect(c.json, {'locationSharing': 'always'});
          return {
            'user': userJson(),
            'member': memberJson({'locationSharing': 'always'}),
          };
        },
      });
      final res = await MeRepository(
        api,
      ).updateMe(MePatch(locationSharing: LocationSharingMode.always));
      expect(res.user.id, 'u1');
      expect(res.member?.locationSharing, LocationSharingMode.always);
    });

    test('updateLocation validates and omits bad accuracy', () async {
      final api = FakeApiClient({
        'PUT /me/location': (_) => {'recordedAt': '2026-09-26T10:15:00.000Z'},
      });
      final repo = MeRepository(api);
      expect(
        await repo.updateLocation(lat: 28.6, lng: 77.2, accuracy: -5),
        DateTime.utc(2026, 9, 26, 10, 15),
      );
      expect(api.calls.single.json, {'lat': 28.6, 'lng': 77.2});
      expect(() => repo.updateLocation(lat: 91, lng: 0), throwsArgumentError);
      expect(
        () => repo.updateLocation(lat: 0, lng: double.nan),
        throwsArgumentError,
      );
    });

    test('device registration uses the contract body', () async {
      final api = FakeApiClient({
        'POST /me/devices': (_) => {'registered': true},
        'DELETE /me/devices/tok%3A1': (_) => null,
      });
      final repo = MeRepository(api);
      await repo.registerDevice(
        token: 'tok:1',
        platform: DevicePlatform.ios,
        locale: 'hi',
      );
      expect(api.calls.first.json, {
        'token': 'tok:1',
        'platform': 'ios',
        'locale': 'hi',
      });
      await repo.unregisterDevice('tok:1');
      expect(api.calls.last.path, '/me/devices/tok%3A1');
    });
  });
}
