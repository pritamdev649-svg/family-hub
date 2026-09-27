import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/network/mock/mock_backend.dart';
import 'package:family_hub/features/emergency_card/data/emergency_card_mock_handlers.dart';
import 'package:family_hub/features/emergency_card/domain/emergency_card.dart';

const _aaravUserId = 'user-aarav-test';
const _unknownId = 'ffffffffffffffffffffff00';
const _strangerId = 'ffffffffffffffffffffff02';

RequestOptions _req(
  String method,
  String memberId, {
  Object? data,
  String? as,
}) => RequestOptions(
  method: method,
  baseUrl: MockBackend.baseUrl,
  path: '/family/members/$memberId/emergency-card',
  data: data,
  headers: {
    'Authorization':
        'Bearer ${MockRequest.accessTokenFor(as ?? MockSeed.amitUserId)}',
  },
);

Future<MockException> _error(Future<Object?> f) async {
  try {
    await f;
  } on MockException catch (e) {
    return e;
  }
  fail('expected a MockException');
}

Map<String, dynamic> _validBody() => {
  'bloodGroup': 'A+',
  'allergies': ['Dust'],
  'medications': <String>[],
  'conditions': <String>[],
  'doctorName': 'Dr. Mehta',
  'doctorPhone': '+91 98765-43210',
  'insuranceProvider': null,
  'insurancePolicyNumber': null,
  'emergencyContacts': [
    {'name': 'Amit', 'phone': '+919876543210', 'relation': 'Father'},
  ],
  'notes': null,
};

void main() {
  late MockBackend b;

  setUp(() {
    b = MockBackend();
    registerEmergencyCardMocks(b);
    // Give Aarav (a regular member) an account so permission rules can be
    // tested.
    b.db.insert(MockDb.users, {
      'id': _aaravUserId,
      'email': 'aarav-test@familyhub.app',
      'familyId': MockSeed.familyId,
      'memberId': MockSeed.aaravMemberId,
    });
    b.db.update(MockDb.members, MockSeed.aaravMemberId, {
      'userId': _aaravUserId,
    });
  });

  group('GET', () {
    test('seeded cards for Amit and Kamla', () async {
      final amit = EmergencyCard.fromJson(
        (await b.handle(_req('GET', MockSeed.amitMemberId))).data
            as Map<String, dynamic>,
      );
      expect(amit.bloodGroup, BloodGroup.bPositive);
      expect(amit.allergies, ['Peanuts']);
      expect(amit.hasBeenSaved, isTrue);

      final kamla = EmergencyCard.fromJson(
        (await b.handle(_req('GET', MockSeed.kamlaMemberId))).data
            as Map<String, dynamic>,
      );
      expect(kamla.bloodGroup, BloodGroup.oPositive);
      expect(kamla.medications.single, contains('Metformin'));
      expect(kamla.conditions.single, contains('diabetes'));
      expect(kamla.doctorName, isNotNull);
      expect(kamla.doctorPhone, isNotNull);
    });

    test('member without a card → contract empty card', () async {
      final res = await b.handle(_req('GET', MockSeed.anayaMemberId));
      expect(res.data, emptyMockCard(MockSeed.anayaMemberId));
      final card = EmergencyCard.fromJson(res.data as Map<String, dynamic>);
      expect(card.isEmpty, isTrue);
      expect(card.updatedAt, isNull);
    });

    test('unknown member or another family → 404', () async {
      b.db.insert(MockDb.members, {
        'id': _strangerId,
        'familyId': 'ffffffffffffffffffffff01',
        'name': 'Stranger',
      });
      expect((await _error(b.handle(_req('GET', _unknownId)))).status, 404);
      expect(
        (await _error(b.handle(_req('GET', _strangerId)))).code,
        'NOT_FOUND',
      );
    });

    test('malformed id → 400 BAD_REQUEST (like the backend)', () async {
      final e = await _error(b.handle(_req('GET', 'not-an-id')));
      expect(e.status, 400);
      expect(e.code, 'BAD_REQUEST');
    });

    test('requires authentication', () async {
      final e = await _error(
        b.handle(
          RequestOptions(
            method: 'GET',
            baseUrl: MockBackend.baseUrl,
            path: '/family/members/${MockSeed.amitMemberId}/emergency-card',
          ),
        ),
      );
      expect(e.status, 401);
    });
  });

  group('PUT', () {
    test('admin saves another member\'s card (normalised phone)', () async {
      final res = await b.handle(
        _req('PUT', MockSeed.anayaMemberId, data: _validBody()),
      );
      final card = EmergencyCard.fromJson(res.data as Map<String, dynamic>);
      expect(card.memberId, MockSeed.anayaMemberId);
      expect(card.bloodGroup, BloodGroup.aPositive);
      expect(card.doctorPhone, '+919876543210');
      expect(card.updatedById, MockSeed.amitMemberId);
      expect(card.updatedAt, isNotNull);

      // Persisted: GET returns the same, and PUT replaces (no duplicates).
      final again = await b.handle(_req('GET', MockSeed.anayaMemberId));
      expect(again.data, res.data);
      await b.handle(
        _req(
          'PUT',
          MockSeed.anayaMemberId,
          data: {..._validBody(), 'bloodGroup': 'O-'},
        ),
      );
      expect(
        b.db.count(
          MockDb.emergencyCards,
          (c) => c['memberId'] == MockSeed.anayaMemberId,
        ),
        1,
      );
    });

    test('a member may save their own card but not someone else\'s', () async {
      final own = await b.handle(
        _req(
          'PUT',
          MockSeed.aaravMemberId,
          data: _validBody(),
          as: _aaravUserId,
        ),
      );
      expect((own.data as Map)['updatedById'], MockSeed.aaravMemberId);

      final e = await _error(
        b.handle(
          _req(
            'PUT',
            MockSeed.kamlaMemberId,
            data: _validBody(),
            as: _aaravUserId,
          ),
        ),
      );
      expect(e.status, 403);
      expect(e.code, 'FORBIDDEN');
    });

    test('validates the contract limits', () async {
      final body = {
        ..._validBody(),
        'bloodGroup': 'C+',
        'allergies': List.generate(21, (i) => 'Allergy $i'),
        'medications': ['x' * 81, '  ', 42],
        'doctorPhone': 'call me',
        'emergencyContacts': List.generate(6, (i) => {'name': 'C$i'}),
        'notes': 'n' * 501,
      };
      final e = await _error(
        b.handle(_req('PUT', MockSeed.amitMemberId, data: body)),
      );
      expect(e.status, 422);
      expect(e.code, 'VALIDATION_ERROR');
      expect(e.details!.keys, {
        'bloodGroup',
        'allergies',
        'medications.0',
        'medications.2', // not text; the blank item is simply dropped
        'doctorPhone',
        'emergencyContacts', // too many: the items are not checked
        'notes',
      });
    });

    test('contacts: name required, phone optional but valid', () async {
      final e = await _error(
        b.handle(
          _req(
            'PUT',
            MockSeed.amitMemberId,
            data: {
              ..._validBody(),
              'emergencyContacts': [
                {'name': '  ', 'phone': '+919800000000'},
                {'name': 'Ravi', 'phone': '12'},
                'Priya',
                {'name': 'R' * 101, 'relation': 'r' * 61},
              ],
            },
          ),
        ),
      );
      expect(e.details!.keys, {
        'emergencyContacts.0.name',
        'emergencyContacts.1.phone',
        'emergencyContacts.2',
        'emergencyContacts.3.name',
        'emergencyContacts.3.relation',
      });
    });

    test(
      'strips unknown and read-only keys (a GET body can be sent back)',
      () async {
        final get = await b.handle(_req('GET', MockSeed.kamlaMemberId));
        final res = await b.handle(
          _req(
            'PUT',
            MockSeed.kamlaMemberId,
            data: {
              ...(get.data as Map<String, dynamic>),
              'memberId': MockSeed.amitMemberId,
              'updatedById': 'forged',
              'familyId': 'forged',
              'allergiesEnc': 'forged',
            },
          ),
        );
        final data = res.data as Map<String, dynamic>;
        expect(data['memberId'], MockSeed.kamlaMemberId);
        expect(data['updatedById'], MockSeed.amitMemberId);
        expect(data.containsKey('allergiesEnc'), isFalse);
        expect(data['conditions'], (get.data as Map)['conditions']);
      },
    );

    test('normalises like the backend schema', () async {
      final res = await b.handle(
        _req(
          'PUT',
          MockSeed.amitMemberId,
          data: {
            'bloodGroup': ' ab \u2212 ',
            'allergies': [' Peanuts ', 'peanuts', '', 'Dust'],
            'medications': null,
            'doctorName': 'Dr.\nRao',
            'doctorPhone': '+91 (98765) 43210',
            'insuranceProvider': '\u200B',
            'emergencyContacts': [
              {'name': ' Ravi ', 'phone': '  ', 'relation': ''},
            ],
            'notes': 'Line 1\r\nLine 2',
          },
        ),
      );
      final data = res.data as Map<String, dynamic>;
      expect(data['bloodGroup'], 'AB-');
      expect(data['allergies'], ['Peanuts', 'Dust']);
      expect(data['medications'], isEmpty);
      expect(data['conditions'], isEmpty); // missing key → replaced
      expect(data['doctorName'], 'Dr. Rao');
      expect(data['doctorPhone'], '+919876543210');
      expect(data['insuranceProvider'], isNull);
      expect(data['insurancePolicyNumber'], isNull);
      expect(data['emergencyContacts'], [
        {'name': 'Ravi', 'phone': null, 'relation': null},
      ]);
      expect(data['notes'], 'Line 1\nLine 2');

      for (final group in [null, '', 'Unknown']) {
        final r = await b.handle(
          _req('PUT', MockSeed.amitMemberId, data: {'bloodGroup': group}),
        );
        expect((r.data as Map)['bloodGroup'], 'unknown', reason: '$group');
      }
      final e = await _error(
        b.handle(_req('PUT', MockSeed.amitMemberId, data: {'bloodGroup': 7})),
      );
      expect(e.details!.keys, ['bloodGroup']);
    });

    test('duplicates are removed before the 20-item limit', () async {
      final res = await b.handle(
        _req(
          'PUT',
          MockSeed.amitMemberId,
          data: {
            'allergies': [
              for (var i = 0; i < 20; i++) 'Allergy $i',
              for (var i = 0; i < 20; i++) 'allergy $i',
            ],
          },
        ),
      );
      expect((res.data as Map)['allergies'], hasLength(20));

      final e = await _error(
        b.handle(
          _req(
            'PUT',
            MockSeed.amitMemberId,
            data: {'allergies': List.filled(101, 'x')},
          ),
        ),
      );
      expect(e.details!.keys, ['allergies']);
    });

    test('checks run in the backend order: 400 → 422 → 404 → 403', () async {
      final invalid = {'notes': 'n' * 501};
      // Malformed id wins over an invalid body.
      expect(
        (await _error(
          b.handle(_req('PUT', 'not-an-id', data: invalid)),
        )).status,
        400,
      );
      // An invalid body is reported before "not in your family" …
      expect(
        (await _error(b.handle(_req('PUT', _unknownId, data: invalid)))).status,
        422,
      );
      expect(
        (await _error(
          b.handle(_req('PUT', _unknownId, data: _validBody())),
        )).status,
        404,
      );
      // … and before "not allowed".
      expect(
        (await _error(
          b.handle(
            _req(
              'PUT',
              MockSeed.kamlaMemberId,
              data: invalid,
              as: _aaravUserId,
            ),
          ),
        )).status,
        422,
      );
    });

    test('accepts exactly the limits', () async {
      final body = {
        ..._validBody(),
        'allergies': List.generate(20, (i) => '${'a' * 70}$i'),
        'emergencyContacts': List.generate(5, (i) => {'name': 'C$i'}),
        'notes': 'n' * 500,
      };
      final res = await b.handle(
        _req('PUT', MockSeed.amitMemberId, data: body),
      );
      final card = EmergencyCard.fromJson(res.data as Map<String, dynamic>);
      expect(card.allergies, hasLength(20));
      expect(card.emergencyContacts, hasLength(5));
      expect(card.notes, hasLength(500));
    });

    test('the app\'s own request body is accepted', () async {
      final card = EmergencyCard(
        memberId: MockSeed.kamlaMemberId,
        bloodGroup: BloodGroup.oPositive,
        allergies: const ['Sulfa drugs'],
        emergencyContacts: const [EmergencyContact(name: 'Priya')],
      );
      final res = await b.handle(
        _req('PUT', MockSeed.kamlaMemberId, data: card.toUpdateJson()),
      );
      final saved = EmergencyCard.fromJson(res.data as Map<String, dynamic>);
      expect(saved.sameContentAs(card), isTrue);
    });
  });
}
