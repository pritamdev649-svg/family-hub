// Storage used by the networking layer (tokens) and the offline cache.
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:family_hub/core/storage/local_cache.dart';
import 'package:family_hub/core/storage/token_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthTokens', () {
    test('round-trips JSON and rejects incomplete payloads', () {
      const t = AuthTokens(accessToken: 'a', refreshToken: 'r', expiresIn: 900);
      expect(AuthTokens.fromJson(t.toJson()), t);
      expect(AuthTokens.tryParse({'accessToken': 'a'}), isNull);
      expect(
        AuthTokens.tryParse({'accessToken': '', 'refreshToken': 'r'}),
        isNull,
      );
      expect(AuthTokens.tryParse('nope'), isNull);
      expect(
        AuthTokens.tryParse({
          'accessToken': 'a',
          'refreshToken': 'r',
          'expiresIn': '60',
        })?.expiresIn,
        60,
      );
      expect(() => AuthTokens.fromJson(const {}), throwsFormatException);
      expect(t.toString(), isNot(contains('a,')));
    });
  });

  group('TokenStorage', () {
    test('save / read (cached + persisted) / clear', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final storage = TokenStorage();
      expect(await storage.read(), isNull);
      await storage.save(const AuthTokens(accessToken: 'a', refreshToken: 'r'));
      expect(storage.cached?.accessToken, 'a');
      expect(await storage.accessToken, 'a');
      expect(await TokenStorage().refreshToken, 'r', reason: 'persisted');
      await storage.clear();
      expect(await storage.hasTokens, isFalse);
      expect(await TokenStorage().read(), isNull);
    });

    test('corrupt payload is treated as signed out', () async {
      FlutterSecureStorage.setMockInitialValues({
        TokenStorage.storageKey: '{not json',
      });
      expect(await TokenStorage().read(), isNull);
    });

    test('concurrent first reads share one load', () async {
      FlutterSecureStorage.setMockInitialValues({
        TokenStorage.storageKey: '{"accessToken":"a","refreshToken":"r"}',
      });
      final storage = TokenStorage();
      final results = await Future.wait([storage.read(), storage.read()]);
      expect(results.map((t) => t?.accessToken), ['a', 'a']);
    });
  });

  group('LocalCache', () {
    late LocalCache cache;
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({'settings.keep': 'me'});
      prefs = await SharedPreferences.getInstance();
      cache = LocalCache(prefs);
    });

    test('write / read / readMap / savedAt / remove', () async {
      expect(await cache.write('session', {'a': 1}), isTrue);
      expect(cache.readMap('session'), {'a': 1});
      expect(cache.read('session', (j) => (j! as Map)['a']), 1);
      expect(cache.savedAt('session'), isNotNull);
      expect(cache.contains('session'), isTrue);
      await cache.remove('session');
      expect(cache.readJson('session'), isNull);
    });

    test('maxAge expires entries', () async {
      await prefs.setString(
        '${LocalCache.prefix}old',
        '{"t":"2000-01-01T00:00:00.000Z","v":1}',
      );
      expect(cache.readJson('old'), 1);
      expect(cache.readJson('old', maxAge: const Duration(days: 1)), isNull);
    });

    test('decode failures and corrupt entries are dropped', () async {
      await cache.write('x', {'a': 1});
      expect(
        cache.read<int>('x', (j) => throw const FormatException()),
        isNull,
      );
      await pumpEventQueue();
      expect(cache.contains('x'), isFalse);

      await prefs.setString('${LocalCache.prefix}bad', 'garbage');
      expect(cache.readJson('bad'), isNull);
    });

    test('non-encodable values are rejected', () async {
      expect(await cache.write('d', DateTime.now()), isFalse);
    });

    test('clear only removes cache entries', () async {
      await cache.write('a', 1);
      await cache.write('b', 2);
      await cache.clear();
      expect(cache.contains('a') || cache.contains('b'), isFalse);
      expect(prefs.getString('settings.keep'), 'me');
    });
  });
}
