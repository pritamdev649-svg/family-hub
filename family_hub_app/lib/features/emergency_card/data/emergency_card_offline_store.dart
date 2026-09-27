import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:family_hub/core/providers/core_providers.dart';
import 'package:family_hub/features/emergency_card/domain/emergency_card.dart';
import 'package:family_hub/shared/json.dart';
import 'package:family_hub/shared/models/member.dart';
import 'package:family_hub/shared/providers/shared_providers.dart';

/// Minimal async key-value store for secrets (keychain / keystore). An
/// interface so tests can use an in-memory map.
abstract interface class SecureKeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<Map<String, String>> readAll();
}

/// [SecureKeyValueStore] on the platform keychain / keystore.
class FlutterSecureKeyValueStore implements SecureKeyValueStore {
  FlutterSecureKeyValueStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            // Same policy as the auth tokens: readable after the first unlock
            // (cards open while the phone was locked in between) and never
            // restored onto another device from a backup.
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
            mOptions: MacOsOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<Map<String, String>> readAll() => _storage.readAll();
}

/// Offline copy of emergency cards — emergencies often happen with bad
/// network, so every successfully loaded card is kept on the device and
/// served when the server cannot be reached.
///
/// Storage (decision, see docs/progress/f-emergency.md):
/// * The card itself is **health data**, so it lives in secure storage
///   (docs/08-COMPLIANCE.md §3 row 19: never cached unencrypted), under
///   `familyhub.emergencyCard.<memberId>` together with the id of the
///   signed-in user it belongs to.
/// * A marker without health data is written to [LocalCache] under
///   `emergencyCard.<memberId>` ([cacheKey]). Its save time is the "offline
///   copy saved at" moment, and because the session clears [LocalCache] on
///   logout / account switch / session expiry, a missing marker invalidates
///   the secure copy: it is deleted on the next read, and orphans are purged
///   once per app run before the first read or write.
/// * The family's member directory (name, avatar, designation — no health
///   data, no location) is cached in [LocalCache] under [membersCacheKey] so
///   the cards list also works offline.
///
/// Every method is best effort and never throws: a broken keystore only
/// means there is no offline copy.
///
/// Writes (save / remove / clear) run one at a time, and with
/// [currentUserId] a save for any account but the signed-in one is dropped.
/// So a request that finishes after logout can never leave health data
/// behind: either it lands before the wipe (and is wiped), or it runs after
/// it and is ignored.
class EmergencyCardOfflineStore {
  EmergencyCardOfflineStore({
    required LocalCache cache,
    required SecureKeyValueStore secure,
    String? Function()? currentUserId,
  }) : _cache = cache,
       _secure = secure,
       _currentUserId = currentUserId;

  /// Prefix of the [LocalCache] markers (`emergencyCard.<memberId>`).
  static const cachePrefix = 'emergencyCard.';

  /// Prefix of the secure-storage entries.
  static const securePrefix = 'familyhub.emergencyCard.';

  /// [LocalCache] key of the member directory snapshot.
  static const membersCacheKey = 'emergencyCard.members';

  static const _version = 1;

  static String cacheKey(String memberId) => '$cachePrefix$memberId';
  static String secureKey(String memberId) => '$securePrefix$memberId';

  final LocalCache _cache;
  final SecureKeyValueStore _secure;

  /// The signed-in account right now (read at write time); `null` = no
  /// session check (tests / tools).
  final String? Function()? _currentUserId;

  /// Last payload written per member in this run (skips identical writes to
  /// the keystore when the same card is loaded again).
  final Map<String, String> _written = {};

  Future<void>? _purge;

  /// Tail of the write queue (see [_serial]).
  Future<void> _writes = Future<void>.value();

  bool _acceptsWritesFor(String userId) {
    final current = _currentUserId;
    if (current == null) return true;
    try {
      return current() == userId;
    } catch (e) {
      // The app is shutting down (container disposed): keep nothing.
      return false;
    }
  }

  /// Runs [op] after every write queued before it (never concurrently).
  /// The operations catch their own errors; a failure never blocks the queue.
  Future<void> _serial(Future<void> Function() op) {
    final settled = _writes.then((_) => op()).catchError((Object e) {
      debugPrint('EmergencyCardOfflineStore: write failed (${e.runtimeType})');
    });
    _writes = settled;
    return settled;
  }

  /// Removes secure copies whose [LocalCache] marker is gone. Runs once;
  /// every other operation waits for it, so it can never race a save.
  Future<void> _ready() => _purge ??= _purgeOrphans();

  Future<void> _purgeOrphans() async {
    try {
      final all = await _secure.readAll();
      for (final key in all.keys) {
        if (!key.startsWith(securePrefix)) continue;
        final memberId = key.substring(securePrefix.length);
        if (memberId.isEmpty || !_cache.contains(cacheKey(memberId))) {
          await _secure.delete(key);
        }
      }
    } catch (e) {
      debugPrint('EmergencyCardOfflineStore: purge failed (${e.runtimeType})');
    }
  }

  /// Keeps [card] as the offline copy for [userId]'s session. Ignored when
  /// [userId] is no longer the signed-in account (see the constructor's
  /// `currentUserId`).
  Future<void> save(String userId, EmergencyCard card) {
    final memberId = card.memberId.trim();
    if (memberId.isEmpty || userId.isEmpty) return Future<void>.value();
    return _serial(() async {
      await _ready();
      // Checked inside the queue: a logout's wipe queued earlier has run.
      if (!_acceptsWritesFor(userId)) return;
      final payload = jsonEncode({
        'v': _version,
        'u': userId,
        'card': card.copyWith(offlineSavedAt: () => null).toJson(),
      });
      try {
        if (_written[memberId] != payload) {
          await _secure.write(secureKey(memberId), payload);
          _written[memberId] = payload;
        }
        // Re-written even when unchanged: its timestamp is "verified at".
        await _cache.write(cacheKey(memberId), {'u': userId});
      } catch (e) {
        _written.remove(memberId);
        debugPrint('EmergencyCardOfflineStore: save failed (${e.runtimeType})');
      }
    });
  }

  /// The offline copy of [memberId]'s card for [userId], marked with
  /// [EmergencyCard.offlineSavedAt]; `null` when there is none (or it belongs
  /// to another account, or is unreadable — then it is deleted).
  Future<EmergencyCard?> load(String userId, String memberId) async {
    final id = memberId.trim();
    if (id.isEmpty || userId.isEmpty) return null;
    await _ready();
    final marker = _cache.readMap(cacheKey(id));
    if (marker == null || marker['u'] != userId) {
      await remove(id);
      return null;
    }
    try {
      final raw = await _secure.read(secureKey(id));
      if (raw == null) {
        await _cache.remove(cacheKey(id));
        return null;
      }
      final json = asMap(jsonDecode(raw));
      if (json['u'] != userId || json['card'] is! Map) {
        await remove(id);
        return null;
      }
      final now = DateTime.now().toUtc();
      var savedAt = _cache.savedAt(cacheKey(id)) ?? now;
      // A clock that was set back must not make the copy look "from the
      // future" ("in 3 hours").
      if (savedAt.isAfter(now)) savedAt = now;
      final card = EmergencyCard.fromJson(
        asMap(json['card']),
        fallbackMemberId: id,
      );
      if (card.memberId != id) {
        await remove(id);
        return null;
      }
      return card.copyWith(offlineSavedAt: () => savedAt);
    } catch (e) {
      debugPrint('EmergencyCardOfflineStore: load failed (${e.runtimeType})');
      await remove(id);
      return null;
    }
  }

  /// Deletes [memberId]'s offline copy (e.g. the member was removed).
  Future<void> remove(String memberId) {
    final id = memberId.trim();
    if (id.isEmpty) return Future<void>.value();
    return _serial(() async {
      _written.remove(id);
      await _cache.remove(cacheKey(id));
      try {
        await _secure.delete(secureKey(id));
      } catch (e) {
        debugPrint(
          'EmergencyCardOfflineStore: remove failed (${e.runtimeType})',
        );
      }
    });
  }

  /// Deletes every offline card and the member directory (call on logout).
  Future<void> clearAll() => _serial(() async {
    _written.clear();
    await _cache.remove(membersCacheKey);
    try {
      final all = await _secure.readAll();
      for (final key in all.keys) {
        if (!key.startsWith(securePrefix)) continue;
        await _cache.remove(cacheKey(key.substring(securePrefix.length)));
        await _secure.delete(key);
      }
    } catch (e) {
      debugPrint('EmergencyCardOfflineStore: clear failed (${e.runtimeType})');
    }
  });

  // ── Member directory ─────────────────────────────────────────────────────

  /// Caches the family's members for the offline cards list. Only what the
  /// list and card header show is kept (data minimisation; the location is
  /// never written to disk).
  Future<void> saveMembers(String userId, List<Member> members) async {
    if (userId.isEmpty || !_acceptsWritesFor(userId)) return;
    await _cache.write(membersCacheKey, {
      'u': userId,
      'members': [for (final m in members) _minimalMember(m)],
    });
  }

  /// The cached member directory of [userId] (`null` when none).
  List<Member>? loadMembers(String userId) {
    final json = _cache.readMap(membersCacheKey);
    if (json == null || userId.isEmpty || json['u'] != userId) return null;
    return List.unmodifiable(
      asMapList(json['members'], Member.fromJson).where((m) => m.id.isNotEmpty),
    );
  }

  static Map<String, dynamic> _minimalMember(Member m) => {
    'id': m.id,
    'familyId': m.familyId,
    'userId': m.userId,
    'name': m.name,
    'phone': m.phone,
    'avatarUrl': m.avatarUrl,
    'designation': m.designation,
    'role': m.role.wireName,
    'hasAccount': m.hasAccount,
  };
}

/// Secure storage used for offline cards (override in tests).
final emergencyCardSecureStoreProvider = Provider<SecureKeyValueStore>(
  (ref) => FlutterSecureKeyValueStore(),
);

/// The offline store, bound to the signed-in account: saves of any other
/// account (a request that finished after logout) are ignored — checked
/// against the live session, so it works even while nothing listens to this
/// provider. When the account changes during a run (logout, session expiry,
/// account switch) every offline card is wiped right away instead of waiting
/// for the next start's orphan purge.
final emergencyCardOfflineStoreProvider = Provider<EmergencyCardOfflineStore>((
  ref,
) {
  final container = ref.container;
  final store = EmergencyCardOfflineStore(
    cache: ref.watch(localCacheProvider),
    secure: ref.watch(emergencyCardSecureStoreProvider),
    currentUserId: () => container.read(sessionUserIdProvider),
  );
  ref.listen<String?>(sessionUserIdProvider, (previous, next) {
    if (previous != null && previous != next) unawaited(store.clearAll());
  });
  return store;
});
