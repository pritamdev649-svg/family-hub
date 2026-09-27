import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:family_hub/core/storage/local_cache.dart';
import 'package:family_hub/features/emergency_card/data/emergency_card_offline_store.dart';
import 'package:family_hub/features/emergency_card/domain/emergency_card.dart';

import 'emergency_card_test_utils.dart';

void main() {
  late LocalCache cache;
  late InMemorySecureStore secure;
  late EmergencyCardOfflineStore store;

  setUp(() async {
    cache = LocalCache(await mockPrefs());
    secure = InMemorySecureStore();
    store = EmergencyCardOfflineStore(cache: cache, secure: secure);
  });

  test(
    'health data goes to secure storage, only a marker to LocalCache',
    () async {
      final card = fullCard('m1');
      await store.save(testUserId, card);

      final key = EmergencyCardOfflineStore.secureKey('m1');
      expect(secure.data[key], contains('Penicillin'));
      expect(cache.contains(EmergencyCardOfflineStore.cacheKey('m1')), isTrue);
      final marker = cache.readJson(EmergencyCardOfflineStore.cacheKey('m1'));
      expect('$marker', isNot(contains('Penicillin')));

      final loaded = await store.load(testUserId, 'm1');
      expect(loaded, isNotNull);
      expect(loaded!.isOfflineCopy, isTrue);
      expect(loaded.offlineSavedAt, isNotNull);
      expect(loaded.copyWith(offlineSavedAt: () => null), card);
    },
  );

  test('identical cards are not re-written to the keystore', () async {
    await store.save(testUserId, fullCard('m1'));
    await store.save(testUserId, fullCard('m1'));
    expect(secure.writes, 1);
    await store.save(testUserId, fullCard('m1').copyWith(notes: () => 'new'));
    expect(secure.writes, 2);
  });

  test('another account never sees the copy (and it is deleted)', () async {
    await store.save(testUserId, fullCard('m1'));
    expect(await store.load('someone-else', 'm1'), isNull);
    expect(secure.data, isEmpty);
    expect(await store.load(testUserId, 'm1'), isNull);
  });

  test('clearing LocalCache (logout) invalidates the secure copy', () async {
    await store.save(testUserId, fullCard('m1'));
    await cache.clear();
    expect(await store.load(testUserId, 'm1'), isNull);
    expect(secure.data, isEmpty);
  });

  test(
    'orphaned secure copies are purged once, before the first use',
    () async {
      await store.save(testUserId, fullCard('m1'));
      await store.save(testUserId, fullCard('m2'));
      await cache.remove(EmergencyCardOfflineStore.cacheKey('m1'));
      secure.data['unrelated.key'] = 'keep me';

      final fresh = EmergencyCardOfflineStore(cache: cache, secure: secure);
      await fresh.save(testUserId, fullCard('m3'));
      expect(secure.data.keys, {
        EmergencyCardOfflineStore.secureKey('m2'),
        EmergencyCardOfflineStore.secureKey('m3'),
        'unrelated.key',
      });
    },
  );

  test('corrupt payloads are dropped instead of throwing', () async {
    await cache.write(EmergencyCardOfflineStore.cacheKey('m1'), {
      'u': testUserId,
    });
    secure.data[EmergencyCardOfflineStore.secureKey('m1')] = '{not json';
    expect(await store.load(testUserId, 'm1'), isNull);
    expect(secure.data, isEmpty);
    expect(cache.contains(EmergencyCardOfflineStore.cacheKey('m1')), isFalse);
  });

  test('a broken keystore never throws', () async {
    secure.fail = true;
    await store.save(testUserId, fullCard('m1'));
    expect(cache.contains(EmergencyCardOfflineStore.cacheKey('m1')), isFalse);
    expect(await store.load(testUserId, 'm1'), isNull);
    await store.remove('m1');
    await store.clearAll();
  });

  test('remove and clearAll delete copies and markers', () async {
    await store.save(testUserId, fullCard('m1'));
    await store.save(testUserId, fullCard('m2'));
    await store.saveMembers(testUserId, testMembers);

    await store.remove('m1');
    expect(await store.load(testUserId, 'm1'), isNull);
    expect(await store.load(testUserId, 'm2'), isNotNull);

    await store.clearAll();
    expect(secure.data, isEmpty);
    expect(cache.contains(EmergencyCardOfflineStore.cacheKey('m2')), isFalse);
    expect(store.loadMembers(testUserId), isNull);
  });

  test(
    'member directory keeps only minimal fields and is per account',
    () async {
      final withPrivate = amit.copyWith(
        email: () => 'amit@example.com',
        dateOfBirth: () => DateTime.utc(1985),
      );
      await store.saveMembers(testUserId, [withPrivate, kamla]);
      final raw =
          '${cache.readJson(EmergencyCardOfflineStore.membersCacheKey)}';
      expect(raw, isNot(contains('amit@example.com')));
      expect(raw, isNot(contains('lastLocation')));

      final members = store.loadMembers(testUserId)!;
      expect(members.map((m) => m.name), ['Amit', 'Kamla']);
      expect(members.first.designation, 'Head of Family');
      expect(members.first.isAdmin, isTrue);
      expect(store.loadMembers('someone-else'), isNull);
    },
  );

  test('with a session check, saves of another account are dropped', () async {
    String? signedIn = testUserId;
    final bound = EmergencyCardOfflineStore(
      cache: cache,
      secure: secure,
      currentUserId: () => signedIn,
    );
    await bound.save(testUserId, fullCard('m1'));
    expect(await bound.load(testUserId, 'm1'), isNotNull);

    signedIn = null; // logged out while a request was still running
    await bound.save(testUserId, fullCard('m2'));
    await bound.saveMembers(testUserId, testMembers);
    expect(
      secure.data.containsKey(EmergencyCardOfflineStore.secureKey('m2')),
      isFalse,
    );
    expect(bound.loadMembers(testUserId), isNull);

    final closed = EmergencyCardOfflineStore(
      cache: cache,
      secure: secure,
      currentUserId: () => throw StateError('container disposed'),
    );
    await closed.save(testUserId, fullCard('m3'));
    expect(
      secure.data.containsKey(EmergencyCardOfflineStore.secureKey('m3')),
      isFalse,
    );
  });

  test('writes run in order: a save queued before a wipe is wiped', () async {
    final save = store.save(testUserId, fullCard('m1'));
    final clear = store.clearAll();
    await Future.wait([save, clear]);
    expect(secure.data, isEmpty);
    expect(cache.contains(EmergencyCardOfflineStore.cacheKey('m1')), isFalse);
  });

  test('a copy "from the future" (clock set back) is dated now', () async {
    await store.save(testUserId, fullCard('m1'));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '${LocalCache.prefix}${EmergencyCardOfflineStore.cacheKey('m1')}',
      jsonEncode({
        't': '2999-01-01T00:00:00.000Z',
        'v': {'u': testUserId},
      }),
    );
    final loaded = await store.load(testUserId, 'm1');
    expect(loaded, isNotNull);
    expect(loaded!.offlineSavedAt!.isAfter(DateTime.now().toUtc()), isFalse);
  });

  test('ignores cards without a member id', () async {
    await store.save(testUserId, EmergencyCard(memberId: ' '));
    expect(secure.data, isEmpty);
  });

  test('FlutterSecureKeyValueStore talks to flutter_secure_storage', () async {
    FlutterSecureStorage.setMockInitialValues({'a': '1'});
    final s = FlutterSecureKeyValueStore();
    expect(await s.read('a'), '1');
    await s.write('b', '2');
    expect(await s.readAll(), {'a': '1', 'b': '2'});
    await s.delete('a');
    expect(await s.read('a'), isNull);
  });
}
