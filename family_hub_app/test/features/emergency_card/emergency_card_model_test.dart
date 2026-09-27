import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/features/emergency_card/domain/emergency_card.dart';
import 'package:family_hub/features/emergency_card/presentation/emergency_card_labels.dart';
import 'package:family_hub/l10n/app_localizations_en.dart';

import 'emergency_card_test_utils.dart';

void main() {
  group('BloodGroup.fromWire', () {
    test('parses every contract wire value', () {
      for (final group in BloodGroup.values) {
        expect(BloodGroup.fromWire(group.wireName), group);
      }
    });

    test('is lenient with case, spaces, typographic minus and "ve"', () {
      expect(BloodGroup.fromWire('ab+'), BloodGroup.abPositive);
      expect(BloodGroup.fromWire(' O - '), BloodGroup.oNegative);
      expect(BloodGroup.fromWire('A−'), BloodGroup.aNegative);
      expect(BloodGroup.fromWire('B+ve'), BloodGroup.bPositive);
      expect(BloodGroup.fromWire('abNegative'), BloodGroup.abNegative);
      expect(BloodGroup.fromWire(BloodGroup.oPositive), BloodGroup.oPositive);
    });

    test('unknown / junk values fall back to unknown', () {
      for (final v in [null, '', 'C+', 'AB', 42, true, <String>[]]) {
        expect(BloodGroup.fromWire(v), BloodGroup.unknown, reason: '$v');
      }
    });

    test('labels: symbols for known groups, translated unknown', () {
      final l10n = AppLocalizationsEn();
      expect(BloodGroup.abNegative.label(l10n), 'AB-');
      expect(BloodGroup.unknown.label(l10n), 'Unknown');
      expect(BloodGroup.bPositive.semanticLabel(l10n), 'Blood group B+');
    });
  });

  group('EmergencyCard.fromJson', () {
    test('parses the full contract shape', () {
      final card = EmergencyCard.fromJson({
        'memberId': 'm1',
        'bloodGroup': 'B+',
        'allergies': ['Peanuts'],
        'medications': ['Metformin 500mg'],
        'conditions': ['Asthma'],
        'doctorName': 'Dr. Rao',
        'doctorPhone': '+911123456789',
        'insuranceProvider': 'Star Health',
        'insurancePolicyNumber': 'P-123',
        'emergencyContacts': [
          {'name': 'Ravi', 'phone': '+919800000000', 'relation': 'Uncle'},
        ],
        'notes': 'Inhaler in bag',
        'updatedAt': '2026-09-26T10:15:00.000Z',
        'updatedById': 'm2',
      });
      expect(card.memberId, 'm1');
      expect(card.bloodGroup, BloodGroup.bPositive);
      expect(card.allergies, ['Peanuts']);
      expect(card.medications, ['Metformin 500mg']);
      expect(card.conditions, ['Asthma']);
      expect(card.doctorName, 'Dr. Rao');
      expect(card.doctorPhone, '+911123456789');
      expect(card.insuranceProvider, 'Star Health');
      expect(card.insurancePolicyNumber, 'P-123');
      expect(card.emergencyContacts, const [
        EmergencyContact(
          name: 'Ravi',
          phone: '+919800000000',
          relation: 'Uncle',
        ),
      ]);
      expect(card.notes, 'Inhaler in bag');
      expect(card.updatedAt, DateTime.utc(2026, 9, 26, 10, 15));
      expect(card.updatedById, 'm2');
      expect(card.hasBeenSaved, isTrue);
      expect(card.isOfflineCopy, isFalse);
    });

    test('the contract empty card', () {
      final card = EmergencyCard.fromJson({
        'memberId': 'm1',
        'bloodGroup': 'unknown',
        'allergies': [],
        'medications': [],
        'conditions': [],
        'doctorName': null,
        'doctorPhone': null,
        'insuranceProvider': null,
        'insurancePolicyNumber': null,
        'emergencyContacts': [],
        'notes': null,
        'updatedAt': null,
        'updatedById': null,
      });
      expect(card, EmergencyCard.empty('m1'));
      expect(card.isEmpty, isTrue);
      expect(card.hasBeenSaved, isFalse);
    });

    test('is defensive: missing, wrong types, blanks and extra fields', () {
      final card = EmergencyCard.fromJson({
        'bloodGroup': 7,
        'allergies': [
          '  Dust ',
          '',
          null,
          3,
          {'x': 1},
        ],
        'medications': 'not a list',
        'doctorName': '   ',
        'notes': '',
        'emergencyContacts': [
          'junk',
          {'name': '', 'phone': ' ', 'relation': null},
          {'name': ' Ravi ', 'phone': '', 'extra': true},
        ],
        'updatedAt': 'not a date',
        'somethingNew': {'a': 1},
      }, fallbackMemberId: 'm9');
      expect(card.memberId, 'm9');
      expect(card.bloodGroup, BloodGroup.unknown);
      expect(card.allergies, ['Dust', '3']);
      expect(card.medications, isEmpty);
      expect(card.doctorName, isNull);
      expect(card.notes, isNull);
      expect(card.emergencyContacts, const [EmergencyContact(name: 'Ravi')]);
      expect(card.updatedAt, isNull);
    });

    test('lists are unmodifiable', () {
      final card = fullCard('m1');
      expect(() => card.allergies.add('x'), throwsUnsupportedError);
      expect(
        () => card.emergencyContacts.add(const EmergencyContact(name: 'x')),
        throwsUnsupportedError,
      );
    });
  });

  group('EmergencyCard JSON out', () {
    test('toUpdateJson sends only editable fields, trimmed and cleaned', () {
      final card = EmergencyCard(
        memberId: 'm1',
        bloodGroup: BloodGroup.aNegative,
        allergies: const [' Peanuts ', 'peanuts', '', 'Dust'],
        doctorName: '  ',
        doctorPhone: ' +91 98 ',
        emergencyContacts: const [
          EmergencyContact(name: ' Ravi ', phone: ' ', relation: 'Uncle '),
          EmergencyContact(name: ''),
        ],
        notes: ' Note ',
        updatedAt: DateTime.utc(2026),
        offlineSavedAt: DateTime.utc(2026),
      );
      final json = card.toUpdateJson();
      expect(json.keys.toSet(), {
        'bloodGroup',
        'allergies',
        'medications',
        'conditions',
        'doctorName',
        'doctorPhone',
        'insuranceProvider',
        'insurancePolicyNumber',
        'emergencyContacts',
        'notes',
      });
      expect(json['bloodGroup'], 'A-');
      expect(json['allergies'], ['Peanuts', 'Dust']);
      expect(json['medications'], isEmpty);
      expect(json['doctorName'], isNull);
      expect(json['doctorPhone'], '+91 98');
      expect(json['emergencyContacts'], [
        {'name': 'Ravi', 'phone': null, 'relation': 'Uncle'},
      ]);
      expect(json['notes'], 'Note');
    });

    test('toJson round-trips (without the client-only offline marker)', () {
      final card = fullCard('m1');
      final copy = card.copyWith(offlineSavedAt: () => DateTime.utc(2026));
      expect(EmergencyCard.fromJson(copy.toJson()), card);
    });

    test('toString never contains health data', () {
      final text = fullCard('m1').toString();
      expect(text, isNot(contains('Penicillin')));
      expect(text, isNot(contains('diabetes')));
    });
  });

  group('completeness', () {
    test('empty card misses every key detail', () {
      final c = EmergencyCard.empty('m1').completeness;
      expect(c.filled, 0);
      expect(c.total, 4);
      expect(c.missing, EmergencyCardSection.values);
      expect(c.ratio, 0);
    });

    test('a full card is complete even without allergies', () {
      final card = fullCard('m1').copyWith(allergies: const []);
      expect(card.completeness.isComplete, isTrue);
      expect(card.completeness.ratio, 1);
    });

    test('contacts only count when they can be called', () {
      final card = fullCard(
        'm1',
      ).copyWith(emergencyContacts: const [EmergencyContact(name: 'Ravi')]);
      expect(card.completeness.missing, [EmergencyCardSection.contacts]);
      expect(card.completeness.filled, 3);
    });
  });

  test(
    'copyWith clears nullable fields and sameContentAs ignores metadata',
    () {
      final card = fullCard('m1');
      final cleared = card.copyWith(notes: () => null, doctorName: () => null);
      expect(cleared.notes, isNull);
      expect(cleared.doctorName, isNull);
      expect(cleared.doctorPhone, card.doctorPhone);

      final resaved = card.copyWith(
        updatedAt: () => DateTime.utc(2030),
        offlineSavedAt: () => DateTime.utc(2030),
        notes: () => ' ${card.notes} ',
      );
      expect(resaved == card, isFalse);
      expect(resaved.sameContentAs(card), isTrue);
      expect(cleared.sameContentAs(card), isFalse);
    },
  );

  test('cleanList trims, drops blanks and case-insensitive duplicates', () {
    expect(EmergencyCard.cleanList([' a', 'A', '', 'b ', 'B', 'c']), [
      'a',
      'b',
      'c',
    ]);
  });
}
