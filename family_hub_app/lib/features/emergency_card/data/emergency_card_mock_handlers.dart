import 'package:family_hub/core/network/mock/mock_backend.dart';
import 'package:family_hub/features/emergency_card/domain/emergency_card.dart';

/// Registers the emergency card mock routes (docs/03-API_CONTRACT.md §6),
/// mirroring `family_hub_backend/src/modules/emergencyCards`:
///
/// * `GET /family/members/:id/emergency-card` (any family member) → the
///   stored card, or the contract's empty card (`updatedAt: null`).
/// * `PUT /family/members/:id/emergency-card` (self or admin) → replaces the
///   whole card. Checks run in the backend's order: 401 → 403 `NO_FAMILY` →
///   400 malformed id → 422 body → 404 (not in the caller's family) → 403
///   `FORBIDDEN` (neither self nor admin).
///
/// The body is normalised like the backend's zod schema: unknown and
/// read-only keys (`memberId`, `updatedAt`, …) are stripped, the blood group
/// is case / space / dash-insensitive, list items are cleaned, blank ones
/// dropped and case-insensitive duplicates removed **before** the 20-item
/// limit, phones lose spaces / dashes / brackets, blank text → `null`.
///
/// Seeds cards for Amit (B+, peanut allergy) and Kamla (O+, Metformin,
/// diabetes, doctor contact).
void registerEmergencyCardMocks(MockBackend b) {
  _seedCards(b.db);

  b.on('GET', '/family/members/:id/emergency-card', (req) {
    req.requireMember();
    final member = req.findInFamily(MockDb.members, _memberIdParam(req));
    final memberId = member['id'] as String;
    final doc = req.db.findOne(
      MockDb.emergencyCards,
      (c) => c['memberId'] == memberId,
    );
    return MockResponse.ok(
      doc == null ? emptyMockCard(memberId) : serializeMockCard(doc),
    );
  });

  b.on('PUT', '/family/members/:id/emergency-card', (req) {
    final me = req.requireMember();
    final id = _memberIdParam(req);
    final fields = _validateCard(req.body);
    final member = req.findInFamily(MockDb.members, id);
    final memberId = member['id'] as String;
    if (me['id'] != memberId && me['role'] != 'admin') {
      throw const MockException.forbidden(
        'Only the member or an admin can edit this card',
      );
    }
    final db = req.db;
    final existing = db.findOne(
      MockDb.emergencyCards,
      (c) => c['memberId'] == memberId,
    );
    final now = db.nowIso();
    final doc = <String, dynamic>{
      ...fields,
      'familyId': member['familyId'],
      'memberId': memberId,
      'updatedById': me['id'],
      'createdAt': existing?['createdAt'] ?? now,
      'updatedAt': now,
    };
    final stored = existing == null
        ? db.insert(MockDb.emergencyCards, doc)
        : db.replace(MockDb.emergencyCards, existing['id'] as String, doc);
    return MockResponse.ok(serializeMockCard(stored ?? doc));
  });
}

final _objectIdPattern = RegExp(r'^[0-9a-fA-F]{24}$');

/// `:id` must be an ObjectId (`400 BAD_REQUEST`, like the backend's params
/// validation); lower-cased like the backend.
String _memberIdParam(MockRequest req) {
  final id = req.param('id').trim();
  if (!_objectIdPattern.hasMatch(id)) {
    throw const MockException.badRequest('Invalid id');
  }
  return id.toLowerCase();
}

/// Contract `EmergencyCard` of a stored mock document.
Map<String, dynamic> serializeMockCard(Map<String, dynamic> doc) => {
  'memberId': doc['memberId'],
  'bloodGroup': doc['bloodGroup'] ?? 'unknown',
  'allergies': _stringList(doc['allergies']),
  'medications': _stringList(doc['medications']),
  'conditions': _stringList(doc['conditions']),
  'doctorName': doc['doctorName'],
  'doctorPhone': doc['doctorPhone'],
  'insuranceProvider': doc['insuranceProvider'],
  'insurancePolicyNumber': doc['insurancePolicyNumber'],
  'emergencyContacts': [
    for (final c in (doc['emergencyContacts'] as List?) ?? const [])
      if (c is Map)
        {'name': c['name'], 'phone': c['phone'], 'relation': c['relation']},
  ],
  'notes': doc['notes'],
  'updatedAt': doc['updatedAt'],
  'updatedById': doc['updatedById'],
};

/// The contract's empty card for a member without a saved card.
Map<String, dynamic> emptyMockCard(String memberId) => {
  'memberId': memberId,
  'bloodGroup': 'unknown',
  'allergies': <String>[],
  'medications': <String>[],
  'conditions': <String>[],
  'doctorName': null,
  'doctorPhone': null,
  'insuranceProvider': null,
  'insurancePolicyNumber': null,
  'emergencyContacts': <Map<String, dynamic>>[],
  'notes': null,
  'updatedAt': null,
  'updatedById': null,
};

List<String> _stringList(Object? v) =>
    v is List ? [for (final e in v) '$e'] : <String>[];

// ── Validation (mirrors emergencyCards.schemas.js) ──────────────────────────

const _bloodGroups = {
  'A+',
  'A-',
  'B+',
  'B-',
  'AB+',
  'AB-',
  'O+',
  'O-',
  'unknown',
};
// The contract limits (shared with the app; the backend's `LIMITS` in
// family_hub_backend/src/models/enums.js has the same values).
const _listMaxItems = EmergencyCardLimits.listMaxItems;
const _listItemMax = EmergencyCardLimits.listItemMaxLength;
const _contactsMax = EmergencyCardLimits.contactsMax;
const _notesMax = EmergencyCardLimits.notesMaxLength;
const _textMax = EmergencyCardLimits.textMaxLength;
const _relationMax = EmergencyCardLimits.relationMaxLength;
const _policyNumberMax = EmergencyCardLimits.textMaxLength;

/// Raw list entries accepted before clean-up (backend `RAW_LIST_MAX`).
const _rawListMax = _listMaxItems * 5;

final _phonePattern = RegExp(r'^\+?\d{6,15}$');
final _phoneSeparators = RegExp(r'[\s\-()]');
final _dashes = RegExp('[\u2010-\u2015\u2212\uFE58\uFE63\uFF0D]');
final _singleLineBreaks = RegExp('[\t\n\v\f\r\u0085\u2028\u2029]+');
final _multiLineBreaks = RegExp('\r\n?|[\v\f\u0085\u2028\u2029]');
final _strippedChars = RegExp(
  '[\u0000-\u0008\u000B-\u001F\u007F-\u009F\u202A-\u202E\u2066-\u2069]',
);
final _edgeBlanks = RegExp(
  '^[\\s\u200B\u2060\uFEFF]+|[\\s\u200B\u2060\uFEFF]+\$',
);
final _invisible = RegExp(
  '[\\s\u200B-\u200F\u2060-\u2064\uFEFF\uFE00-\uFE0F\u115F\u1160\u3164\uFFA0\u2800]',
);

/// Backend `cleanText`: line breaks -> one space (or `\n` in [multiline]
/// fields), control / bidi-override characters removed, trimmed; text with
/// nothing visible becomes `''`.
String _cleanText(String value, {bool multiline = false}) {
  final text =
      (multiline
              ? value.replaceAll(_multiLineBreaks, '\n')
              : value.replaceAll(_singleLineBreaks, ' '))
          .replaceAll(_strippedChars, '')
          .replaceAll(_edgeBlanks, '');
  return text.replaceAll(_invisible, '').isEmpty ? '' : text;
}

/// `"ab −"` → `AB-`, null / blank → `unknown`; anything else unchanged.
Object? _normalizeBloodGroup(Object? value) {
  if (value == null) return 'unknown';
  if (value is! String) return value;
  final compact = value.replaceAll(_dashes, '-').replaceAll(RegExp(r'\s+'), '');
  if (compact.isEmpty || compact.toLowerCase() == 'unknown') return 'unknown';
  return compact.toUpperCase();
}

/// Validated, normalised card fields; throws `422 VALIDATION_ERROR` with
/// `details` = field path → message. Keys missing from [body] get their empty
/// value (PUT replaces the whole card); unknown keys are ignored.
Map<String, dynamic> _validateCard(Map<String, dynamic> body) {
  final errors = <String, String>{};

  final bloodGroup = _normalizeBloodGroup(body['bloodGroup']);
  if (bloodGroup is! String || !_bloodGroups.contains(bloodGroup)) {
    errors['bloodGroup'] =
        'Blood group must be one of ${_bloodGroups.join(', ')}';
  }

  String? text(
    Object? value,
    String path,
    int max, {
    bool required = false,
    bool multiline = false,
  }) {
    if (value == null) {
      if (required) errors[path] = 'Required';
      return null;
    }
    if (value is! String) {
      errors[path] = 'Must be text';
      return null;
    }
    final t = _cleanText(value, multiline: multiline);
    if (t.isEmpty) {
      if (required) errors[path] = 'Required';
      return null;
    }
    if (t.length > max) errors[path] = 'At most $max characters';
    return t;
  }

  String? phone(Object? value, String path) {
    if (value == null) return null;
    if (value is! String) {
      errors[path] = 'Must be text';
      return null;
    }
    final cleaned = value.trim().replaceAll(_phoneSeparators, '');
    if (cleaned.isEmpty) return null;
    if (!_phonePattern.hasMatch(cleaned)) errors[path] = 'Invalid phone number';
    return cleaned;
  }

  List<String> list(String name) {
    final value = body[name];
    if (value == null) return const [];
    if (value is! List) {
      errors[name] = 'Must be a list of text items';
      return const [];
    }
    if (value.length > _rawListMax) {
      errors[name] = 'At most $_listMaxItems items';
      return const [];
    }
    final seen = <String>{};
    final out = <String>[];
    for (var i = 0; i < value.length; i++) {
      final raw = value[i];
      final path = '$name.$i';
      if (raw is! String) {
        errors[path] = 'Each item must be text';
        continue;
      }
      final item = _cleanText(raw);
      if (item.length > _listItemMax) {
        errors[path] = 'Each item can have at most $_listItemMax characters';
        continue;
      }
      if (item.isEmpty || !seen.add(item.toLowerCase())) continue;
      out.add(item);
    }
    if (out.length > _listMaxItems) {
      errors[name] = 'At most $_listMaxItems items';
    }
    return out;
  }

  final contacts = <Map<String, dynamic>>[];
  final rawContacts = body['emergencyContacts'];
  if (rawContacts != null && rawContacts is! List) {
    errors['emergencyContacts'] = 'Must be a list of contacts';
  } else if (rawContacts is List && rawContacts.length > _contactsMax) {
    // Checked before the items, like the backend's bounded array.
    errors['emergencyContacts'] = 'At most $_contactsMax emergency contacts';
  } else if (rawContacts is List) {
    for (var i = 0; i < rawContacts.length; i++) {
      final raw = rawContacts[i];
      final path = 'emergencyContacts.$i';
      if (raw is! Map) {
        errors[path] = 'Each emergency contact must be an object';
        continue;
      }
      contacts.add({
        'name': text(raw['name'], '$path.name', _textMax, required: true),
        'phone': phone(raw['phone'], '$path.phone'),
        'relation': text(raw['relation'], '$path.relation', _relationMax),
      });
    }
  }

  final fields = <String, dynamic>{
    'bloodGroup': bloodGroup,
    'allergies': list('allergies'),
    'medications': list('medications'),
    'conditions': list('conditions'),
    'doctorName': text(body['doctorName'], 'doctorName', _textMax),
    'doctorPhone': phone(body['doctorPhone'], 'doctorPhone'),
    'insuranceProvider': text(
      body['insuranceProvider'],
      'insuranceProvider',
      _textMax,
    ),
    'insurancePolicyNumber': text(
      body['insurancePolicyNumber'],
      'insurancePolicyNumber',
      _policyNumberMax,
    ),
    'emergencyContacts': contacts,
    'notes': text(body['notes'], 'notes', _notesMax, multiline: true),
  };

  if (errors.isNotEmpty) throw MockException.validation(errors);
  return fields;
}

// ── Seed ─────────────────────────────────────────────────────────────────────

void _seedCards(MockDb db) {
  db.seedOnce(MockDb.emergencyCards, () {
    // Only for the demo family (tests may start without the core seed).
    if (db.findById(MockDb.members, MockSeed.amitMemberId) == null) {
      return const [];
    }
    final now = DateTime.now();
    String daysAgo(int d) => MockDb.iso(now.subtract(Duration(days: d)));
    return [
      {
        'familyId': MockSeed.familyId,
        'memberId': MockSeed.amitMemberId,
        'bloodGroup': 'B+',
        'allergies': ['Peanuts'],
        'medications': <String>[],
        'conditions': <String>[],
        'doctorName': null,
        'doctorPhone': null,
        'insuranceProvider': null,
        'insurancePolicyNumber': null,
        'emergencyContacts': [
          {'name': 'Priya', 'phone': '+919876543211', 'relation': 'Wife'},
        ],
        'notes': 'Carries an antihistamine in his office bag.',
        'updatedById': MockSeed.amitMemberId,
        'createdAt': daysAgo(90),
        'updatedAt': daysAgo(12),
      },
      {
        'familyId': MockSeed.familyId,
        'memberId': MockSeed.kamlaMemberId,
        'bloodGroup': 'O+',
        'allergies': <String>[],
        'medications': ['Metformin 500 mg, twice a day'],
        'conditions': ['Type 2 diabetes'],
        'doctorName': 'Dr. Rao',
        'doctorPhone': '+911123456789',
        'insuranceProvider': 'Star Health',
        'insurancePolicyNumber': 'SH-2024-778812',
        'emergencyContacts': [
          {'name': 'Amit', 'phone': '+919876543210', 'relation': 'Son'},
          {
            'name': 'Priya',
            'phone': '+919876543211',
            'relation': 'Daughter-in-law',
          },
        ],
        'notes': 'Keeps glucose tablets in her handbag.',
        'updatedById': MockSeed.amitMemberId,
        'createdAt': daysAgo(80),
        'updatedAt': daysAgo(5),
      },
    ];
  });
}
