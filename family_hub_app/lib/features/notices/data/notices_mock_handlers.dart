import 'package:family_hub/core/network/mock/mock_backend.dart';

/// Registers the `/notices` mock routes (docs/03-API_CONTRACT.md §9) and
/// seeds the demo notice board.
///
/// | route                   | who             | notes                                      |
/// |-------------------------|-----------------|--------------------------------------------|
/// | `GET /notices`          | member          | paginated; pinned first, then newest first |
/// | `POST /notices`         | member          | `pinned` ignored unless admin              |
/// | `PATCH /notices/:id`    | author or admin | changing `pinned` → admin only (403)       |
/// | `DELETE /notices/:id`   | author or admin |                                            |
///
/// Check order like the backend (routes → zod → service): `401` → `403
/// NO_FAMILY` → `400 BAD_REQUEST` (malformed id) → `422 VALIDATION_ERROR`
/// (field details) → `404 NOT_FOUND` (unknown id or another family's
/// notice) → `403 FORBIDDEN`. Nothing is written on an error. Push
/// notifications are not simulated.
void registerNoticeMocks(MockBackend b) {
  seedMockNotices(b.db);
  b.on('GET', '/notices', _list);
  b.on('POST', '/notices', _create);
  b.on('PATCH', '/notices/:id', _update);
  b.on('DELETE', '/notices/:id', _delete);
}

/// Title of the pinned demo notice.
const mockPinnedNoticeTitle = 'Family meeting Sunday 7pm';

/// Seeds the demo family's notice board once per database: four notices by
/// the two demo admins, one of them pinned, one long (to show "Read more")
/// and one with a photo.
void seedMockNotices(MockDb db) {
  db.seedOnce(MockDb.notices, () {
    final now = DateTime.now();
    String ago(Duration d) => MockDb.iso(now.subtract(d));
    Map<String, dynamic> notice({
      required String id,
      required String title,
      required String body,
      required String authorId,
      required Duration age,
      bool pinned = false,
      String? imageUrl,
    }) => {
      'id': id,
      'familyId': MockSeed.familyId,
      'title': title,
      'body': body,
      'imageUrl': imageUrl,
      'pinned': pinned,
      'authorId': authorId,
      'createdAt': ago(age),
      'updatedAt': ago(age),
    };

    return [
      notice(
        id: '64f1a0000000000000000701',
        title: mockPinnedNoticeTitle,
        body:
            'Our monthly family check-in is on Sunday at 7pm in the living '
            'room. Agenda: holiday plans, the exam timetable and our new '
            'savings goal. Please be on time!',
        authorId: MockSeed.amitMemberId,
        age: const Duration(days: 2, hours: 3),
        pinned: true,
      ),
      notice(
        id: '64f1a0000000000000000702',
        title: 'Electricity bill paid',
        body:
            "This month's electricity bill is paid. Please switch off lights "
            'and the AC when you leave a room.',
        authorId: MockSeed.priyaMemberId,
        age: const Duration(hours: 5),
      ),
      notice(
        id: '64f1a0000000000000000703',
        title: "Grandma's check-up on Thursday",
        body:
            'Kamla has her regular check-up with Dr. Rao on Thursday at 11am. '
            'I will take her, but I need someone to pick up Anaya from school '
            'at 1pm that day.\n\n'
            'Things to remember:\n'
            '- Bring the blue folder with her last reports.\n'
            '- Her new glasses are ready at the optician next to the clinic.\n'
            '- We should leave by 10:15 because of the traffic.\n\n'
            'Reply in the family chat if you can help with the school pickup. '
            'Thank you!',
        authorId: MockSeed.priyaMemberId,
        age: const Duration(days: 1, hours: 2),
      ),
      notice(
        id: '64f1a0000000000000000704',
        title: 'Weekend trip photos',
        body: 'What a lovely weekend at the lake! More photos are coming soon.',
        authorId: MockSeed.amitMemberId,
        age: const Duration(days: 4),
        imageUrl: 'https://res.cloudinary.com/demo/image/upload/sample.jpg',
      ),
    ];
  });
}

/// Contract `Notice` for a stored document. `authorName` / `authorAvatarUrl`
/// are resolved from the author's member document at read time, like the
/// backend's `memberDirectory`: both are `null` once the author is no longer
/// a member of the notice's family (the app shows "Former member").
Map<String, dynamic> mockNoticeJson(MockDb db, Map<String, dynamic> doc) {
  final member = db.findById(MockDb.members, doc['authorId']);
  final author = member != null && member['familyId'] == doc['familyId']
      ? member
      : null;
  return {
    'id': doc['id'],
    'title': doc['title'],
    'body': doc['body'],
    'imageUrl': doc['imageUrl'],
    'pinned': doc['pinned'] == true,
    'authorId': doc['authorId'],
    'authorName': author?['name'],
    'authorAvatarUrl': author?['avatarUrl'],
    'createdAt': doc['createdAt'],
    'updatedAt': doc['updatedAt'],
  };
}

/// Board order of `GET /notices`: pinned first, then `createdAt` desc (ties
/// by id desc, so the order is stable).
int compareMockNotices(Map<String, dynamic> a, Map<String, dynamic> b) {
  final pa = a['pinned'] == true ? 0 : 1;
  final pb = b['pinned'] == true ? 0 : 1;
  if (pa != pb) return pa - pb;
  final ca = '${a['createdAt'] ?? ''}';
  final cb = '${b['createdAt'] ?? ''}';
  // ISO-8601 UTC strings with milliseconds sort lexicographically.
  final byDate = cb.compareTo(ca);
  if (byDate != 0) return byDate;
  return '${b['id']}'.compareTo('${a['id']}');
}

/// The family's notices, serialized and sorted like `GET /notices`.
/// Also useful for the dashboard (`latestNotices`) and `/me/export` mocks.
List<Map<String, dynamic>> mockFamilyNotices(MockDb db, String familyId) {
  final docs = db.where(MockDb.notices, (d) => d['familyId'] == familyId)
    ..sort(compareMockNotices);
  return [for (final d in docs) mockNoticeJson(db, d)];
}

// ── handlers ────────────────────────────────────────────────────────────────

MockResponse _list(MockRequest req) {
  req.requireMember();
  // `paged` validates `page` / `limit` (422 when out of range).
  return MockResponse.paged(mockFamilyNotices(req.db, req.familyId), req);
}

MockResponse _create(MockRequest req) {
  final me = req.requireMember();
  final body = req.body;
  final errors = <String, String>{};
  final title = _text(body, 'title', _titleMax, errors, required: true);
  final text = _text(body, 'body', _bodyMax, errors, required: true);
  final image = _imageUrl(body, errors);
  final pinned = _bool(body, 'pinned', errors);
  if (errors.isNotEmpty) throw MockException.validation(errors);

  final doc = req.db.insert(MockDb.notices, {
    'familyId': me['familyId'],
    'title': title,
    'body': text,
    'imageUrl': image.value,
    // `pinned` is silently ignored for non-admins (contract §9).
    'pinned': me['role'] == 'admin' && pinned == true,
    'authorId': me['id'],
  });
  return MockResponse.created(mockNoticeJson(req.db, doc));
}

MockResponse _update(MockRequest req) {
  final me = req.requireMember();
  final id = _objectId(req);
  final body = req.body;
  final errors = <String, String>{};
  final changes = <String, dynamic>{};
  if (body.containsKey('title')) {
    changes['title'] = _text(body, 'title', _titleMax, errors, required: true);
  }
  if (body.containsKey('body')) {
    changes['body'] = _text(body, 'body', _bodyMax, errors, required: true);
  }
  final image = _imageUrl(body, errors);
  if (image.present) changes['imageUrl'] = image.value;
  final pinned = _bool(body, 'pinned', errors);
  if (errors.isNotEmpty) throw MockException.validation(errors);

  final notice = req.findInFamily(MockDb.notices, id);
  final isAdmin = me['role'] == 'admin';
  if (!isAdmin && notice['authorId'] != me['id']) {
    throw const MockException.forbidden();
  }
  // Only values that differ are written; an unchanged PATCH keeps
  // `updatedAt` (backend `updateNotice`).
  final patch = <String, dynamic>{
    for (final e in changes.entries)
      if (e.value != notice[e.key]) e.key: e.value,
  };
  // Sending the current `pinned` value is allowed (full forms); changing it
  // needs an admin.
  if (pinned != null && pinned != (notice['pinned'] == true)) {
    if (!isAdmin) {
      throw const MockException.forbidden('Only admins can pin notices');
    }
    patch['pinned'] = pinned;
  }
  final updated = patch.isEmpty
      ? notice
      : req.db.update(MockDb.notices, id, patch) ?? notice;
  return MockResponse.ok(mockNoticeJson(req.db, updated));
}

MockResponse _delete(MockRequest req) {
  final me = req.requireMember();
  final id = _objectId(req);
  final notice = req.findInFamily(MockDb.notices, id);
  if (me['role'] != 'admin' && notice['authorId'] != me['id']) {
    throw const MockException.forbidden();
  }
  req.db.remove(MockDb.notices, id);
  return const MockResponse.ok();
}

// ── validation (mirrors the backend's zod schemas) ─────────────────────────

const _titleMax = 100;
const _bodyMax = 2000;
const _urlMax = 1024;

final _objectIdPattern = RegExp(r'^[0-9a-fA-F]{24}$');

String _objectId(MockRequest req) {
  final id = req.param('id');
  if (!_objectIdPattern.hasMatch(id)) {
    throw const MockException.badRequest('Invalid id');
  }
  return id;
}

/// Trimmed string of 1..[max] UTF-16 code units (zod `.trim().min(1).max()`).
String? _text(
  Map<String, dynamic> body,
  String field,
  int max,
  Map<String, String> errors, {
  required bool required,
}) {
  final raw = body[field];
  if (raw == null) {
    if (required) errors[field] = 'Required';
    return null;
  }
  if (raw is! String) {
    errors[field] = 'Expected text';
    return null;
  }
  final value = raw.trim();
  if (value.isEmpty) {
    errors[field] = 'Required';
    return null;
  }
  if (value.length > max) {
    errors[field] = 'Must be at most $max characters';
    return null;
  }
  return value;
}

/// Optional boolean (zod `z.boolean().optional()`): absent → `null`; an
/// explicit `null` or any non-boolean is a validation error.
bool? _bool(
  Map<String, dynamic> body,
  String field,
  Map<String, String> errors,
) {
  if (!body.containsKey(field)) return null;
  final raw = body[field];
  if (raw is bool) return raw;
  errors[field] = 'Expected true or false';
  return null;
}

/// `imageUrl`: absent, `null` / blank (no image) or an
/// `https://res.cloudinary.com/...` URL like the backend requires. The mock
/// also accepts local file paths, which is what uploads return in mock mode
/// without a Cloudinary configuration.
({bool present, String? value}) _imageUrl(
  Map<String, dynamic> body,
  Map<String, String> errors,
) {
  if (!body.containsKey('imageUrl')) return (present: false, value: null);
  final raw = body['imageUrl'];
  if (raw == null) return (present: true, value: null);
  if (raw is! String) {
    errors['imageUrl'] = 'Invalid image URL';
    return (present: true, value: null);
  }
  final value = raw.trim();
  if (value.isEmpty) return (present: true, value: null);
  if (value.length > _urlMax || !_isAcceptedImage(value)) {
    errors['imageUrl'] = 'Image must be uploaded to res.cloudinary.com';
    return (present: true, value: null);
  }
  return (present: true, value: value);
}

bool _isAcceptedImage(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null) return false;
  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'https') return uri.host.toLowerCase() == 'res.cloudinary.com';
  if (scheme == 'http') return false;
  // Local upload in mock mode: absolute path, `file://` URI or `C:\...`.
  return scheme == 'file' ||
      (scheme.isEmpty && value.startsWith('/')) ||
      scheme.length == 1;
}
