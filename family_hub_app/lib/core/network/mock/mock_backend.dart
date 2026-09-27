import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:family_hub/core/network/mock/mock_db.dart';

export 'package:family_hub/core/network/mock/mock_db.dart';
export 'package:family_hub/core/network/mock/mock_seed.dart';
export 'package:family_hub/core/network/mock/mock_serializers.dart';
export 'package:family_hub/core/network/mock/mock_tokens.dart';

/// Handles one mock route. Throw [MockException] for API errors.
typedef MockHandler = FutureOr<MockResponse> Function(MockRequest req);

/// In-memory implementation of `docs/03-API_CONTRACT.md`, used when the app
/// runs without `API_BASE_URL` (see `AppConfig.useMockApi`).
///
/// Feature files register routes in their `register<Feature>Mocks(b)`:
/// ```dart
/// b.on('POST', '/tasks/:id/complete', (req) {
///   final me = req.requireMember();
///   final task = req.findInFamily(MockDb.tasks, req.param('id'));
///   ...
///   return MockResponse.ok(task);
/// });
/// ```
class MockBackend {
  MockBackend([MockDb? db]) : db = db ?? MockDb();

  /// Base URL the Dio client uses in mock mode. The `.invalid` TLD can never
  /// resolve, so a request that escapes the mock interceptor fails fast
  /// instead of leaking to a real host.
  static const baseUrl = 'https://mock.familyhub.invalid/api/v1';

  final MockDb db;
  final List<_Route> _routes = [];

  /// All registered routes as `METHOD /pattern` (for debugging / tests).
  List<String> get routes => [
    for (final r in _routes) '${r.method} ${r.pattern}',
  ];

  /// Registers [handler] for [method] + [pattern]. Patterns are paths
  /// relative to `/api/v1` with `:name` parameters, e.g.
  /// `/family/members/:id/emergency-card`. Registering the same method and
  /// pattern again replaces the previous handler.
  void on(String method, String pattern, MockHandler handler) {
    final route = _Route(method.toUpperCase(), _normalize(pattern), handler);
    _routes.removeWhere(
      (r) => r.method == route.method && r.pattern == route.pattern,
    );
    _routes.add(route);
  }

  /// Dispatches a Dio request. Throws [MockException] (`404 NOT_FOUND` for
  /// an unknown route or method, like the real server's 404 handler).
  Future<MockResponse> handle(RequestOptions o) async {
    final path = relativePath(o.uri);
    final method = o.method.toUpperCase();
    final match = _match(method, path);
    if (match == null) {
      throw MockException.notFound('Route $method $path not found');
    }
    final req = MockRequest(
      method: method,
      path: path,
      pathParams: match.params,
      query: Map<String, String>.unmodifiable(o.uri.queryParameters),
      body: _parseBody(o.data),
      headers: {
        for (final e in o.headers.entries)
          e.key.toLowerCase(): e.value?.toString() ?? '',
      },
      db: db,
    );
    return await match.route.handler(req);
  }

  /// Path relative to the API root: strips the `/api/v1` prefix of
  /// [baseUrl] (or of any `/api/vN`) and trailing slashes.
  static String relativePath(Uri uri) {
    var path = uri.path;
    final basePath = Uri.parse(baseUrl).path;
    if (path.startsWith(basePath)) {
      path = path.substring(basePath.length);
    } else {
      final m = RegExp(r'^/api/v\d+').firstMatch(path);
      if (m != null) path = path.substring(m.end);
    }
    return _normalize(path);
  }

  static String _normalize(String path) {
    var p = path.trim();
    if (!p.startsWith('/')) p = '/$p';
    while (p.length > 1 && p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    return p;
  }

  _Match? _match(String method, String path) {
    final segments = _split(path);
    _Match? best;
    for (final route in _routes) {
      if (route.method != method) continue;
      final params = route.match(segments);
      if (params == null) continue;
      // Most literal segments wins (so `/sos/active` beats `/sos/:id`
      // regardless of registration order); ties → first registered.
      if (best == null || route.literalCount > best.route.literalCount) {
        best = _Match(route, params);
      }
    }
    return best;
  }

  static List<String> _split(String path) =>
      path.split('/').where((s) => s.isNotEmpty).toList();

  static Map<String, dynamic> _parseBody(Object? data) {
    Object? decoded = data;
    if (data is String) {
      if (data.trim().isEmpty) return <String, dynamic>{};
      try {
        decoded = jsonDecode(data);
      } on FormatException {
        throw const MockException.badRequest('Malformed JSON body');
      }
    } else if (data is FormData) {
      return {for (final f in data.fields) f.key: f.value};
    }
    if (decoded == null) return <String, dynamic>{};
    // JSON round-trip: same types a real server would see (no DateTime,
    // no shared references with the caller).
    try {
      decoded = jsonDecode(jsonEncode(decoded));
    } on JsonUnsupportedObjectError {
      throw const MockException.badRequest('Body is not JSON-encodable');
    }
    if (decoded is Map<String, dynamic>) return decoded;
    throw const MockException.badRequest('Body must be a JSON object');
  }
}

class _Route {
  _Route(this.method, this.pattern, this.handler)
    : _segments = MockBackend._split(pattern);

  final String method;
  final String pattern;
  final MockHandler handler;
  final List<String> _segments;
  late final int literalCount = _segments
      .where((s) => !s.startsWith(':'))
      .length;

  Map<String, String>? match(List<String> path) {
    if (path.length != _segments.length) return null;
    final params = <String, String>{};
    for (var i = 0; i < path.length; i++) {
      final seg = _segments[i];
      final value = _decode(path[i]);
      if (seg.startsWith(':')) {
        if (value.isEmpty) return null;
        params[seg.substring(1)] = value;
      } else if (seg != value) {
        return null;
      }
    }
    return params;
  }

  static String _decode(String s) {
    try {
      return Uri.decodeComponent(s);
    } catch (_) {
      return s; // malformed percent-encoding: match literally
    }
  }
}

class _Match {
  _Match(this.route, this.params);
  final _Route route;
  final Map<String, String> params;
}

/// A parsed request handed to a [MockHandler].
class MockRequest {
  MockRequest({
    required this.method,
    required this.path,
    required this.pathParams,
    required this.query,
    required this.body,
    required this.db,
    this.headers = const {},
  });

  /// Upper-case HTTP method.
  final String method;

  /// Path relative to `/api/v1`, e.g. `/tasks/abc/complete`.
  final String path;

  /// Values of `:name` segments (URL-decoded).
  final Map<String, String> pathParams;

  /// Query string values (strings, like Express).
  final Map<String, String> query;

  /// JSON body (`{}` when none).
  final Map<String, dynamic> body;

  /// Lower-cased header names.
  final Map<String, String> headers;

  final MockDb db;

  static final _bearer = RegExp(r'^Bearer\s+(\S+)$', caseSensitive: false);
  static const accessPrefix = 'mock-access.';
  static const refreshPrefix = 'mock-refresh.';

  /// Mock access token for [userId] (what `/auth/login` returns).
  static String accessTokenFor(String userId) => '$accessPrefix$userId';

  /// New mock refresh token for [userId]: `mock-refresh.<userId>.<random>`.
  static String refreshTokenFor(MockDb db, String userId) =>
      '$refreshPrefix$userId.${db.randomHex(12)}';

  /// User id encoded in a refresh token, or null when malformed.
  static String? userIdFromRefreshToken(String? token) {
    if (token == null || !token.startsWith(refreshPrefix)) return null;
    final rest = token.substring(refreshPrefix.length);
    final dot = rest.indexOf('.');
    final id = dot < 0 ? rest : rest.substring(0, dot);
    return id.isEmpty ? null : id;
  }

  /// Raw bearer token from `Authorization`, or null.
  String? get accessToken {
    final header = headers['authorization'];
    if (header == null) return null;
    return _bearer.firstMatch(header.trim())?.group(1);
  }

  /// User id from `Authorization: Bearer mock-access.<userId>`, or null when
  /// the header is missing or malformed.
  String? get userId {
    final token = accessToken;
    if (token == null || !token.startsWith(accessPrefix)) return null;
    final id = token.substring(accessPrefix.length);
    return id.isEmpty ? null : id;
  }

  /// Path parameter (throws `400 BAD_REQUEST` if the route has no such
  /// parameter — a programming error in the handler).
  String param(String name) {
    final v = pathParams[name];
    if (v == null) throw MockException.badRequest('Missing path param $name');
    return v;
  }

  /// Non-empty query value or null.
  String? q(String name) {
    final v = query[name]?.trim();
    return v == null || v.isEmpty ? null : v;
  }

  /// `?page=` (default 1, must be ≥ 1) → `422 VALIDATION_ERROR` otherwise.
  int get page => _intQuery('page', 1, min: 1);

  /// `?limit=` (default 20, 1..100) → `422 VALIDATION_ERROR` otherwise.
  int get limit => _intQuery('limit', 20, min: 1, max: 100);

  int _intQuery(String name, int fallback, {int? min, int? max}) {
    final raw = q(name);
    if (raw == null) return fallback;
    final v = int.tryParse(raw);
    if (v == null || (min != null && v < min) || (max != null && v > max)) {
      throw MockException.validation({name: 'Invalid $name'});
    }
    return v;
  }

  /// The authenticated user document (401 `UNAUTHORIZED` when the header is
  /// missing/invalid or the user no longer exists — same as the server).
  Map<String, dynamic> requireUser() {
    final id = userId;
    if (id == null) throw const MockException.unauthorized();
    final user = db.findById(MockDb.users, id);
    if (user == null) throw const MockException.unauthorized();
    return user;
  }

  /// The caller's member document (403 `NO_FAMILY` when not in a family).
  Map<String, dynamic> requireMember() {
    final user = requireUser();
    final memberId = user['memberId'];
    final familyId = user['familyId'];
    if (memberId is! String || familyId is! String) {
      throw const MockException.noFamily();
    }
    final member = db.findById(MockDb.members, memberId);
    if (member == null || member['familyId'] != familyId) {
      throw const MockException.noFamily();
    }
    return member;
  }

  /// The caller's member document; 403 `FORBIDDEN` unless admin.
  Map<String, dynamic> requireAdmin() {
    final member = requireMember();
    if (member['role'] != 'admin') throw const MockException.forbidden();
    return member;
  }

  /// The caller's family document (403 `NO_FAMILY` when missing).
  Map<String, dynamic> requireFamily() {
    final member = requireMember();
    final family = db.findById(MockDb.families, member['familyId']);
    if (family == null) throw const MockException.noFamily();
    return family;
  }

  /// Whether the caller is an admin of their family (false when signed out
  /// or without family — never throws).
  bool get isAdmin {
    try {
      return requireMember()['role'] == 'admin';
    } on MockException {
      return false;
    }
  }

  /// Caller's family id (throws like [requireMember]).
  String get familyId => requireMember()['familyId'] as String;

  /// Caller's member id (throws like [requireMember]).
  String get memberId => requireMember()['id'] as String;

  /// Documents of [collection] that belong to the caller's family.
  List<Map<String, dynamic>> familyDocs(
    String collection, [
    bool Function(Map<String, dynamic> doc)? test,
  ]) {
    final fid = familyId;
    return db.where(
      collection,
      (d) => d['familyId'] == fid && (test == null || test(d)),
    );
  }

  /// Document [id] of [collection] in the caller's family, else
  /// `404 NOT_FOUND` (never leaks other families' data).
  Map<String, dynamic> findInFamily(String collection, Object? id) {
    final doc = db.findById(collection, id);
    if (doc == null || doc['familyId'] != familyId) {
      throw const MockException.notFound();
    }
    return doc;
  }
}

/// A successful response; the interceptor wraps it in the envelope.
class MockResponse {
  const MockResponse(this.status, this.data, [this.meta]);

  /// `200 { success: true, data }`.
  const MockResponse.ok([this.data]) : status = 200, meta = null;

  /// `201 { success: true, data }`.
  const MockResponse.created(this.data) : status = 201, meta = null;

  /// Paginates [items] using the request's `page` / `limit` query values
  /// and sets `meta` like the real API.
  factory MockResponse.paged(List<dynamic> items, MockRequest req) {
    final page = req.page;
    final limit = req.limit;
    final start = (page - 1) * limit;
    final slice = start >= items.length
        ? const <dynamic>[]
        : items.sublist(start, (start + limit).clamp(0, items.length));
    return MockResponse(200, slice, {
      'page': page,
      'limit': limit,
      'total': items.length,
      'hasMore': start + slice.length < items.length,
    });
  }

  final int status;
  final Object? data;
  final Map<String, dynamic>? meta;
}

/// An API error; the interceptor turns it into the error envelope.
class MockException implements Exception {
  const MockException(this.status, this.code, [this.message, this.details]);

  const MockException.badRequest([String message = 'Bad request'])
    : this(400, 'BAD_REQUEST', message);

  const MockException.unauthorized([
    String code = 'UNAUTHORIZED',
    String message = 'Authentication required',
  ]) : this(401, code, message);

  const MockException.forbidden([String message = 'Not allowed'])
    : this(403, 'FORBIDDEN', message);

  const MockException.noFamily([String message = 'You are not in a family'])
    : this(403, 'NO_FAMILY', message);

  const MockException.notFound([String message = 'Not found'])
    : this(404, 'NOT_FOUND', message);

  /// `409` with a contract code, e.g. `EMAIL_TAKEN`, `LAST_ADMIN`.
  const MockException.conflict(String code, [String? message])
    : this(409, code, message);

  /// `422 VALIDATION_ERROR` with `details` = field → message.
  const MockException.validation(
    Map<String, dynamic> details, [
    String message = 'Validation failed',
  ]) : this(422, 'VALIDATION_ERROR', message, details);

  /// `429 TOO_MANY_REQUESTS` with `details.retryAfterSeconds`.
  MockException.tooManyRequests(int retryAfterSeconds)
    : this(429, 'TOO_MANY_REQUESTS', 'Too many requests', {
        'retryAfterSeconds': retryAfterSeconds,
      });

  final int status;
  final String code;
  final String? message;
  final Map<String, dynamic>? details;

  Map<String, dynamic> toEnvelope() => {
    'success': false,
    'error': {
      'code': code,
      'message': message ?? code,
      if (details != null) 'details': details,
    },
  };

  @override
  String toString() => 'MockException($status $code: $message)';
}
