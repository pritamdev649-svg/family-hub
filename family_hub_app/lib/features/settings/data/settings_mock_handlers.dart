import 'package:family_hub/core/config/app_languages.dart';
import 'package:family_hub/core/network/mock/mock_backend.dart';
import 'package:family_hub/features/emergency_card/data/emergency_card_mock_handlers.dart'
    show serializeMockCard;
import 'package:family_hub/features/family/data/family_mock_handlers.dart'
    show FamilyMockService;
import 'package:family_hub/features/ledger/data/ledger_mock_handlers.dart'
    show mockEntryJson;
import 'package:family_hub/features/notices/data/notices_mock_handlers.dart'
    show mockNoticeJson;
import 'package:family_hub/features/tasks/data/tasks_mock_handlers.dart'
    show mockTaskJson;

/// Registers the `/me` mock routes (docs/03-API_CONTRACT.md §5), mirroring
/// the backend module `family_hub_backend/src/modules/me`:
///
/// * `PATCH /me` is strict (unknown fields → `422`); nullable fields follow
///   the shared PATCH rule (absent = unchanged, `null` / blank = cleared);
///   `name` updates both the account and the member profile; member-only
///   fields without a family → `403 NO_FAMILY`; switching `locationSharing`
///   away from `always` clears `lastLocation` (GAP-04); a date of birth below
///   the family country's consent age needs recorded guardian consent
///   (`422 GUARDIAN_CONSENT_REQUIRED`, GAP-05).
/// * `avatarUrl` must be a `https://res.cloudinary.com/...` URL — or, in mock
///   mode only, a local file path (the upload service keeps picked images
///   local when Cloudinary is not configured).
/// * `POST /me/leave-family` and `DELETE /me` share the backend's
///   `removeSelfFromFamily`: the only member → the whole family is deleted;
///   otherwise `409 LAST_ADMIN` unless another admin **with an account**
///   remains, then the admin-removal cascade (pending tasks, emergency card,
///   active SOS resolved without a resolution, member row) and the family
///   owner moves to the longest-standing remaining admin. Leaving keeps the
///   user signed in; deleting the account ends every session.
/// * Not mirrored: the login lockout for wrong `DELETE /me` passwords (lives
///   in the auth mock) and rate limits.
void registerMeMocks(MockBackend b) {
  // PATCH /me { name?, phone?, avatarUrl?, locale?, locationSharing?,
  //             gender?, dateOfBirth? } → { user, member }
  b.on('PATCH', '/me', (req) {
    final user = req.requireUser();
    final db = req.db;
    final body = req.body;

    final details = <String, dynamic>{
      for (final key in body.keys)
        if (!_patchableFields.contains(key)) key: 'Unknown field',
    };
    final userPatch = <String, dynamic>{};
    final memberPatch = <String, dynamic>{};

    if (body.containsKey('name')) {
      final name = _trimmed(body['name']);
      if (name == null || name.length > _maxNameLength) {
        details['name'] = 'Name must be 1-$_maxNameLength characters';
      } else {
        userPatch['name'] = name;
        memberPatch['name'] = name;
      }
    }
    if (body.containsKey('phone')) {
      final raw = _blankToNull(body['phone']);
      final phone = raw is String ? _normalizePhone(raw) : null;
      if (raw == null) {
        memberPatch['phone'] = null;
      } else if (phone == null || !_phonePattern.hasMatch(phone)) {
        details['phone'] = 'Invalid phone number';
      } else {
        memberPatch['phone'] = phone;
      }
    }
    if (body.containsKey('avatarUrl')) {
      final raw = _blankToNull(body['avatarUrl']);
      if (raw == null) {
        memberPatch['avatarUrl'] = null;
      } else if (raw is String && _isAllowedImageUrl(raw.trim())) {
        memberPatch['avatarUrl'] = raw.trim();
      } else {
        details['avatarUrl'] = 'Image must be hosted on res.cloudinary.com';
      }
    }
    if (body.containsKey('locale')) {
      final locale = body['locale'];
      if (locale is String && AppLanguages.byCode(locale) != null) {
        userPatch['locale'] = locale;
      } else {
        details['locale'] = 'Unsupported language';
      }
    }
    if (body.containsKey('locationSharing')) {
      final mode = body['locationSharing'];
      if (mode is String && _locationModes.contains(mode)) {
        memberPatch['locationSharing'] = mode;
        if (mode != 'always') memberPatch['lastLocation'] = null;
      } else {
        details['locationSharing'] = 'Must be never, sos_only or always';
      }
    }
    if (body.containsKey('gender')) {
      final gender = _blankToNull(body['gender']);
      if (gender == null || (gender is String && _genders.contains(gender))) {
        memberPatch['gender'] = gender;
      } else {
        details['gender'] = 'Invalid gender';
      }
    }
    if (body.containsKey('dateOfBirth')) {
      final raw = _blankToNull(body['dateOfBirth']);
      if (raw == null) {
        memberPatch['dateOfBirth'] = null;
      } else {
        final dob = _parseIsoDate(raw);
        final error = _dateOfBirthError(dob);
        if (error != null) {
          details['dateOfBirth'] = error;
        } else {
          memberPatch['dateOfBirth'] = MockDb.iso(dob!);
        }
      }
    }
    if (details.isNotEmpty) throw MockException.validation(details);

    final member = _ownMember(db, user);
    final touchesMemberOnly = memberPatch.keys.any((k) => k != 'name');
    if (member == null && touchesMemberOnly) {
      throw const MockException.noFamily();
    }
    final dateOfBirth = memberPatch['dateOfBirth'];
    if (member != null &&
        dateOfBirth is String &&
        member['guardianConsent'] != true) {
      final family = db.findById(MockDb.families, member['familyId']);
      if (family != null) {
        FamilyMockService.requireGuardianConsent(
          family,
          dateOfBirth: dateOfBirth,
          guardianConsent: false,
        );
      }
    }

    final userId = user['id'] as String;
    if (userPatch.isNotEmpty) db.update(MockDb.users, userId, userPatch);
    if (member != null && memberPatch.isNotEmpty) {
      db.update(MockDb.members, member['id'] as String, memberPatch);
    }

    final freshUser = db.findById(MockDb.users, userId) ?? user;
    final freshMember = member == null
        ? null
        : db.findById(MockDb.members, member['id']);
    return MockResponse.ok({
      'user': MockSerializers.user(db, freshUser),
      'member': freshMember == null
          ? null
          : MockSerializers.member(freshMember),
    });
  });

  // PUT /me/location { lat, lng, accuracy? } → { recordedAt }
  // Order like the backend: NO_FAMILY → 422 → LOCATION_SHARING_DISABLED.
  b.on('PUT', '/me/location', (req) {
    final member = req.requireMember();
    final body = req.body;
    final lat = _finite(body['lat']);
    final lng = _finite(body['lng']);
    final hasAccuracy = body['accuracy'] != null;
    final accuracy = _finite(body['accuracy']);
    final details = <String, dynamic>{
      if (lat == null || lat < -90 || lat > 90) 'lat': 'Must be -90..90',
      if (lng == null || lng < -180 || lng > 180) 'lng': 'Must be -180..180',
      if (hasAccuracy &&
          (accuracy == null || accuracy < 0 || accuracy > _maxAccuracy))
        'accuracy': 'Must be 0..$_maxAccuracy',
    };
    if (details.isNotEmpty) throw MockException.validation(details);

    if (member['locationSharing'] != 'always') {
      throw const MockException(
        403,
        'LOCATION_SHARING_DISABLED',
        'Location sharing is not set to always',
      );
    }
    final recordedAt = req.db.nowIso();
    req.db.update(MockDb.members, member['id'] as String, {
      'lastLocation': {
        'lat': lat,
        'lng': lng,
        'accuracy': hasAccuracy ? accuracy : null,
        'recordedAt': recordedAt,
      },
    });
    return MockResponse.ok({'recordedAt': recordedAt});
  });

  // POST /me/devices { token, platform, locale? } → { registered: true }
  // Upsert by token; a token moves to the latest user; at most
  // [_maxDevicesPerUser] devices per account (least recently seen dropped).
  b.on('POST', '/me/devices', (req) {
    final user = req.requireUser();
    final db = req.db;
    final token = _deviceToken(req.body['token']);
    final platform = req.body['platform'];
    final locale = _blankToNull(req.body['locale']);
    final details = <String, dynamic>{
      if (token == null) 'token': 'Invalid device token',
      if (platform != 'android' && platform != 'ios')
        'platform': 'Must be android or ios',
      if (locale != null &&
          (locale is! String || AppLanguages.byCode(locale) == null))
        'locale': 'Unsupported language',
    };
    if (details.isNotEmpty) throw MockException.validation(details);

    final userId = user['id'] as String;
    final fields = <String, dynamic>{
      'userId': userId,
      'token': token,
      'platform': platform,
      // Absent → pushes use the account locale (backend: `locale ?? null`).
      'locale': locale,
      'lastSeenAt': db.nowIso(),
    };
    final existing = db.findOne(MockDb.devices, (d) => d['token'] == token);
    if (existing == null) {
      db.insert(MockDb.devices, fields);
    } else {
      db.update(MockDb.devices, existing['id'] as String, fields);
    }
    _pruneDevices(db, userId);
    return const MockResponse.ok({'registered': true});
  });

  // DELETE /me/devices/:token → null (idempotent; only the caller's token,
  // existence of other accounts' tokens is never revealed).
  b.on('DELETE', '/me/devices/:token', (req) {
    final user = req.requireUser();
    final token = _deviceToken(req.param('token'));
    if (token == null) {
      throw const MockException.validation({'token': 'Invalid device token'});
    }
    req.db.removeWhere(
      MockDb.devices,
      (d) => d['token'] == token && d['userId'] == user['id'],
    );
    return const MockResponse.ok();
  });

  // GET /me/export → the caller's personal data (works without a family).
  b.on('GET', '/me/export', (req) {
    final user = req.requireUser();
    return MockResponse.ok(_export(req.db, user));
  });

  // DELETE /me { password } → null
  b.on('DELETE', '/me', (req) {
    final user = req.requireUser();
    final db = req.db;
    final password = req.body['password'];
    if (password is! String ||
        password.isEmpty ||
        password.length > _maxPasswordLength) {
      throw const MockException.validation({
        'password': 'Password is required',
      });
    }
    if (user['password'] != password) {
      throw const MockException.unauthorized(
        'INVALID_CREDENTIALS',
        'Invalid password',
      );
    }

    final member = _ownMember(db, user);
    if (member != null) _removeSelfFromFamily(db, member);

    final userId = user['id'] as String;
    // End every session (rows are deleted, like the backend) + devices.
    db.removeWhere(MockDb.devices, (d) => d['userId'] == userId);
    db.removeWhere(MockDb.refreshTokens, (t) => t['userId'] == userId);
    db.removeWhere(
      MockDb.otps,
      (o) => o['userId'] == userId || o['email'] == user['email'],
    );
    db.remove(MockDb.users, userId);
    return const MockResponse.ok();
  });

  // POST /me/leave-family → { user } (the caller stays signed in).
  b.on('POST', '/me/leave-family', (req) {
    final user = req.requireUser();
    final member = req.requireMember();
    final db = req.db;
    _removeSelfFromFamily(db, member);

    final userId = user['id'] as String;
    db.update(MockDb.users, userId, {'familyId': null, 'memberId': null});
    final fresh = db.findById(MockDb.users, userId) ?? user;
    return MockResponse.ok({'user': MockSerializers.user(db, fresh)});
  });
}

/// Registers the `/uploads` mock routes (docs/03-API_CONTRACT.md §12).
///
/// `POST /uploads/signature` returns a fake (unusable) signature. The upload
/// service only calls it when a Cloudinary cloud name is configured without
/// an upload preset; without any Cloudinary config it keeps picked images as
/// local file paths in mock mode. Order like the backend: `401` →
/// `403 NO_FAMILY` → `422` (exact folder names only).
void registerUploadMocks(MockBackend b) {
  b.on('POST', '/uploads/signature', (req) {
    final member = req.requireMember();
    final folder = req.body['folder'];
    if (folder != 'avatars' && folder != 'notices') {
      throw const MockException.validation({
        'folder': 'Must be one of: avatars, notices',
      });
    }
    return MockResponse.ok({
      'cloudName': 'demo',
      'apiKey': '000000000000000',
      'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'signature': req.db.randomHex(20),
      'folder': 'familyhub/${member['familyId']}/$folder',
    });
  });
}

// ── rules ───────────────────────────────────────────────────────────────────

const _maxNameLength = 60;
const _maxPasswordLength = 128;
const _maxAccuracy = 100000;
const _maxDeviceTokenLength = 4096;
const _maxDevicesPerUser = 10;
const _oldestBirthYear = 1900;

/// `GET /me/export` format version (backend `EXPORT_FORMAT_VERSION`).
const _exportFormatVersion = 1;

/// Last characters of a push token shown in the export.
const _tokenSuffixLength = 6;

const _patchableFields = {
  'name',
  'phone',
  'avatarUrl',
  'locale',
  'locationSharing',
  'gender',
  'dateOfBirth',
};

const _locationModes = {'never', 'sos_only', 'always'};
const _genders = {'male', 'female', 'other'};

final _phonePattern = RegExp(r'^\+?\d{6,15}$');

/// Backend `phone` block strips spaces, dashes and brackets.
final _phoneSeparators = RegExp(r'[\s\-()]');

/// FCM token: printable ASCII without spaces.
final _deviceTokenPattern = RegExp(r'^[\x21-\x7E]+$');

/// `YYYY-MM-DD` or a date-time **with** `Z` / offset (backend `isoDate`).
final _isoDatePattern = RegExp(
  r'^\d{4}-\d{2}-\d{2}(T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:?\d{2}))?$',
);

// ── helpers ─────────────────────────────────────────────────────────────────

/// The shared PATCH rule: blank strings mean `null` (clear the field).
Object? _blankToNull(Object? v) => v is String && v.trim().isEmpty ? null : v;

String? _trimmed(Object? v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

String _normalizePhone(String v) => v.trim().replaceAll(_phoneSeparators, '');

double? _finite(Object? v) {
  if (v is! num) return null;
  final d = v.toDouble();
  return d.isFinite ? d : null;
}

/// Trimmed, valid FCM token or `null`.
String? _deviceToken(Object? v) {
  if (v is! String) return null;
  final t = v.trim();
  if (t.isEmpty ||
      t.length > _maxDeviceTokenLength ||
      !_deviceTokenPattern.hasMatch(t)) {
    return null;
  }
  return t;
}

/// Backend `isoDate`: `YYYY-MM-DD` (read as UTC midnight, like JavaScript's
/// `new Date('1985-01-31')`) or a date-time with `Z` / offset; the calendar
/// date must exist (no 31 February). `null` when invalid.
DateTime? _parseIsoDate(Object? raw) {
  if (raw is! String) return null;
  final t = raw.trim();
  if (!_isoDatePattern.hasMatch(t)) return null;
  final y = int.parse(t.substring(0, 4));
  final m = int.parse(t.substring(5, 7));
  final d = int.parse(t.substring(8, 10));
  final day = DateTime.utc(y, m, d);
  if (day.year != y || day.month != m || day.day != d) return null;
  return t.length == 10 ? day : DateTime.tryParse(t);
}

/// Backend `dateOfBirth` rule: an ISO date, not in the future (one day of
/// time-zone slack), not before 1900 (UTC). `null` when valid.
String? _dateOfBirthError(DateTime? dob) {
  if (dob == null) return 'Invalid date';
  if (dob.isAfter(DateTime.now().add(const Duration(days: 1)))) {
    return 'Date of birth cannot be in the future';
  }
  if (dob.toUtc().year < _oldestBirthYear) return 'Invalid date of birth';
  return null;
}

/// Contract: only `res.cloudinary.com` image URLs. Mock mode additionally
/// accepts local file paths (see [registerMeMocks]).
bool _isAllowedImageUrl(String url) {
  if (url.isEmpty || url.length > FamilyMockService.maxAvatarUrlLength) {
    return false;
  }
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  if (uri.scheme == 'https') return uri.host == 'res.cloudinary.com';
  return !uri.hasScheme || uri.scheme == 'file' || uri.scheme == 'blob';
}

/// The caller's member document, or `null` without (a consistent) family.
Map<String, dynamic>? _ownMember(MockDb db, Map<String, dynamic> user) {
  final member = db.findById(MockDb.members, user['memberId']);
  if (member == null || member['familyId'] != user['familyId']) return null;
  return member;
}

List<Map<String, dynamic>> _otherMembers(
  MockDb db,
  Map<String, dynamic> member,
) => db.where(
  MockDb.members,
  (m) => m['familyId'] == member['familyId'] && m['id'] != member['id'],
);

/// Admin of [others] who can sign in (managed profiles cannot run a family).
bool _isAdminWithAccount(Map<String, dynamic> m) =>
    m['role'] == 'admin' && m['userId'] is String;

/// `409 LAST_ADMIN` when [member] is an admin and no other admin with an
/// account remains among [others] (backend `assertNotLastAdmin`).
void _assertNotLastAdmin(
  Map<String, dynamic> member,
  List<Map<String, dynamic>> others,
) {
  if (member['role'] != 'admin') return;
  if (others.any(_isAdminWithAccount)) return;
  throw const MockException.conflict(
    'LAST_ADMIN',
    'The family needs at least one admin',
  );
}

/// Backend `removeSelfFromFamily`: the only member deletes the family;
/// otherwise the LAST_ADMIN rule, then the member-removal cascade. The user
/// row is **not** touched here (leave unlinks it, delete removes it) and its
/// sessions are kept.
void _removeSelfFromFamily(MockDb db, Map<String, dynamic> member) {
  final memberId = member['id'] as String;
  final familyId = member['familyId'] as String;
  final others = _otherMembers(db, member);
  if (others.isEmpty) {
    _deleteFamily(db, familyId);
    return;
  }
  _assertNotLastAdmin(member, others);
  // The admin-removal cascade (pending tasks, emergency card, active SOS,
  // ledger names, member row) minus its "end the user's sessions" part:
  // without `userId` it leaves the account alone.
  FamilyMockService.removeMember(db, {
    ...member,
    'userId': null,
  }, removedByMemberId: memberId);
  _transferOwnership(db, familyId, fromUserId: member['userId']);
}

/// The family owner left: ownership moves to the longest-standing remaining
/// admin with an account (backend `settleFamily`).
void _transferOwnership(MockDb db, String familyId, {Object? fromUserId}) {
  final family = db.findById(MockDb.families, familyId);
  if (family == null || fromUserId == null) return;
  if (family['ownerId'] != fromUserId) return;
  final heirs = db.where(
    MockDb.members,
    (m) => m['familyId'] == familyId && _isAdminWithAccount(m),
  )..sort((a, b) => _compareIso(a['createdAt'], b['createdAt']));
  if (heirs.isEmpty) return;
  db.update(MockDb.families, familyId, {'ownerId': heirs.first['userId']});
}

/// Deletes the family and every family-scoped document (the last member
/// left) and unlinks its users, who stay signed in (backend
/// `deleteFamilyCascade`).
void _deleteFamily(MockDb db, String familyId) {
  final memberIds = {
    for (final m in db.where(MockDb.members, (m) => m['familyId'] == familyId))
      m['id'],
  };
  for (final collection in const [
    MockDb.tasks,
    MockDb.ledgerEntries,
    MockDb.goals,
    MockDb.notices,
    MockDb.sosAlerts,
    MockDb.emergencyCards,
    MockDb.members,
  ]) {
    db.removeWhere(
      collection,
      (d) => d['familyId'] == familyId || memberIds.contains(d['memberId']),
    );
  }
  db.updateWhere(MockDb.users, (u) => u['familyId'] == familyId, {
    'familyId': null,
    'memberId': null,
  });
  db.remove(MockDb.families, familyId);
}

/// Keeps the [_maxDevicesPerUser] most recently seen devices of [userId].
void _pruneDevices(MockDb db, String userId) {
  final devices = db.where(MockDb.devices, (d) => d['userId'] == userId)
    ..sort((a, b) {
      final bySeen = _compareIso(b['lastSeenAt'], a['lastSeenAt']);
      return bySeen != 0 ? bySeen : '${b['id']}'.compareTo('${a['id']}');
    });
  for (final stale in devices.skip(_maxDevicesPerUser)) {
    db.remove(MockDb.devices, stale['id'] as String);
  }
}

int _compareIso(Object? a, Object? b) {
  final da = MockDb.parse(a);
  final dbb = MockDb.parse(b);
  if (da == null || dbb == null) {
    return da == null ? (dbb == null ? 0 : 1) : -1;
  }
  return da.compareTo(dbb);
}

List<Map<String, dynamic>> _sorted(
  List<Map<String, dynamic>> docs,
  String key,
) => docs..sort((a, b) => _compareIso(a[key], b[key]));

/// `GET /me/export` payload, same shape as the backend's `buildExport`:
/// account, member profile (with the member's own stored location), family,
/// currency, emergency card, tasks (assigned to / created / completed by
/// the caller), ledger entries they own or created, notices they authored,
/// their SOS alerts (with trail), push devices (token masked) and sign-in
/// sessions. Never includes passwords, token values or the invite code.
Map<String, dynamic> _export(MockDb db, Map<String, dynamic> user) {
  final now = DateTime.now();
  final member = _ownMember(db, user);
  final family = member == null
      ? null
      : db.findById(MockDb.families, member['familyId']);
  final linked = member != null && family != null;
  final memberId = member?['id'];
  final familyId = member?['familyId'];
  final userId = user['id'];

  List<Map<String, dynamic>> inFamily(
    String collection,
    bool Function(Map<String, dynamic> d) test, {
    String sortKey = 'createdAt',
  }) => linked
      ? _sorted(
          db.where(collection, (d) => d['familyId'] == familyId && test(d)),
          sortKey,
        )
      : const [];

  final card = linked
      ? db.findOne(MockDb.emergencyCards, (c) => c['memberId'] == memberId)
      : null;

  return {
    'formatVersion': _exportFormatVersion,
    'exportedAt': MockDb.iso(now),
    'user': {
      ...MockSerializers.user(db, user),
      if (!linked) 'role': null,
      'updatedAt': user['updatedAt'],
      'lastLoginAt': user['lastLoginAt'],
      'consentAcceptedAt': user['consentAcceptedAt'],
    },
    'member': linked
        ? {
            ...MockSerializers.member(member),
            // The member's own stored location, whatever the sharing mode.
            'lastLocation': member['lastLocation'],
            'guardianConsentAt': member['guardianConsentAt'],
          }
        : null,
    'family': linked
        ? MockSerializers.family(db, family, isAdmin: false)
        : null,
    'currency': linked ? family['currency'] : null,
    'emergencyCard': card == null ? null : serializeMockCard(card),
    'tasks': [
      for (final t in inFamily(
        MockDb.tasks,
        (t) =>
            t['assigneeId'] == memberId ||
            t['createdById'] == memberId ||
            t['completedById'] == memberId,
      ))
        mockTaskJson(db, t),
    ],
    'ledgerEntries': [
      for (final e in inFamily(
        MockDb.ledgerEntries,
        (e) => e['memberId'] == memberId || e['createdById'] == memberId,
        sortKey: 'date',
      ))
        mockEntryJson(e),
    ],
    'notices': [
      for (final n in inFamily(
        MockDb.notices,
        (n) => n['authorId'] == memberId,
      ))
        mockNoticeJson(db, n),
    ],
    'sosAlerts': [
      for (final a in inFamily(
        MockDb.sosAlerts,
        (a) => a['memberId'] == memberId,
        sortKey: 'startedAt',
      ))
        _exportSosAlert(db, a, now),
    ],
    'devices': [
      for (final d in _sorted(
        db.where(MockDb.devices, (d) => d['userId'] == userId),
        'createdAt',
      ))
        {
          'platform': d['platform'],
          'locale': d['locale'],
          'tokenSuffix': _tokenSuffix(d['token']),
          'createdAt': d['createdAt'],
          'lastSeenAt': d['lastSeenAt'],
        },
    ],
    'sessions': [
      for (final t in _sorted(
        db.where(MockDb.refreshTokens, (t) => t['userId'] == userId),
        'createdAt',
      ))
        {
          'createdAt': t['createdAt'],
          'expiresAt': t['expiresAt'],
          'revokedAt': t['revokedAt'],
          'active':
              t['revokedAt'] == null &&
              (MockDb.parse(t['expiresAt'])?.isAfter(now) ?? false),
          'ip': t['ip'],
          'userAgent': t['userAgent'],
        },
    ],
  };
}

String _tokenSuffix(Object? token) {
  final t = '${token ?? ''}';
  return t.length <= _tokenSuffixLength
      ? t
      : t.substring(t.length - _tokenSuffixLength);
}

/// Contract `SosAlert` (with `trail`) for the export; an `active` alert past
/// `expiresAt` is reported as `expired` (lazy expiry, not written).
Map<String, dynamic> _exportSosAlert(
  MockDb db,
  Map<String, dynamic> a,
  DateTime now,
) {
  final expiresAt = MockDb.parse(a['expiresAt']);
  final expired =
      a['status'] == 'active' && expiresAt != null && !expiresAt.isAfter(now);
  final name = MockSerializers.memberName(db, a['memberId']);
  return {
    'id': a['id'],
    'memberId': a['memberId'],
    'memberName': name.isNotEmpty ? name : a['memberName'],
    'status': expired ? 'expired' : a['status'],
    'message': a['message'],
    'locationShared': a['locationShared'] == true,
    'lastLocation': a['lastLocation'],
    'trail': a['trail'] is List ? a['trail'] : const <Object?>[],
    'startedAt': a['startedAt'],
    'expiresAt': a['expiresAt'],
    'resolvedAt': a['resolvedAt'],
    'resolvedById': a['resolvedById'],
    'resolution': a['resolution'],
  };
}
