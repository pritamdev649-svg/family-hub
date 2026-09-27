import 'dart:math';

import 'package:family_hub/core/network/mock/mock_seed.dart';

/// In-memory "MongoDB" for the mock backend.
///
/// Documents are plain JSON maps with a string `id` (24 hex chars, like an
/// ObjectId). **Reads return deep copies**: mutating a map returned by
/// [col], [where], [findById] or [findOne] never changes the database — use
/// [insert], [update], [replace], [remove] and [removeWhere] to write.
/// This mirrors a real server where handlers work on copies of DB rows and
/// keeps response decoration (e.g. adding `assigneeName`) from leaking into
/// stored data.
class MockDb {
  /// [seedCore] seeds the demo family/users/members (see [MockSeed]).
  /// [random] can be injected for deterministic ids in tests.
  MockDb({bool seedCore = true, Random? random})
    : _random = random ?? Random() {
    if (seedCore) MockSeed.seedCore(this);
  }

  /// Collection names used across the mock (contract resources + auth).
  static const users = 'users';
  static const families = 'families';
  static const members = 'members';
  static const refreshTokens = 'refreshTokens';
  static const otps = 'otps';
  static const devices = 'devices';
  static const tasks = 'tasks';
  static const ledgerEntries = 'ledgerEntries';
  static const goals = 'goals';
  static const notices = 'notices';
  static const sosAlerts = 'sosAlerts';
  static const emergencyCards = 'emergencyCards';

  static const collectionNames = [
    users,
    families,
    members,
    refreshTokens,
    otps,
    devices,
    tasks,
    ledgerEntries,
    goals,
    notices,
    sosAlerts,
    emergencyCards,
  ];

  /// Raw storage. Prefer the helpers; direct access bypasses copy-on-read.
  final Map<String, List<Map<String, dynamic>>> collections = {};

  final Random _random;
  final Set<String> _seeded = {};
  int _counter = 0;

  List<Map<String, dynamic>> _raw(String name) =>
      collections.putIfAbsent(name, () => <Map<String, dynamic>>[]);

  // ── ids & time ───────────────────────────────────────────────────────────

  /// A new unique 24-hex id: 4-byte timestamp + 5 random bytes + 3-byte
  /// counter (same layout as a MongoDB ObjectId).
  String newId() {
    final seconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final buffer = StringBuffer(_hex(seconds & 0xFFFFFFFF, 8));
    for (var i = 0; i < 5; i++) {
      buffer.write(_hex(_random.nextInt(256), 2));
    }
    _counter = (_counter + 1) & 0xFFFFFF;
    buffer.write(_hex(_counter, 6));
    return buffer.toString();
  }

  /// Random token-ish string (hex) for refresh tokens, etc.
  String randomHex([int bytes = 16]) {
    final buffer = StringBuffer();
    for (var i = 0; i < bytes; i++) {
      buffer.write(_hex(_random.nextInt(256), 2));
    }
    return buffer.toString();
  }

  /// Random integer in `[0, max)`.
  int randomInt(int max) => _random.nextInt(max);

  static String _hex(int v, int width) =>
      v.toRadixString(16).padLeft(width, '0');

  /// Current time as an ISO-8601 UTC string with milliseconds, exactly like
  /// the real API (`2026-09-26T10:15:00.000Z`).
  String nowIso() => iso(DateTime.now());

  /// Formats [d] as the API does (UTC, millisecond precision).
  static String iso(DateTime d) => DateTime.fromMillisecondsSinceEpoch(
    d.millisecondsSinceEpoch,
    isUtc: true,
  ).toIso8601String();

  /// Parses an ISO string stored in a document (null-safe).
  static DateTime? parse(Object? v) =>
      v is String ? DateTime.tryParse(v) : null;

  // ── seeding ──────────────────────────────────────────────────────────────

  /// Seeds [collection] with [seed] once per database instance. Feature mock
  /// files call this from their `register*Mocks` function. Seed documents
  /// without an `id` get one.
  void seedOnce(String collection, List<Map<String, dynamic>> Function() seed) {
    if (!_seeded.add(collection)) return;
    final raw = _raw(collection);
    for (final doc in seed()) {
      final copy = copyDoc(doc);
      copy['id'] ??= newId();
      raw.add(copy);
    }
  }

  bool isSeeded(String collection) => _seeded.contains(collection);

  /// Empties every collection and forgets what was seeded.
  void reset({bool seedCore = true}) {
    collections.clear();
    _seeded.clear();
    if (seedCore) MockSeed.seedCore(this);
  }

  // ── reads (deep copies) ──────────────────────────────────────────────────

  /// Snapshot of every document in [name] (a new growable list of copies).
  List<Map<String, dynamic>> col(String name) => [
    for (final d in _raw(name)) copyDoc(d),
  ];

  /// Copies of the documents matching [test].
  List<Map<String, dynamic>> where(
    String name,
    bool Function(Map<String, dynamic> doc) test,
  ) => [
    for (final d in _raw(name))
      if (test(d)) copyDoc(d),
  ];

  Map<String, dynamic>? findById(String name, Object? id) {
    if (id is! String || id.isEmpty) return null;
    for (final d in _raw(name)) {
      if (d['id'] == id) return copyDoc(d);
    }
    return null;
  }

  Map<String, dynamic>? findOne(
    String name,
    bool Function(Map<String, dynamic> doc) test,
  ) {
    for (final d in _raw(name)) {
      if (test(d)) return copyDoc(d);
    }
    return null;
  }

  int count(String name, [bool Function(Map<String, dynamic> doc)? test]) =>
      test == null ? _raw(name).length : _raw(name).where(test).length;

  bool exists(String name, bool Function(Map<String, dynamic> doc) test) =>
      _raw(name).any(test);

  // ── writes ───────────────────────────────────────────────────────────────

  /// Inserts a copy of [doc] and returns a copy of the stored document.
  /// Assigns `id` if missing; with [timestamps] sets `createdAt` /
  /// `updatedAt` when absent.
  Map<String, dynamic> insert(
    String name,
    Map<String, dynamic> doc, {
    bool timestamps = true,
  }) {
    final copy = copyDoc(doc);
    copy['id'] ??= newId();
    if (timestamps) {
      final now = nowIso();
      copy['createdAt'] ??= now;
      copy['updatedAt'] ??= now;
    }
    _raw(name).add(copy);
    return copyDoc(copy);
  }

  /// Merges [patch] into the document (keys with null values are set to
  /// null, not removed). With [timestamps] bumps `updatedAt` unless the patch
  /// sets it. Returns the updated copy, or null when not found.
  Map<String, dynamic>? update(
    String name,
    String id,
    Map<String, dynamic> patch, {
    bool timestamps = true,
  }) {
    final raw = _raw(name);
    final index = raw.indexWhere((d) => d['id'] == id);
    if (index < 0) return null;
    final doc = raw[index];
    doc.addAll(copyDoc(patch));
    doc['id'] = id; // ids are immutable
    if (timestamps && !patch.containsKey('updatedAt')) {
      doc['updatedAt'] = nowIso();
    }
    return copyDoc(doc);
  }

  /// Applies [patch] to every document matching [test]; returns the count.
  int updateWhere(
    String name,
    bool Function(Map<String, dynamic> doc) test,
    Map<String, dynamic> patch, {
    bool timestamps = true,
  }) {
    var n = 0;
    for (final doc in _raw(name)) {
      if (!test(doc)) continue;
      final id = doc['id'];
      doc.addAll(copyDoc(patch));
      doc['id'] = id;
      if (timestamps && !patch.containsKey('updatedAt')) {
        doc['updatedAt'] = nowIso();
      }
      n++;
    }
    return n;
  }

  /// Replaces the whole document (keeps its id). Returns the stored copy or
  /// null when not found.
  Map<String, dynamic>? replace(
    String name,
    String id,
    Map<String, dynamic> doc,
  ) {
    final raw = _raw(name);
    final index = raw.indexWhere((d) => d['id'] == id);
    if (index < 0) return null;
    final copy = copyDoc(doc)..['id'] = id;
    raw[index] = copy;
    return copyDoc(copy);
  }

  /// Removes the document; returns whether it existed.
  bool remove(String name, String id) {
    final raw = _raw(name);
    final before = raw.length;
    raw.removeWhere((d) => d['id'] == id);
    return raw.length != before;
  }

  /// Removes all matching documents; returns how many were removed.
  int removeWhere(String name, bool Function(Map<String, dynamic> doc) test) {
    final raw = _raw(name);
    final before = raw.length;
    raw.removeWhere(test);
    return before - raw.length;
  }

  // ── helpers ──────────────────────────────────────────────────────────────

  /// Deep copy of a document (nested maps become `Map<String, dynamic>`,
  /// nested lists `List<dynamic>`).
  static Map<String, dynamic> copyDoc(Map<dynamic, dynamic> doc) =>
      _copy(doc)! as Map<String, dynamic>;

  /// Deep copy of any JSON-like value (Map / List / scalars).
  static Object? deepCopy(Object? value) => _copy(value);

  static Object? _copy(Object? v) {
    if (v is Map) {
      return <String, dynamic>{
        for (final e in v.entries) '${e.key}': _copy(e.value),
      };
    }
    if (v is List) return <dynamic>[for (final e in v) _copy(e)];
    return v;
  }
}
