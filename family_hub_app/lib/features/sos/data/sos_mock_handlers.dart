import 'package:family_hub/core/config/app_config.dart';
import 'package:family_hub/core/network/mock/mock_backend.dart';

/// Registers the `/sos` mock routes (docs/03-API_CONTRACT.md §10) and seeds
/// one resolved alert into the demo family's history.
///
/// | route                        | who            | notes                                                  |
/// |------------------------------|----------------|--------------------------------------------------------|
/// | `POST /sos`                  | member         | idempotent: an active alert of the caller is returned (200) |
/// | `GET /sos/active`            | member         | active alerts of the family, newest first, `trail: []` |
/// | `GET /sos/history`           | member         | resolved / expired, newest first, paginated            |
/// | `GET /sos/:id`               | member         | includes `trail` (≤ 100 newest, oldest first)          |
/// | `POST /sos/:id/location`     | alert owner    | 3 s store throttle, trail cap 100                      |
/// | `POST /sos/:id/resolve`      | owner or admin | idempotent on resolved, `409` on expired               |
///
/// Behaviour mirrors the backend module (docs/progress/b-sos.md):
/// * **Lazy expiry**: every route first persists `active` → `expired` for
///   alerts of the caller's family whose 15-minute window has passed.
/// * A caller whose sharing mode is `never` raises alerts without location
///   (`locationShared: false`); location updates then answer
///   `403 LOCATION_SHARING_DISABLED`. The owner's **current** mode governs:
///   switching to `never` hides the stored points, switching back shows them.
/// * Only `GET /sos/:id` returns the trail; every other response sends
///   `trail: []`.
/// * `memberName` / `memberPhone` / `memberAvatarUrl` are resolved from the
///   member at read time (`null` once the member left the family).
///
/// Check order like the backend: `401` → `403 NO_FAMILY` → `400` (malformed
/// id) → `422 VALIDATION_ERROR` → `404` (unknown id / other family) →
/// `403 FORBIDDEN` → `409 SOS_NOT_ACTIVE` → `403 LOCATION_SHARING_DISABLED`.
/// Nothing is written on an error. Push notifications are not simulated.
void registerSosMocks(MockBackend b) {
  seedMockSosAlerts(b.db);
  b.on('POST', '/sos', _create);
  b.on('GET', '/sos/active', _active);
  b.on('GET', '/sos/history', _history);
  b.on('GET', '/sos/:id', _get);
  b.on('POST', '/sos/:id/location', _location);
  b.on('POST', '/sos/:id/resolve', _resolve);
}

/// Id of the seeded history alert (Priya, resolved "safe" three days ago).
const mockSeededSosAlertId = '64f1a0000000000000000901';

/// Location updates closer together than this are accepted but not stored.
const mockSosLocationThrottle = Duration(seconds: 3);

/// Maximum number of trail points kept per alert.
const mockSosTrailMax = 100;

/// Seeds `sosAlerts` once per database: no active alert, one resolved alert
/// in the history (with a short trail).
void seedMockSosAlerts(MockDb db) {
  db.seedOnce(MockDb.sosAlerts, () {
    final started = DateTime.now().subtract(const Duration(days: 3, hours: 2));
    String at(Duration offset) => MockDb.iso(started.add(offset));
    Map<String, dynamic> point(double lat, double lng, double acc, int sec) => {
      'lat': lat,
      'lng': lng,
      'accuracy': acc,
      'recordedAt': at(Duration(seconds: sec)),
    };
    final trail = [
      point(28.5355, 77.3910, 18, 0),
      point(28.5361, 77.3902, 12, 40),
      point(28.5368, 77.3897, 9, 95),
      point(28.5372, 77.3893, 8, 170),
    ];
    return [
      {
        'id': mockSeededSosAlertId,
        'familyId': MockSeed.familyId,
        'memberId': MockSeed.priyaMemberId,
        'memberName': 'Priya',
        'status': 'resolved',
        'message': null,
        'locationShared': true,
        'lastLocation': trail.last,
        'trail': trail,
        'startedAt': at(Duration.zero),
        'expiresAt': at(AppConfig.sosTrackingWindow),
        'resolvedAt': at(const Duration(minutes: 6)),
        'resolvedById': MockSeed.priyaMemberId,
        'resolution': 'safe',
        'createdAt': at(Duration.zero),
        'updatedAt': at(const Duration(minutes: 6)),
      },
    ];
  });
}

// ── serialization (also used by the dashboard / export mocks) ─────────────

/// Effective status of a stored alert at [now] (lazy expiry, not written).
String mockSosStatus(Map<String, dynamic> doc, DateTime now) {
  final status = '${doc['status'] ?? ''}';
  if (status != 'active') return status;
  final expiresAt = MockDb.parse(doc['expiresAt']);
  return expiresAt != null && !expiresAt.isAfter(now) ? 'expired' : status;
}

/// Contract `SosAlert` for a stored document. [withTrail] only for
/// `GET /sos/:id`.
Map<String, dynamic> mockSosAlertJson(
  MockDb db,
  Map<String, dynamic> doc, {
  bool withTrail = false,
  DateTime? now,
}) {
  final member = db.findById(MockDb.members, doc['memberId']);
  final owner = member != null && member['familyId'] == doc['familyId']
      ? member
      : null;
  // The owner's current mode governs; a removed owner shares nothing.
  final shared =
      doc['locationShared'] == true &&
      owner != null &&
      (owner['locationSharing'] ?? 'never') != 'never';
  return {
    'id': doc['id'],
    'memberId': doc['memberId'],
    'memberName': owner?['name'],
    'memberPhone': _blankToNull(owner?['phone']),
    'memberAvatarUrl': _blankToNull(owner?['avatarUrl']),
    'status': mockSosStatus(doc, now ?? DateTime.now()),
    'message': _blankToNull(doc['message']),
    'locationShared': shared,
    'lastLocation': shared ? doc['lastLocation'] : null,
    'trail': withTrail && shared ? _trail(doc['trail']) : const <Object?>[],
    'startedAt': doc['startedAt'],
    'expiresAt': doc['expiresAt'],
    'resolvedAt': doc['resolvedAt'],
    'resolvedById': doc['resolvedById'],
    'resolution': doc['resolution'],
  };
}

/// Active alerts of [familyId] after lazy expiry, newest first, serialized
/// like `GET /sos/active` (for the dashboard's `activeSos`).
List<Map<String, dynamic>> mockActiveSosAlerts(MockDb db, String familyId) {
  final now = DateTime.now();
  mockExpireStaleSosAlerts(db, familyId, now);
  final docs = db.where(
    MockDb.sosAlerts,
    (d) => d['familyId'] == familyId && d['status'] == 'active',
  )..sort(_newestFirst);
  return [for (final d in docs) mockSosAlertJson(db, d, now: now)];
}

// ── handlers ────────────────────────────────────────────────────────────────

MockResponse _create(MockRequest req) {
  final me = req.requireMember();
  final body = req.body;
  final errors = <String, String>{};
  Map<String, dynamic>? location;
  if (body['location'] != null) {
    location = _latLng(body['location'], errors, prefix: 'location.');
  }
  final message = _message(body, errors);
  if (errors.isNotEmpty) throw MockException.validation(errors);

  final db = req.db;
  final familyId = me['familyId'] as String;
  final now = DateTime.now();
  mockExpireStaleSosAlerts(db, familyId, now);

  final existing = db.findOne(
    MockDb.sosAlerts,
    (d) =>
        d['familyId'] == familyId &&
        d['memberId'] == me['id'] &&
        d['status'] == 'active',
  );
  if (existing != null) {
    // Idempotent: the repeat's message / location are ignored.
    return MockResponse.ok(mockSosAlertJson(db, existing, now: now));
  }

  final shared = (me['locationSharing'] ?? 'never') != 'never';
  final nowIso = MockDb.iso(now);
  final point = shared && location != null
      ? {...location, 'recordedAt': nowIso}
      : null;
  final doc = db.insert(MockDb.sosAlerts, {
    'familyId': familyId,
    'memberId': me['id'],
    'memberName': me['name'],
    'status': 'active',
    'message': message,
    'locationShared': shared,
    'lastLocation': point,
    'trail': [?point],
    'startedAt': nowIso,
    'expiresAt': MockDb.iso(now.add(AppConfig.sosTrackingWindow)),
    'resolvedAt': null,
    'resolvedById': null,
    'resolution': null,
  });
  return MockResponse.created(mockSosAlertJson(db, doc, now: now));
}

MockResponse _active(MockRequest req) {
  req.requireMember();
  return MockResponse.ok(mockActiveSosAlerts(req.db, req.familyId));
}

MockResponse _history(MockRequest req) {
  req.requireMember();
  // Validate `page` / `limit` before touching the database.
  req.page;
  req.limit;
  final db = req.db;
  final familyId = req.familyId;
  final now = DateTime.now();
  mockExpireStaleSosAlerts(db, familyId, now);
  final docs = db.where(
    MockDb.sosAlerts,
    (d) =>
        d['familyId'] == familyId &&
        (d['status'] == 'resolved' || d['status'] == 'expired'),
  )..sort(_newestFirst);
  return MockResponse.paged([
    for (final d in docs) mockSosAlertJson(db, d, now: now),
  ], req);
}

MockResponse _get(MockRequest req) {
  req.requireMember();
  final id = _objectId(req);
  final db = req.db;
  final now = DateTime.now();
  mockExpireStaleSosAlerts(db, req.familyId, now);
  final doc = req.findInFamily(MockDb.sosAlerts, id);
  return MockResponse.ok(mockSosAlertJson(db, doc, withTrail: true, now: now));
}

MockResponse _location(MockRequest req) {
  final me = req.requireMember();
  final id = _objectId(req);
  final errors = <String, String>{};
  final point = _latLng(req.body, errors);
  if (errors.isNotEmpty || point == null) {
    throw MockException.validation(errors);
  }

  final db = req.db;
  final now = DateTime.now();
  mockExpireStaleSosAlerts(db, req.familyId, now);
  final doc = req.findInFamily(MockDb.sosAlerts, id);
  if (doc['memberId'] != me['id']) {
    throw const MockException.forbidden(
      'Only the member who raised the SOS can share its location',
    );
  }
  if (mockSosStatus(doc, now) != 'active') {
    throw const MockException.conflict(
      'SOS_NOT_ACTIVE',
      'This SOS alert has already ended',
    );
  }
  if ((me['locationSharing'] ?? 'never') == 'never') {
    throw const MockException(
      403,
      'LOCATION_SHARING_DISABLED',
      'Location sharing is turned off',
    );
  }

  final last = _lastRecordedAt(doc);
  if (last != null && now.difference(last) < mockSosLocationThrottle) {
    // Accepted but not stored.
    return MockResponse.ok(mockSosAlertJson(db, doc, now: now));
  }
  final stored = {...point, 'recordedAt': MockDb.iso(now)};
  final trail = [if (doc['trail'] is List) ...(doc['trail'] as List), stored];
  final capped = trail.length > mockSosTrailMax
      ? trail.sublist(trail.length - mockSosTrailMax)
      : trail;
  final updated =
      db.update(MockDb.sosAlerts, id, {
        'lastLocation': stored,
        'trail': capped,
        // Switching from `never` to another mode during an alert starts
        // sharing.
        'locationShared': true,
      }) ??
      doc;
  return MockResponse.ok(mockSosAlertJson(db, updated, now: now));
}

MockResponse _resolve(MockRequest req) {
  final me = req.requireMember();
  final id = _objectId(req);
  final resolution = req.body['resolution'];
  if (resolution is! String || !_resolutions.contains(resolution)) {
    throw MockException.validation({
      'resolution': 'Must be one of ${_resolutions.join(', ')}',
    });
  }

  final db = req.db;
  final now = DateTime.now();
  mockExpireStaleSosAlerts(db, req.familyId, now);
  final doc = req.findInFamily(MockDb.sosAlerts, id);
  if (doc['memberId'] != me['id'] && me['role'] != 'admin') {
    throw const MockException.forbidden(
      'Only the member or an admin can resolve this SOS',
    );
  }
  switch (mockSosStatus(doc, now)) {
    case 'resolved':
      // Idempotent: the first resolution wins.
      return MockResponse.ok(mockSosAlertJson(db, doc, now: now));
    case 'active':
      final updated =
          db.update(MockDb.sosAlerts, id, {
            'status': 'resolved',
            'resolvedAt': MockDb.iso(now),
            'resolvedById': me['id'],
            'resolution': resolution,
          }) ??
          doc;
      return MockResponse.ok(mockSosAlertJson(db, updated, now: now));
    default:
      throw const MockException.conflict(
        'SOS_NOT_ACTIVE',
        'This SOS alert has already ended',
      );
  }
}

// ── helpers ─────────────────────────────────────────────────────────────────

const _resolutions = ['safe', 'false_alarm', 'helped'];
const _messageMax = 140;
const _accuracyMax = 100000;

final _objectIdPattern = RegExp(r'^[0-9a-fA-F]{24}$');

String _objectId(MockRequest req) {
  final id = req.param('id');
  if (!_objectIdPattern.hasMatch(id)) {
    throw const MockException.badRequest('Invalid id');
  }
  return id;
}

/// Persists lazy expiry for [familyId] (`active` past `expiresAt` →
/// `expired`), like the backend's `expireStaleAlerts`. Public for other
/// mocks that end alerts (e.g. the member-removal cascade must expire stale
/// alerts first, so an alert whose window had passed is reported as
/// `expired`, not closed by the removal).
void mockExpireStaleSosAlerts(MockDb db, String familyId, [DateTime? now]) {
  final at = now ?? DateTime.now();
  db.updateWhere(
    MockDb.sosAlerts,
    (d) =>
        d['familyId'] == familyId &&
        d['status'] == 'active' &&
        mockSosStatus(d, at) == 'expired',
    {'status': 'expired'},
  );
}

int _newestFirst(Map<String, dynamic> a, Map<String, dynamic> b) {
  // ISO-8601 UTC strings with milliseconds sort lexicographically.
  final byStart = '${b['startedAt'] ?? ''}'.compareTo(
    '${a['startedAt'] ?? ''}',
  );
  return byStart != 0 ? byStart : '${b['id']}'.compareTo('${a['id']}');
}

/// `{ lat, lng, accuracy? }` like the backend's `latLng` zod block: plain
/// finite numbers only (no numeric strings), extra keys stripped. Returns
/// `null` (and fills [errors]) when invalid.
Map<String, dynamic>? _latLng(
  Object? raw,
  Map<String, String> errors, {
  String prefix = '',
}) {
  if (raw is! Map) {
    errors[prefix.isEmpty ? 'body' : prefix.substring(0, prefix.length - 1)] =
        'Expected an object';
    return null;
  }
  num? number(String key, num min, num max, {bool optional = false}) {
    final v = raw[key];
    if (v == null) {
      if (!optional) errors['$prefix$key'] = 'Required';
      return null;
    }
    if (v is! num || !v.isFinite) {
      errors['$prefix$key'] = 'Expected a number';
      return null;
    }
    if (v < min || v > max) {
      errors['$prefix$key'] = 'Must be between $min and $max';
      return null;
    }
    return v;
  }

  final lat = number('lat', -90, 90);
  final lng = number('lng', -180, 180);
  final accuracy = number('accuracy', 0, _accuracyMax, optional: true);
  if (lat == null || lng == null) return null;
  return {
    'lat': lat.toDouble(),
    'lng': lng.toDouble(),
    'accuracy': accuracy?.toDouble(),
  };
}

/// Optional message: absent / `null` / blank / invisible-only → `null`,
/// else cleaned ([mockCleanSosMessage]) and ≤ 140 UTF-16 code units (the
/// length is checked after the clean-up, like the backend).
String? _message(Map<String, dynamic> body, Map<String, String> errors) {
  final raw = body['message'];
  if (raw == null) return null;
  if (raw is! String) {
    errors['message'] = 'Message must be text';
    return null;
  }
  final value = mockCleanSosMessage(raw);
  if (value == null) return null;
  if (value.length > _messageMax) {
    errors['message'] = 'Message must be at most $_messageMax characters';
    return null;
  }
  return value;
}

// Regex escapes (not literal characters) so the invisible code points stay
// readable in the source.
final _lineBreaks = RegExp(r'\r\n?|[\v\f\u0085\u2028\u2029]');
final _controlsExceptLf = RegExp(r'[\x00-\x09\x0B-\x1F\x7F-\x9F]');
final _bidiControls = RegExp(r'[\u202A-\u202E\u2066-\u2069]');
final _edgeBlanks = RegExp(
  r'^[\s\u200B\u2060\uFEFF]+|[\s\u200B\u2060\uFEFF]+$',
);
final _visibleChar = RegExp(
  r'[^\s\p{Cc}\p{Cf}\uFE00-\uFE0F\u115F\u1160\u3164\uFFA0\u2800]',
  unicode: true,
);

/// The backend's `cleanSosMessage` (`sos.schemas.js`): lone surrogates →
/// U+FFFD, line breaks → `\n`, tabs → a space, other control characters
/// and bidi embedding / override / isolate controls removed, trimmed
/// (also zero-width space, word joiner, BOM); nothing visible left →
/// `null`. (Unicode NFC normalisation is not mirrored: Dart has no
/// built-in normaliser.)
String? mockCleanSosMessage(String raw) {
  final text = _wellFormed(raw)
      .replaceAll(_lineBreaks, '\n')
      .replaceAll('\t', ' ')
      .replaceAll(_controlsExceptLf, '')
      .replaceAll(_bidiControls, '')
      .replaceAll(_edgeBlanks, '');
  return _visibleChar.hasMatch(text) ? text : null;
}

/// `String.prototype.toWellFormed`: every lone surrogate becomes U+FFFD.
String _wellFormed(String s) {
  final units = s.codeUnits;
  final out = StringBuffer();
  for (var i = 0; i < units.length; i++) {
    final u = units[i];
    final isHigh = u >= 0xD800 && u <= 0xDBFF;
    final isLow = u >= 0xDC00 && u <= 0xDFFF;
    if (isHigh &&
        i + 1 < units.length &&
        units[i + 1] >= 0xDC00 &&
        units[i + 1] <= 0xDFFF) {
      out.writeCharCode(
        0x10000 + ((u - 0xD800) << 10) + (units[i + 1] - 0xDC00),
      );
      i++;
    } else if (isHigh || isLow) {
      out.writeCharCode(0xFFFD);
    } else {
      out.writeCharCode(u);
    }
  }
  return out.toString();
}

DateTime? _lastRecordedAt(Map<String, dynamic> doc) {
  final trail = doc['trail'];
  if (trail is List && trail.isNotEmpty && trail.last is Map) {
    final at = MockDb.parse((trail.last as Map)['recordedAt']);
    if (at != null) return at;
  }
  final last = doc['lastLocation'];
  return last is Map ? MockDb.parse(last['recordedAt']) : null;
}

/// Newest ≤ [mockSosTrailMax] points, oldest first.
List<Object?> _trail(Object? raw) {
  if (raw is! List) return const <Object?>[];
  final points =
      [
        for (final p in raw)
          if (p is Map) p,
      ]..sort(
        (a, b) =>
            '${a['recordedAt'] ?? ''}'.compareTo('${b['recordedAt'] ?? ''}'),
      );
  return points.length > mockSosTrailMax
      ? points.sublist(points.length - mockSosTrailMax)
      : points;
}

String? _blankToNull(Object? v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}
