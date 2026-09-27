import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Small JSON cache on top of [SharedPreferences] for "last known good" data
/// (e.g. the session so the app opens offline, dashboard snapshot).
///
/// Values are stored as `{"t": savedAtIso, "v": json}` under
/// `cache.<key>`; [clear] only removes these entries, never other
/// preferences (settings live in the same store).
///
/// Do not store secrets here — use `TokenStorage` for tokens.
class LocalCache {
  LocalCache(this._prefs);

  static const prefix = 'cache.';

  final SharedPreferences _prefs;

  String _k(String key) => '$prefix$key';

  /// Stores any JSON-encodable value (Map/List/String/num/bool/null).
  /// Returns false when the value is not encodable or the write failed.
  Future<bool> write(String key, Object? json) async {
    try {
      final payload = jsonEncode({
        't': DateTime.now().toUtc().toIso8601String(),
        'v': json,
      });
      return await _prefs.setString(_k(key), payload);
    } catch (e) {
      debugPrint('LocalCache: write "$key" failed ($e)');
      return false;
    }
  }

  /// Raw decoded JSON for [key], or null when missing, corrupt or older than
  /// [maxAge].
  Object? readJson(String key, {Duration? maxAge}) {
    final entry = _entry(key);
    if (entry == null) return null;
    if (maxAge != null) {
      final saved = DateTime.tryParse('${entry['t']}');
      if (saved == null || DateTime.now().toUtc().difference(saved) > maxAge) {
        return null;
      }
    }
    return entry['v'];
  }

  /// Decodes the value with [decode]; returns null (and drops the entry) if
  /// decoding throws, so a model change never bricks app start.
  T? read<T>(String key, T Function(Object? json) decode, {Duration? maxAge}) {
    final json = readJson(key, maxAge: maxAge);
    if (json == null) return null;
    try {
      return decode(json);
    } catch (e) {
      debugPrint('LocalCache: decode "$key" failed ($e); dropping entry');
      remove(key);
      return null;
    }
  }

  /// Convenience for object payloads.
  Map<String, dynamic>? readMap(String key, {Duration? maxAge}) {
    final json = readJson(key, maxAge: maxAge);
    return json is Map ? Map<String, dynamic>.from(json) : null;
  }

  /// When [key] was last written (UTC), or null.
  DateTime? savedAt(String key) {
    final entry = _entry(key);
    return entry == null ? null : DateTime.tryParse('${entry['t']}');
  }

  bool contains(String key) => _prefs.containsKey(_k(key));

  Future<void> remove(String key) async {
    try {
      await _prefs.remove(_k(key));
    } catch (e) {
      debugPrint('LocalCache: remove "$key" failed ($e)');
    }
  }

  /// Removes every cache entry (call on logout / account switch).
  Future<void> clear() async {
    final keys = _prefs.getKeys().where((k) => k.startsWith(prefix)).toList();
    for (final k in keys) {
      try {
        await _prefs.remove(k);
      } catch (e) {
        debugPrint('LocalCache: clear "$k" failed ($e)');
      }
    }
  }

  Map<String, dynamic>? _entry(String key) {
    final raw = _prefs.getString(_k(key));
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded.containsKey('v')) {
        return Map<String, dynamic>.from(decoded);
      }
    } on FormatException {
      // fall through
    }
    remove(key);
    return null;
  }
}
