// Run: cd family_hub_app && flutter test tool/test
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../src/l10n_tool.dart';

void main() {
  group('mergeArbFragments', () {
    test('merges fragments in order, @@locale first, metadata after its key', () {
      final result = mergeArbFragments(const [
        ArbSource('common.arb', '{"commonOk": "OK", "@commonOk": {"description": "d"}}'),
        ArbSource('tasks.arb', '{"@@locale": "en", "tasksTitle": "Tasks"}'),
      ]);
      expect(result.ok, isTrue, reason: result.errors.join('\n'));
      expect(result.merged.keys.toList(), ['@@locale', 'commonOk', '@commonOk', 'tasksTitle']);
      expect(result.merged['@@locale'], 'en');
      expect(result.keyOrigin, {'commonOk': 'common.arb', 'tasksTitle': 'tasks.arb'});
      expect(result.keysPerSource, {'common.arb': 1, 'tasks.arb': 1});
      expect(result.messageCount, 2);
    });

    test('duplicate keys across files fail and name both files', () {
      final result = mergeArbFragments(const [
        ArbSource('a.arb', '{"commonOk": "OK"}'),
        ArbSource('b.arb', '{"commonOk": "Okay"}'),
      ]);
      expect(result.ok, isFalse);
      expect(result.errors.single, contains('l10n_parts/a.arb'));
      expect(result.errors.single, contains('l10n_parts/b.arb'));
      expect(result.errors.single, contains('"commonOk"'));
    });

    test('duplicate keys inside one file fail', () {
      final result = mergeArbFragments(const [
        ArbSource('a.arb', '{"x": "1", "@x": {}, "x": "2"}'),
      ]);
      expect(result.ok, isFalse);
      expect(result.errors.single, contains('more than once'));
    });

    test('invalid JSON, non-object roots, bad keys and non-string values fail', () {
      final result = mergeArbFragments(const [
        ArbSource('broken.arb', '{"a": "1",}'),
        ArbSource('list.arb', '["a"]'),
        ArbSource('keys.arb', '{"Bad-Key": "x", "2fa": "y", "ok_key": "z"}'),
        ArbSource('values.arb', '{"count": 3, "@meta": "nope", "meta": "m"}'),
      ]);
      expect(result.errors.where((e) => e.contains('broken.arb')), hasLength(1));
      expect(result.errors.where((e) => e.contains('list.arb')), hasLength(1));
      expect(result.errors.where((e) => e.contains('invalid key')), hasLength(2));
      expect(result.errors.where((e) => e.contains('"count" must be a string')), hasLength(1));
      expect(result.errors.where((e) => e.contains('"@meta" must be a JSON object')), hasLength(1));
      expect(result.keyOrigin.keys, containsAll(<String>['ok_key', 'meta']));
    });

    test('orphan metadata and a foreign @@locale are warnings only', () {
      final result = mergeArbFragments(const [
        ArbSource('a.arb', '{"@@locale": "hi", "@ghost": {}, "real": "r"}'),
      ]);
      expect(result.ok, isTrue);
      expect(result.warnings, hasLength(2));
      expect(result.merged.containsKey('@ghost'), isFalse);
    });

    test('encodeArb is stable, pretty and newline-terminated', () {
      final result = mergeArbFragments(const [ArbSource('a.arb', '{"k": "é {n}"}')]);
      final encoded = encodeArb(result.merged);
      expect(encoded, endsWith('}\n'));
      expect(jsonDecode(encoded), result.merged);
      expect(encodeArb(result.merged), encoded);
    });
  });

  group('findDuplicateTopLevelKeys', () {
    test('ignores nested keys and strings that look like keys', () {
      const json = '{"a": {"a": 1, "placeholders": {"count": {}}}, '
          '"b": "\\"a\\": fake", "@a": {"a": 2}, "c": ["a", "a"]}';
      expect(findDuplicateTopLevelKeys(json), isEmpty);
    });

    test('finds repeated root keys, including escaped ones', () {
      const json = '{"a": 1, "b\\u0041": 2, "a": 3, "bA": 4}';
      expect(findDuplicateTopLevelKeys(json), unorderedEquals(['a', 'bA']));
    });
  });

  group('DirectoryLock', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('l10n_lock_test'));
    tearDown(() => tmp.deleteSync(recursive: true));

    String lockPath() => '${tmp.path}${Platform.pathSeparator}$lockDirName';

    test('acquire and release create and remove the lock directory', () async {
      final lock = DirectoryLock(lockPath());
      await lock.acquire();
      expect(lock.isHeld, isTrue);
      expect(Directory(lockPath()).existsSync(), isTrue);
      lock.release();
      expect(lock.isHeld, isFalse);
      expect(Directory(lockPath()).existsSync(), isFalse);
    });

    test('a second holder waits and times out while the lock is fresh', () async {
      final first = DirectoryLock(lockPath());
      await first.acquire();
      final second = DirectoryLock(lockPath(), timeout: const Duration(milliseconds: 600));
      await expectLater(second.acquire(), throwsA(isA<LockTimeoutException>()));
      first.release();
      await second.acquire();
      expect(second.isHeld, isTrue);
      second.release();
    });

    test('a waiting run gets the lock as soon as it is released', () async {
      final first = DirectoryLock(lockPath());
      await first.acquire();
      final second = DirectoryLock(lockPath(), timeout: const Duration(seconds: 5));
      final pending = second.acquire();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      first.release();
      await pending;
      expect(second.isHeld, isTrue);
      second.release();
    });

    test('a stale lock is broken', () async {
      Directory(lockPath()).createSync();
      File('${lockPath()}${Platform.pathSeparator}owner.json').writeAsStringSync(
        jsonEncode({'pid': 1, 'startedAt': '2020-01-01T00:00:00.000Z', 'token': 'old'}),
      );
      final messages = <String>[];
      final lock = DirectoryLock(lockPath(), log: messages.add);
      await lock.acquire();
      expect(lock.isHeld, isTrue);
      expect(messages.join('\n'), contains('stale'));
      lock.release();
    });

    test('an empty leftover lock directory does not block', () async {
      Directory(lockPath()).createSync();
      final lock = DirectoryLock(lockPath(), timeout: const Duration(seconds: 1));
      await lock.acquire();
      expect(lock.isHeld, isTrue);
      lock.release();
    });

    test('release never deletes a lock that was taken over', () async {
      final lock = DirectoryLock(lockPath());
      await lock.acquire();
      File('${lockPath()}${Platform.pathSeparator}owner.json')
          .writeAsStringSync(jsonEncode({'pid': 2, 'token': 'someone-else'}));
      lock.release();
      expect(Directory(lockPath()).existsSync(), isTrue);
    });
  });
}
