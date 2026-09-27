import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:family_hub/core/storage/auth_tokens.dart';

export 'package:family_hub/core/storage/auth_tokens.dart';

/// Persists the [AuthTokens] in the platform keychain / keystore with an
/// in-memory cache so the auth interceptor does not hit secure storage on
/// every request.
///
/// Failures of the secure store (e.g. a keystore invalidated after a device
/// restore) never crash the app: reads fall back to "signed out" and writes
/// keep the in-memory session alive for this run.
class TokenStorage {
  TokenStorage({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            // Readable after the first unlock so SOS location streaming and
            // background sync keep working while the phone is locked; never
            // restored onto a different device from a backup.
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
            mOptions: MacOsOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  static const storageKey = 'familyhub.auth.tokens.v1';

  final FlutterSecureStorage _storage;

  AuthTokens? _cache;
  bool _loaded = false;
  Future<AuthTokens?>? _loading;

  /// Tokens currently held in memory (null before the first [read] or when
  /// signed out). Synchronous; prefer [read] unless you know it was loaded.
  AuthTokens? get cached => _cache;

  /// Current tokens; loads from secure storage once, then serves the cache.
  /// Concurrent first calls share a single platform read.
  Future<AuthTokens?> read() {
    if (_loaded) return Future.value(_cache);
    return _loading ??= _load();
  }

  Future<String?> get accessToken async => (await read())?.accessToken;

  Future<String?> get refreshToken async => (await read())?.refreshToken;

  Future<bool> get hasTokens async => (await read()) != null;

  Future<AuthTokens?> _load() async {
    try {
      final raw = await _storage.read(key: storageKey);
      if (_loaded) return _cache; // a save()/clear() won the race
      _cache = raw == null ? null : _decode(raw);
      if (raw != null && _cache == null) {
        // Corrupt payload: drop it so we don't retry forever.
        await _safeDelete();
      }
    } catch (e) {
      debugPrint('TokenStorage: read failed ($e); treating as signed out');
      if (!_loaded) {
        _cache = null;
        await _safeDelete();
      }
    } finally {
      _loaded = true;
      _loading = null;
    }
    return _cache;
  }

  Future<void> save(AuthTokens tokens) async {
    _cache = tokens;
    _loaded = true;
    try {
      await _storage.write(key: storageKey, value: jsonEncode(tokens.toJson()));
    } catch (e) {
      // Keep the in-memory session; the user will simply have to sign in
      // again after an app restart.
      debugPrint('TokenStorage: write failed ($e)');
    }
  }

  Future<void> clear() async {
    _cache = null;
    _loaded = true;
    await _safeDelete();
  }

  Future<void> _safeDelete() async {
    try {
      await _storage.delete(key: storageKey);
    } catch (e) {
      debugPrint('TokenStorage: delete failed ($e)');
    }
  }

  static AuthTokens? _decode(String raw) {
    try {
      return AuthTokens.tryParse(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }
}
