import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/config/countries.dart';
import 'package:family_hub/features/family/domain/member_designation.dart';
import 'package:family_hub/features/family/domain/member_form_data.dart';
import 'package:family_hub/shared/models/member.dart';

import 'family_test_utils.dart';

final india = Countries.byCode('IN'); // consent age 18
final usa = Countries.byCode('US'); // consent age 13

void main() {
  group('Member parsing (contract JSON the family screens rely on)', () {
    test('full member → fields, age group, account status', () {
      final m = Member.fromJson({
        'id': 'm1',
        'familyId': 'f1',
        'userId': null,
        'name': ' Anaya ',
        'email': '',
        'phone': null,
        'dateOfBirth': '2016-08-01T00:00:00.000Z',
        'gender': 'female',
        'designation': 'Junior Explorer',
        'role': 'member',
        'hasAccount': false,
        'locationSharing': 'sos_only',
        'lastLocation': null,
        'guardianConsent': true,
        'extra': 'ignored',
      });
      expect(m.name, 'Anaya');
      expect(m.email, isNull);
      expect(m.birthDate, DateTime(2016, 8, 1));
      expect(m.locationSharing, LocationSharingMode.sosOnly);
      expect(m.accountStatus, MemberAccountStatus.managed);
      expect(m.isMinorIn(india), isTrue);
    });

    test('unknown enums fall back, account status follows email / user', () {
      final invited = Member.fromJson({
        'id': 'm2',
        'name': 'Aarav',
        'email': 'aarav@example.com',
        'role': 'boss',
        'gender': 'x',
        'locationSharing': 'sometimes',
      });
      expect(invited.role, MemberRole.member);
      expect(invited.gender, isNull);
      expect(invited.locationSharing, LocationSharingMode.never);
      expect(invited.accountStatus, MemberAccountStatus.invited);

      final active = Member.fromJson({'id': 'm3', 'name': 'A', 'userId': 'u'});
      expect(active.accountStatus, MemberAccountStatus.active);
    });
  });

  group('MemberFormAccess.resolve', () {
    test('admin adds, edits others, edits self without role', () {
      expect(
        MemberFormAccess.resolve(isAdmin: true, currentMemberId: 'a'),
        MemberFormAccess.adminAdd,
      );
      final other = MemberFormAccess.resolve(
        isAdmin: true,
        currentMemberId: amit.id,
        target: kamla,
      );
      expect(other, MemberFormAccess.adminEdit);
      expect(other.canEditRole, isTrue);
      final self = MemberFormAccess.resolve(
        isAdmin: true,
        currentMemberId: amit.id,
        target: amit,
      );
      expect(self, MemberFormAccess.adminEditSelf);
      expect(self.canEditRole, isFalse);
      expect(self.isAdminAccess, isTrue);
    });

    test('members may only edit themselves, never add', () {
      expect(
        MemberFormAccess.resolve(isAdmin: false, currentMemberId: kamla.id),
        MemberFormAccess.denied,
      );
      expect(
        MemberFormAccess.resolve(
          isAdmin: false,
          currentMemberId: kamla.id,
          target: amit,
        ),
        MemberFormAccess.denied,
      );
      final self = MemberFormAccess.resolve(
        isAdmin: false,
        currentMemberId: kamla.id,
        target: kamla,
      );
      expect(self, MemberFormAccess.selfEdit);
      expect(self.isAdminAccess, isFalse);
      expect(self.canEditEmail(kamla), isFalse);
    });

    test('an account holder email is read-only, a managed one editable', () {
      expect(MemberFormAccess.adminEdit.canEditEmail(kamla), isFalse);
      expect(MemberFormAccess.adminEdit.canEditEmail(anaya), isTrue);
      expect(MemberFormAccess.adminAdd.canEditEmail(null), isTrue);
    });
  });

  group('guardian consent rule', () {
    test('uses the country consent age and the calendar day', () {
      final today = DateTime(2026, 9, 26);
      final turns18Tomorrow = MemberFormData(birthDate: DateTime(2008, 9, 27));
      final turned18Today = MemberFormData(birthDate: DateTime(2008, 9, 26));
      expect(turns18Tomorrow.ageOn(today), 17);
      expect(turns18Tomorrow.needsGuardianConsent(india, today: today), isTrue);
      expect(turned18Today.needsGuardianConsent(india, today: today), isFalse);
      // 15-year-old: minor in India (18), not in the US (13).
      final teen = MemberFormData(birthDate: DateTime(2011, 1, 1));
      expect(teen.needsGuardianConsent(india, today: today), isTrue);
      expect(teen.needsGuardianConsent(usa, today: today), isFalse);
    });

    test('unknown or future dates of birth need no consent', () {
      expect(const MemberFormData().needsGuardianConsent(india), isFalse);
      final future = MemberFormData(
        birthDate: DateTime.now().add(const Duration(days: 30)),
      );
      expect(future.age, isNull);
      expect(future.needsGuardianConsent(india), isFalse);
    });
  });

  group('toNewMemberRequest', () {
    test('contract body; consent only recorded for minors', () {
      final child = MemberFormData(
        name: '  Anaya ',
        email: 'Anaya@Example.com ',
        phone: '+91 98765-43210',
        birthDate: birthDateForAge(9),
        gender: Gender.female,
        designation: ' Junior Explorer ',
        guardianConsent: true,
      );
      final json = child.toNewMemberRequest(india).toJson();
      expect(json['name'], 'Anaya');
      expect(json['email'], 'anaya@example.com');
      expect(json['phone'], '+919876543210');
      expect(json['gender'], 'female');
      expect(json['designation'], 'Junior Explorer');
      expect(json['role'], 'member');
      expect(json['guardianConsent'], isTrue);
      expect(json['dateOfBirth'], endsWith('Z'));

      final adult = child.copyWith(birthDate: () => birthDateForAge(30));
      expect(
        adult.toNewMemberRequest(india).toJson()['guardianConsent'],
        false,
      );
    });

    test('blank optional fields are sent as null', () {
      final json = const MemberFormData(
        name: 'Kamla',
        email: '',
        designation: '  ',
      ).toNewMemberRequest(india).toJson();
      expect(json['email'], isNull);
      expect(json['phone'], isNull);
      expect(json['dateOfBirth'], isNull);
      expect(json['gender'], isNull);
      expect(json['designation'], isNull);
    });
  });

  group('toPatch', () {
    test('no changes → empty patch (even though the DOB instant differs)', () {
      final data = MemberFormData.fromMember(kamla);
      final patch = data.toPatch(kamla, MemberFormAccess.adminEdit, india);
      expect(patch.isEmpty, isTrue, reason: patch.toJson().toString());
    });

    test('admin: changed + cleared fields, role and consent', () {
      final data = MemberFormData.fromMember(anaya).copyWith(
        name: 'Anaya S',
        phone: () => '+911234567',
        designation: () => 'Chief Fun Officer',
        role: MemberRole.admin,
        guardianConsent: true,
      );
      final json = data
          .toPatch(anaya, MemberFormAccess.adminEdit, india)
          .toJson();
      expect(json, {
        'name': 'Anaya S',
        'phone': '+911234567',
        'designation': 'Chief Fun Officer',
        'role': 'admin',
        'guardianConsent': true,
      });

      final cleared = MemberFormData.fromMember(
        aarav,
      ).copyWith(email: () => null, designation: () => null);
      expect(
        cleared.toPatch(aarav, MemberFormAccess.adminEdit, india).toJson(),
        {'email': null, 'designation': null},
      );
    });

    test('self edit never sends admin-only fields', () {
      final data = MemberFormData.fromMember(kamla).copyWith(
        name: 'Kamla Devi',
        email: () => 'other@example.com',
        designation: () => 'Boss',
        role: MemberRole.admin,
        guardianConsent: true,
        gender: () => null,
        birthDate: () => DateTime(1953, 1, 2),
      );
      final json = data
          .toPatch(kamla, MemberFormAccess.selfEdit, india)
          .toJson();
      expect(json.keys, unorderedEquals(['name', 'gender', 'dateOfBirth']));
      expect(json['gender'], isNull);
      expect(
        DateTime.parse(json['dateOfBirth'] as String).toLocal(),
        DateTime(1953, 1, 2),
      );
    });

    test('an admin editing themselves cannot change their role', () {
      final data = MemberFormData.fromMember(
        amit,
      ).copyWith(role: MemberRole.member, designation: () => 'CEO');
      expect(
        data.toPatch(amit, MemberFormAccess.adminEditSelf, india).toJson(),
        {'designation': 'CEO'},
      );
    });

    test("an account holder's email is never patched", () {
      final data = MemberFormData.fromMember(
        kamla,
      ).copyWith(email: () => 'new@example.com');
      expect(
        data.toPatch(kamla, MemberFormAccess.adminEdit, india).isEmpty,
        isTrue,
      );
    });
  });

  group('edge cases', () {
    test('leap-day birthdays and the consent birthday itself', () {
      final leap = MemberFormData(birthDate: DateTime(2008, 2, 29));
      // Not 18 yet on 28 Feb of a non-leap year, 18 from 1 March.
      expect(leap.ageOn(DateTime(2026, 2, 28)), 17);
      expect(leap.ageOn(DateTime(2026, 3, 1)), 18);
      expect(
        leap.needsGuardianConsent(india, today: DateTime(2026, 2, 28)),
        isTrue,
      );
      expect(
        leap.needsGuardianConsent(india, today: DateTime(2026, 3, 1)),
        isFalse,
      );
      // Born today → 0 years (a minor), not "unknown".
      final newborn = MemberFormData(birthDate: DateTime(2026, 9, 26));
      expect(newborn.ageOn(DateTime(2026, 9, 26)), 0);
    });

    test('consentRequired (server asked for it) records the ticked box', () {
      final adult = MemberFormData(
        name: 'Rohan',
        birthDate: birthDateForAge(19),
        guardianConsent: true,
      );
      expect(adult.toNewMemberRequest(india).guardianConsent, isFalse);
      expect(
        adult.toNewMemberRequest(india, consentRequired: true).guardianConsent,
        isTrue,
      );
      // Never without the tick.
      expect(
        adult
            .copyWith(guardianConsent: false)
            .toNewMemberRequest(india, consentRequired: true)
            .guardianConsent,
        isFalse,
      );
      final before = kamla; // adult, no consent recorded
      final data = MemberFormData.fromMember(
        before,
      ).copyWith(guardianConsent: true);
      expect(
        data.toPatch(before, MemberFormAccess.adminEdit, india).isEmpty,
        isTrue,
      );
      expect(
        data
            .toPatch(
              before,
              MemberFormAccess.adminEdit,
              india,
              consentRequired: true,
            )
            .toJson(),
        {'guardianConsent': true},
      );
      // A member editing themselves can never give consent.
      expect(
        data
            .toPatch(
              before,
              MemberFormAccess.selfEdit,
              india,
              consentRequired: true,
            )
            .isEmpty,
        isTrue,
      );
    });

    test('sameNameIn ignores case and spacing; blank names never match', () {
      final members = [amit, kamla, aarav];
      expect(
        const MemberFormData(name: '  aARav ').sameNameIn(members)?.id,
        aarav.id,
      );
      expect(
        const MemberFormData(
          name: 'Kamla',
        ).sameNameIn([kamla.copyWith(name: 'kamla   ')])?.id,
        kamla.id,
      );
      expect(const MemberFormData(name: 'Aaravi').sameNameIn(members), isNull);
      expect(const MemberFormData(name: '   ').sameNameIn(members), isNull);
      expect(MemberFormData.nameKey(' Anaya\t Sharma '), 'anaya sharma');
    });

    test('very long and non-Latin names keep grapheme-safe initials', () {
      final long = 'A' * 60;
      expect(Member.initialsOf(long), 'A');
      expect(Member.initialsOf('आरव शर्मा'), 'आश');
      expect(Member.initialsOf('   '), '?');
    });
  });

  group('DesignationSuggestion.forAgeGroup', () {
    test('age-appropriate lists without duplicates', () {
      expect(
        DesignationSuggestion.forAgeGroup(AgeGroup.child),
        contains(DesignationSuggestion.juniorExplorer),
      );
      expect(
        DesignationSuggestion.forAgeGroup(AgeGroup.child),
        isNot(contains(DesignationSuggestion.financeHead)),
      );
      expect(
        DesignationSuggestion.forAgeGroup(AgeGroup.teen).first,
        DesignationSuggestion.chiefStudyOfficer,
      );
      expect(
        DesignationSuggestion.forAgeGroup(AgeGroup.adult).first,
        DesignationSuggestion.headOfFamily,
      );
      expect(
        DesignationSuggestion.forAgeGroup(AgeGroup.senior).first,
        DesignationSuggestion.familyAdvisor,
      );
      for (final group in [...AgeGroup.values, null]) {
        final list = DesignationSuggestion.forAgeGroup(group);
        expect(list.toSet().length, list.length);
        expect(list, isNotEmpty);
      }
    });
  });
}
