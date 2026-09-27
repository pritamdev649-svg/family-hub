import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/config/countries.dart';
import 'package:family_hub/shared/models/auth_tokens.dart';
import 'package:family_hub/shared/models/auth_user.dart';
import 'package:family_hub/shared/models/family.dart';
import 'package:family_hub/shared/models/member.dart';
import 'package:family_hub/shared/models/session_state.dart';

Map<String, dynamic> memberJson([Map<String, dynamic> extra = const {}]) => {
  'id': '64f000000000000000000001',
  'familyId': '64f0000000000000000000ff',
  'userId': '64f0000000000000000000aa',
  'name': 'Aarav Sharma',
  'email': 'aarav@example.com',
  'phone': '+919876543210',
  'avatarUrl': 'https://res.cloudinary.com/demo/a.jpg',
  'dateOfBirth': '2010-05-14T00:00:00.000Z',
  'gender': 'male',
  'designation': 'Chief Study Officer',
  'role': 'member',
  'hasAccount': true,
  'locationSharing': 'sos_only',
  'lastLocation': {
    'lat': 28.61,
    'lng': 77.2,
    'accuracy': 12.5,
    'recordedAt': '2026-09-26T10:15:00.000Z',
  },
  'guardianConsent': true,
  'createdAt': '2026-01-01T00:00:00.000Z',
  'updatedAt': '2026-02-01T00:00:00.000Z',
  ...extra,
};

Map<String, dynamic> userJson([Map<String, dynamic> extra = const {}]) => {
  'id': 'u1',
  'email': ' Amit@Example.com ',
  'name': 'Amit Sharma',
  'emailVerified': true,
  'locale': 'hi',
  'familyId': 'f1',
  'memberId': 'm1',
  'role': 'admin',
  'createdAt': '2026-01-01T00:00:00.000Z',
  ...extra,
};

Map<String, dynamic> familyJson([Map<String, dynamic> extra = const {}]) => {
  'id': 'f1',
  'name': 'Sharma Family',
  'inviteCode': 'k7q2m9xd',
  'country': 'IN',
  'currency': 'INR',
  'timezone': 'Asia/Kolkata',
  'ownerId': 'u1',
  'memberCount': 5,
  'createdAt': '2026-01-01T00:00:00.000Z',
  ...extra,
};

void main() {
  group('Member', () {
    test('parses the full contract shape', () {
      final m = Member.fromJson(memberJson());
      expect(m.id, '64f000000000000000000001');
      expect(m.name, 'Aarav Sharma');
      expect(m.gender, Gender.male);
      expect(m.role, MemberRole.member);
      expect(m.isAdmin, isFalse);
      expect(m.hasAccount, isTrue);
      expect(m.locationSharing, LocationSharingMode.sosOnly);
      expect(
        m.lastLocation,
        GeoPoint(
          lat: 28.61,
          lng: 77.2,
          accuracy: 12.5,
          recordedAt: DateTime.utc(2026, 9, 26, 10, 15),
        ),
      );
      expect(m.dateOfBirth, DateTime.utc(2010, 5, 14));
      expect(m.birthDate, DateTime(2010, 5, 14));
      expect(m.guardianConsent, isTrue);
    });

    test('survives an empty object with safe defaults', () {
      final m = Member.fromJson(const {});
      expect(m.id, '');
      expect(m.name, '');
      expect(m.userId, isNull);
      expect(m.email, isNull);
      expect(m.gender, isNull);
      expect(m.role, MemberRole.member);
      expect(m.hasAccount, isFalse);
      expect(m.locationSharing, LocationSharingMode.never);
      expect(m.lastLocation, isNull);
      expect(m.dateOfBirth, isNull);
      expect(m.age, isNull);
      expect(m.ageGroup, isNull);
      expect(m.guardianConsent, isFalse);
      expect(m.initials, '?');
    });

    test('unknown enums, wrong types, blanks and extra fields never throw', () {
      final m = Member.fromJson(
        memberJson({
          'role': 'owner',
          'gender': 'robot',
          'locationSharing': 'sometimes',
          'hasAccount': 'yes',
          'guardianConsent': 1,
          'dateOfBirth': 'yesterday',
          'lastLocation': {'lat': 'abc', 'lng': 77},
          'email': '',
          'phone': '   ',
          'designation': null,
          'extraField': {'nested': true},
          '__v': 3,
        }),
      );
      expect(m.role, MemberRole.member);
      expect(m.gender, isNull);
      expect(m.locationSharing, LocationSharingMode.never);
      expect(m.hasAccount, isTrue);
      expect(m.guardianConsent, isTrue);
      expect(m.dateOfBirth, isNull);
      expect(m.lastLocation, isNull);
      expect(m.email, isNull);
      expect(m.phone, isNull);
      expect(m.designation, isNull);
    });

    test('accepts _id and derives hasAccount from userId when missing', () {
      final json = memberJson()
        ..remove('id')
        ..remove('hasAccount')
        ..['_id'] = 'legacy';
      final m = Member.fromJson(json);
      expect(m.id, 'legacy');
      expect(m.hasAccount, isTrue);
      final managed = Member.fromJson(
        memberJson({'userId': null})..remove('hasAccount'),
      );
      expect(managed.hasAccount, isFalse);
      expect(managed.isManagedProfile, isTrue);
    });

    test('snake_case round trip through toJson', () {
      final m = Member.fromJson(memberJson({'locationSharing': 'always'}));
      final json = m.toJson();
      expect(json['locationSharing'], 'always');
      expect(
        Member.fromJson(
          m.copyWith(locationSharing: LocationSharingMode.sosOnly).toJson(),
        ).toJson()['locationSharing'],
        'sos_only',
      );
      expect(json['role'], 'member');
      expect(json['gender'], 'male');
      expect(json['dateOfBirth'], '2010-05-14T00:00:00.000Z');
      expect(Member.fromJson(json), m);
    });

    test('age, ageGroup and isMinorIn', () {
      Member bornOn(DateTime d) =>
          Member(id: 'x', familyId: 'f', name: 'X', dateOfBirth: d);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      final twelve = bornOn(DateTime(today.year - 12, today.month, today.day));
      expect(twelve.age, 12);
      expect(twelve.ageGroup, AgeGroup.child);

      final almost13 = bornOn(
        DateTime(
          today.year - 13,
          today.month,
          today.day,
        ).add(const Duration(days: 1)),
      );
      expect(almost13.age, 12);

      expect(
        bornOn(DateTime(today.year - 13, today.month, today.day)).ageGroup,
        AgeGroup.teen,
      );
      expect(
        bornOn(DateTime(today.year - 18, today.month, today.day)).ageGroup,
        AgeGroup.adult,
      );
      expect(
        bornOn(DateTime(today.year - 60, today.month, today.day)).ageGroup,
        AgeGroup.senior,
      );
      expect(bornOn(today.add(const Duration(days: 30))).age, isNull);

      final india = Countries.byCode('IN'); // consent age 18
      final us = Countries.byCode('US'); // consent age 13
      final fifteen = bornOn(DateTime(today.year - 15, today.month, today.day));
      expect(fifteen.isMinorIn(india), isTrue);
      expect(fifteen.isMinorIn(us), isFalse);
      expect(
        const Member(id: 'x', familyId: 'f', name: 'X').isMinorIn(india),
        isFalse,
      );
    });

    test('ageOn handles birthdays exactly', () {
      final m = Member(
        id: 'x',
        familyId: 'f',
        name: 'X',
        dateOfBirth: DateTime.utc(2010, 5, 14),
      );
      expect(m.ageOn(DateTime(2026, 5, 13)), 15);
      expect(m.ageOn(DateTime(2026, 5, 14)), 16);
      expect(m.ageOn(DateTime(2010, 5, 13)), isNull);
      expect(m.ageOn(DateTime(2010, 5, 14)), 0);
    });

    test('AgeGroup.forAge boundaries', () {
      expect(AgeGroup.forAge(0), AgeGroup.child);
      expect(AgeGroup.forAge(12), AgeGroup.child);
      expect(AgeGroup.forAge(13), AgeGroup.teen);
      expect(AgeGroup.forAge(17), AgeGroup.teen);
      expect(AgeGroup.forAge(18), AgeGroup.adult);
      expect(AgeGroup.forAge(59), AgeGroup.adult);
      expect(AgeGroup.forAge(60), AgeGroup.senior);
    });

    test('initials are grapheme-aware', () {
      expect(Member.initialsOf('amit sharma'), 'AS');
      expect(Member.initialsOf('  Priya  '), 'P');
      expect(Member.initialsOf('Kamla Devi Sharma'), 'KS');
      expect(Member.initialsOf('अमित शर्मा'), 'अश');
      expect(Member.initialsOf(''), '?');
      expect(Member.initialsOf(null), '?');
      // A vowel sign stays with its base consonant (one grapheme).
      expect(Member.initialsOf('கோபால்'), 'கோ');
    });

    test('copyWith can set and clear nullable fields', () {
      final m = Member.fromJson(memberJson());
      final cleared = m.copyWith(phone: () => null, gender: () => null);
      expect(cleared.phone, isNull);
      expect(cleared.gender, isNull);
      expect(cleared.email, m.email);
      final renamed = m.copyWith(name: 'Aarav S', role: MemberRole.admin);
      expect(renamed.name, 'Aarav S');
      expect(renamed.isAdmin, isTrue);
      expect(m.copyWith(), m);
      expect(m.copyWith().hashCode, m.hashCode);
      expect(renamed == m, isFalse);
    });

    test('compare orders admins first, then oldest, unknown DOB last', () {
      final a = Member.fromJson(
        memberJson({
          'id': 'a',
          'role': 'member',
          'dateOfBirth': '1952-01-01T00:00:00.000Z',
        }),
      );
      final b = Member.fromJson(
        memberJson({
          'id': 'b',
          'role': 'admin',
          'dateOfBirth': '1987-01-01T00:00:00.000Z',
        }),
      );
      final c = Member.fromJson(
        memberJson({'id': 'c', 'role': 'member', 'dateOfBirth': null}),
      );
      final d = Member.fromJson(
        memberJson({
          'id': 'd',
          'role': 'member',
          'dateOfBirth': '2016-01-01T00:00:00.000Z',
        }),
      );
      final sorted = [c, d, a, b]..sort(Member.compare);
      expect(sorted.map((m) => m.id), ['b', 'a', 'd', 'c']);
    });
  });

  group('GeoPoint', () {
    test('rejects out-of-range and missing coordinates', () {
      expect(GeoPoint.tryParse({'lat': 91, 'lng': 0}), isNull);
      expect(GeoPoint.tryParse({'lat': 0, 'lng': 181}), isNull);
      expect(GeoPoint.tryParse({'lat': 1}), isNull);
      expect(GeoPoint.tryParse('28.6,77.2'), isNull);
      expect(GeoPoint.tryParse(null), isNull);
    });

    test('parses strings, drops negative accuracy and bad list entries', () {
      final p = GeoPoint.tryParse({'lat': '28.6', 'lng': 77, 'accuracy': -1})!;
      expect(p.lat, 28.6);
      expect(p.lng, 77.0);
      expect(p.accuracy, isNull);
      expect(p.recordedAt, isNull);
      final list = GeoPoint.listFrom([
        {'lat': 1, 'lng': 2},
        null,
        {'lat': 'x', 'lng': 2},
        {'lat': 3, 'lng': 4, 'recordedAt': '2026-09-26T10:15:00.000Z'},
      ]);
      expect(list.length, 2);
      expect(GeoPoint.tryParse(list.last.toJson()), list.last);
    });
  });

  group('AuthUser', () {
    test('parses and normalises email', () {
      final u = AuthUser.fromJson(userJson());
      expect(u.email, 'amit@example.com');
      expect(u.role, MemberRole.admin);
      expect(u.isAdmin, isTrue);
      expect(u.hasFamily, isTrue);
      expect(AuthUser.fromJson(u.toJson()), u);
    });

    test('handles null family and unknown role', () {
      final u = AuthUser.fromJson(
        userJson({'familyId': null, 'memberId': null, 'role': 'boss'}),
      );
      expect(u.hasFamily, isFalse);
      expect(u.role, isNull);
      expect(u.isAdmin, isFalse);
      final empty = AuthUser.fromJson(const {});
      expect(empty.id, '');
      expect(empty.emailVerified, isFalse);
      expect(empty.locale, isNull);
    });

    test('copyWith clears family', () {
      final u = AuthUser.fromJson(userJson());
      final left = u.copyWith(
        familyId: () => null,
        memberId: () => null,
        role: () => null,
      );
      expect(left.hasFamily, isFalse);
      expect(left.role, isNull);
      expect(left.email, u.email);
    });
  });

  group('Family', () {
    test('parses and normalises codes', () {
      final f = Family.fromJson(
        familyJson({'country': 'in', 'currency': 'inr'}),
      );
      expect(f.inviteCode, 'K7Q2M9XD');
      expect(f.country, 'IN');
      expect(f.currency, 'INR');
      expect(f.memberCount, 5);
      expect(f.countryInfo.code, 'IN');
      expect(Family.fromJson(f.toJson()), f);
    });

    test('members get null invite code; missing fields have defaults', () {
      final f = Family.fromJson({
        'id': 'f',
        'name': 'X',
        'inviteCode': null,
        'country': 'US',
      });
      expect(f.inviteCode, isNull);
      expect(f.currency, 'USD');
      expect(f.timezone, 'UTC');
      expect(f.memberCount, 0);
      final empty = Family.fromJson(const {});
      expect(empty.country, Countries.fallback.code);
      expect(empty.currency, Countries.fallback.currency);
      expect(Family.fromJson({'memberCount': -3}).memberCount, 0);
    });
  });

  group('AuthTokens (re-exported from core/storage)', () {
    test('is available from shared/models and rejects half payloads', () {
      final t = AuthTokens.tryParse({
        'accessToken': 'secret-access',
        'refreshToken': 'secret-refresh',
        'expiresIn': 900,
      });
      expect(t, isNotNull);
      expect(t!.toString(), isNot(contains('secret')));
      expect(AuthTokens.tryParse({'accessToken': 'a'}), isNull);
      expect(AuthTokens.tryParse(null), isNull);
    });
  });

  group('SessionState', () {
    test('full session', () {
      final s = SessionState.fromJson({
        'user': userJson(),
        'member': memberJson({'role': 'admin'}),
        'family': familyJson(),
      });
      expect(s.isSignedIn, isTrue);
      expect(s.needsEmailVerification, isFalse);
      expect(s.needsFamily, isFalse);
      expect(s.isComplete, isTrue);
      expect(s.isAdmin, isTrue);
      expect(SessionState.fromJson(s.toJson()), s);
    });

    test('unverified user must verify first', () {
      final s = SessionState.fromJson({
        'user': userJson({'emailVerified': false}),
        'member': null,
        'family': null,
      });
      expect(s.needsEmailVerification, isTrue);
      expect(s.needsFamily, isFalse);
      expect(s.isComplete, isFalse);
    });

    test('verified user without family needs a family', () {
      final s = SessionState.fromJson({'user': userJson(), 'member': null});
      expect(s.needsFamily, isTrue);
      expect(s.member, isNull);
      expect(s.family, isNull);
    });

    test('half populated session drops member/family', () {
      final s = SessionState.fromJson({
        'user': userJson(),
        'member': memberJson(),
        'family': 'oops',
      });
      expect(s.member, isNull);
      expect(s.family, isNull);
      expect(s.needsFamily, isTrue);
    });

    test('missing or invalid user is signed out', () {
      expect(SessionState.fromJson(const {}), SessionState.signedOut);
      expect(SessionState.fromJson({'user': 'x'}), SessionState.signedOut);
      expect(
        SessionState.fromJson({'user': <String, dynamic>{}}),
        SessionState.signedOut,
      );
      expect(SessionState.signedOut.isSignedIn, isFalse);
      expect(SessionState.signedOut.needsFamily, isFalse);
      expect(SessionState.signedOut.isAdmin, isFalse);
    });
  });
}
