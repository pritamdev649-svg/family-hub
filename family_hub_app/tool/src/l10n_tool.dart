// Merges the per-feature English ARB fragments (`l10n_parts/*.arb`) into the
// template `lib/l10n/app_en.arb` and runs `flutter gen-l10n`, all under an
// atomic directory lock so many agents / terminals can run it concurrently.
//
// Used by `tool/l10n.dart` (merge + generate) and `tool/merge_arb.dart`
// (merge only). The pure merge logic ([mergeArbFragments]) is unit-tested in
// `tool/test/l10n_tool_test.dart`.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Name of the lock directory created next to `pubspec.yaml`.
const lockDirName = '.l10n.lock';

/// How long to wait for another run to release the lock.
const defaultLockTimeout = Duration(seconds: 120);

/// A lock older than this is considered abandoned (crashed run) and broken.
const defaultStaleAfter = Duration(seconds: 180);

const _pollInterval = Duration(milliseconds: 400);
const _ownerFileName = 'owner.json';
const _fragmentsDir = 'l10n_parts';
const _templatePath = 'lib/l10n/app_en.arb';

/// Message keys must be valid Dart identifiers (they become getters).
final _keyPattern = RegExp(r'^[a-z][a-zA-Z0-9_]*$');

// -----------------------------------------------------------------------------
// Merge (pure)
// -----------------------------------------------------------------------------

/// One `l10n_parts/<name>.arb` file.
class ArbSource {
  const ArbSource(this.name, this.content);

  /// File name used in messages, e.g. `tasks.arb`.
  final String name;
  final String content;
}

class ArbMergeResult {
  ArbMergeResult({
    required this.merged,
    required this.keyOrigin,
    required this.keysPerSource,
    required this.errors,
    required this.warnings,
  });

  /// The merged template, `@@locale` first, then every fragment in order.
  final Map<String, Object?> merged;

  /// message key -> fragment file name.
  final Map<String, String> keyOrigin;

  /// fragment file name -> number of message keys.
  final Map<String, int> keysPerSource;
  final List<String> errors;
  final List<String> warnings;

  bool get ok => errors.isEmpty;
  int get messageCount => keyOrigin.length;
}

/// Merges [sources] (already sorted by the caller) into one English template.
///
/// Errors (the merge must fail): invalid JSON, non-object root, duplicate
/// keys (inside one file or across files), invalid key names, non-string
/// messages, non-object metadata. Warnings: metadata without a message,
/// a fragment declaring a `@@locale` other than `en`.
ArbMergeResult mergeArbFragments(
  List<ArbSource> sources, {
  String locale = 'en',
  String dirLabel = _fragmentsDir,
}) {
  final merged = <String, Object?>{'@@locale': locale};
  final origin = <String, String>{};
  final perSource = <String, int>{};
  final errors = <String>[];
  final warnings = <String>[];

  for (final source in sources) {
    final label = '$dirLabel/${source.name}';
    perSource[source.name] = 0;

    final Object? decoded;
    try {
      decoded = jsonDecode(source.content);
    } on FormatException catch (e) {
      errors.add('$label: invalid JSON - ${e.message}'
          '${e.offset != null ? ' (at offset ${e.offset})' : ''}');
      continue;
    }
    if (decoded is! Map<String, dynamic>) {
      errors.add('$label: the root must be a JSON object');
      continue;
    }

    // jsonDecode silently keeps the last of duplicated keys - detect them.
    for (final dup in findDuplicateTopLevelKeys(source.content)) {
      errors.add('$label: key "$dup" is defined more than once in this file');
    }

    for (final entry in decoded.entries) {
      final key = entry.key;
      final value = entry.value;

      if (key.startsWith('@@')) {
        if (key == '@@locale' && value != locale) {
          warnings.add('$label: ignoring "@@locale": "$value" '
              '(fragments are always "$locale")');
        }
        continue;
      }

      if (key.startsWith('@')) {
        final target = key.substring(1);
        if (value is! Map) {
          errors.add('$label: metadata "$key" must be a JSON object');
        } else if (!decoded.containsKey(target)) {
          warnings.add('$label: metadata "$key" has no message "$target" '
              'in this file - dropped');
        }
        continue; // metadata is copied right after its message below
      }

      if (!_keyPattern.hasMatch(key)) {
        errors.add('$label: invalid key "$key" (use lowerCamelCase: '
            'letters, digits, "_"; must start with a lowercase letter)');
        continue;
      }
      if (value is! String) {
        errors.add('$label: message "$key" must be a string');
        continue;
      }
      final previous = origin[key];
      if (previous != null) {
        errors.add('duplicate key "$key": defined in $dirLabel/$previous '
            'AND in $label');
        continue;
      }

      origin[key] = source.name;
      perSource[source.name] = perSource[source.name]! + 1;
      merged[key] = value;
      final meta = decoded['@$key'];
      if (meta is Map) merged['@$key'] = meta;
    }
  }

  return ArbMergeResult(
    merged: merged,
    keyOrigin: origin,
    keysPerSource: perSource,
    errors: errors,
    warnings: warnings,
  );
}

/// Returns keys that appear more than once directly inside the root object
/// of the JSON document [json]. Assumes [json] is valid JSON.
List<String> findDuplicateTopLevelKeys(String json) {
  final seen = <String>{};
  final dups = <String>{};
  var depth = 0;
  var i = 0;
  while (i < json.length) {
    final c = json[i];
    if (c == '"') {
      final start = i + 1;
      final buffer = StringBuffer();
      i++;
      while (i < json.length && json[i] != '"') {
        if (json[i] == r'\' && i + 1 < json.length) {
          buffer.write(json.substring(i, i + 2));
          i += 2;
          continue;
        }
        buffer.write(json[i]);
        i++;
      }
      i++; // closing quote
      if (depth == 1) {
        var j = i;
        while (j < json.length && ' \t\r\n'.contains(json[j])) {
          j++;
        }
        if (j < json.length && json[j] == ':') {
          String key;
          try {
            key = jsonDecode('"$buffer"') as String;
          } on FormatException {
            key = json.substring(start, i - 1);
          }
          if (!seen.add(key)) dups.add(key);
        }
      }
      continue;
    }
    if (c == '{' || c == '[') depth++;
    if (c == '}' || c == ']') depth--;
    i++;
  }
  return dups.toList();
}

/// Pretty-prints the merged template exactly as it is written to disk.
String encodeArb(Map<String, Object?> arb) =>
    '${const JsonEncoder.withIndent('  ').convert(arb)}\n';

// -----------------------------------------------------------------------------
// Lock
// -----------------------------------------------------------------------------

class LockTimeoutException implements Exception {
  LockTimeoutException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// An atomic, cross-process lock backed by a directory (`mkdir` is atomic on
/// every OS). Locks older than [staleAfter] are broken so a crashed run cannot
/// block everybody forever.
class DirectoryLock {
  DirectoryLock(
    this.path, {
    this.timeout = defaultLockTimeout,
    this.staleAfter = defaultStaleAfter,
    void Function(String message)? log,
  }) : _log = log ?? ((_) {});

  final String path;
  final Duration timeout;
  final Duration staleAfter;
  final void Function(String message) _log;

  final String _token =
      '$pid-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}';
  bool _held = false;

  bool get isHeld => _held;

  /// Acquires the lock, waiting up to [timeout]. Returns the time waited.
  Future<Duration> acquire() async {
    final watch = Stopwatch()..start();
    var announced = false;
    while (true) {
      if (_tryCreate()) {
        _held = true;
        return watch.elapsed;
      }
      final owner = _readOwner(path);
      final age = _ageOf(path, owner);
      if (age != null && age > staleAfter) {
        _log('l10n: breaking stale lock (${age.inSeconds}s old, '
            'owner pid ${owner?['pid'] ?? '?'})');
        _breakStale(owner?['token'] as String?);
        continue;
      }
      if (watch.elapsed > timeout) {
        throw LockTimeoutException(
          'Timed out after ${timeout.inSeconds}s waiting for $path '
          '(held by pid ${owner?['pid'] ?? '?'} since '
          '${owner?['startedAt'] ?? 'unknown'}). If no other l10n run is '
          'active, delete that directory and retry.',
        );
      }
      if (!announced) {
        _log('l10n: another run holds the lock (pid ${owner?['pid'] ?? '?'}), '
            'waiting...');
        announced = true;
      }
      await Future<void>.delayed(_pollInterval);
    }
  }

  /// Releases the lock if (and only if) this instance still owns it.
  ///
  /// The directory is first renamed aside (atomic) and only then deleted, so
  /// a concurrent run can never claim a half-deleted lock.
  void release() {
    if (!_held) return;
    _held = false;
    final owner = _readOwner(path);
    if (owner?['token'] != _token) {
      _log('l10n: lock is no longer ours (taken over as stale?); '
          'leaving it in place');
      return;
    }
    final aside = '$path.released-$pid-${DateTime.now().microsecondsSinceEpoch}';
    try {
      Directory(path).renameSync(aside);
    } on FileSystemException {
      return; // Already gone.
    }
    try {
      Directory(aside).deleteSync(recursive: true);
    } on FileSystemException {
      // Best effort - an orphaned `*.released-*` directory is harmless.
    }
  }

  /// Claims the lock. The directory itself may already exist (an empty
  /// leftover or a concurrent creator - `Directory.createSync` does not fail
  /// on existing directories); the atomic claim is the **exclusive** creation
  /// of the owner file inside it (`O_EXCL`).
  bool _tryCreate() {
    final file = File('$path${Platform.pathSeparator}$_ownerFileName');
    try {
      Directory(path).createSync();
      file.createSync(exclusive: true);
    } on FileSystemException {
      return false;
    }
    try {
      file.writeAsStringSync(
        jsonEncode({
          'pid': pid,
          'host': Platform.localHostname,
          'startedAt': DateTime.now().toUtc().toIso8601String(),
          'token': _token,
        }),
        flush: true,
      );
      return true;
    } on FileSystemException {
      // Could not record ownership (disk full?) - give the claim back.
      try {
        file.deleteSync();
      } on FileSystemException {
        // Becomes stale and is broken after [staleAfter].
      }
      return false;
    }
  }

  void _breakStale(String? staleToken) {
    final aside = '$path.stale-$pid-${DateTime.now().microsecondsSinceEpoch}';
    try {
      Directory(path).renameSync(aside);
    } on FileSystemException {
      return; // someone else broke or released it first
    }
    final movedOwner = _readOwner(aside);
    if (staleToken != null && movedOwner?['token'] != staleToken) {
      // We raced with a run that had just re-created a fresh lock: put it back.
      try {
        Directory(aside).renameSync(path);
        return;
      } on FileSystemException {
        _log('l10n: warning - could not restore a fresh lock after a race');
      }
    }
    try {
      Directory(aside).deleteSync(recursive: true);
    } on FileSystemException {
      // Best effort.
    }
  }

  static Map<String, Object?>? _readOwner(String dirPath) {
    try {
      final file = File('$dirPath${Platform.pathSeparator}$_ownerFileName');
      if (!file.existsSync()) return null;
      final decoded = jsonDecode(file.readAsStringSync());
      return decoded is Map<String, Object?> ? decoded : null;
    } on Object {
      return null;
    }
  }

  static Duration? _ageOf(String dirPath, Map<String, Object?>? owner) {
    final started = DateTime.tryParse('${owner?['startedAt'] ?? ''}');
    if (started != null) return DateTime.now().toUtc().difference(started);
    try {
      final stat = Directory(dirPath).statSync();
      if (stat.type == FileSystemEntityType.notFound) return null;
      return DateTime.now().difference(stat.modified);
    } on FileSystemException {
      return null;
    }
  }
}

// -----------------------------------------------------------------------------
// CLI
// -----------------------------------------------------------------------------

/// Entry point shared by `tool/l10n.dart` and `tool/merge_arb.dart`.
/// Returns the process exit code.
Future<int> runL10nTool(List<String> args, {required bool generate}) async {
  if (args.contains('-h') || args.contains('--help')) {
    stdout.writeln(_usage(generate));
    return 0;
  }
  final runGen = generate && !args.contains('--no-gen');
  final root = _findAppRoot();
  if (root == null) {
    stderr.writeln('l10n: could not find the Flutter app root (a directory '
        'with pubspec.yaml and $_fragmentsDir/). Run this from family_hub_app/.');
    return 2;
  }

  final sep = Platform.pathSeparator;
  final lock = DirectoryLock('${root.path}$sep$lockDirName', log: stdout.writeln);
  final subscriptions = <StreamSubscription<ProcessSignal>>[];
  void onSignal(ProcessSignal signal) {
    lock.release();
    stderr.writeln('l10n: interrupted ($signal) - lock released');
    exit(130);
  }

  for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
    try {
      subscriptions.add(signal.watch().listen(onSignal));
    } on Object {
      // SIGTERM cannot be watched on Windows.
    }
  }

  final total = Stopwatch()..start();
  try {
    final waited = await lock.acquire();
    if (waited > const Duration(seconds: 1)) {
      stdout.writeln('l10n: lock acquired after ${_secs(waited)}');
    }

    final merge = _mergeOnDisk(root);
    if (merge == null) return 1;

    if (!runGen) {
      stdout.writeln('l10n: done in ${_secs(total.elapsed)} '
          '(skipped flutter gen-l10n)');
      return 0;
    }
    final code = await _runGenL10n(root, merge.keyOrigin);
    if (code != 0) return code;
    stdout.writeln('l10n: done in ${_secs(total.elapsed)}');
    return 0;
  } on LockTimeoutException catch (e) {
    stderr.writeln('l10n: ERROR - $e');
    return 3;
  } finally {
    lock.release();
    for (final s in subscriptions) {
      await s.cancel();
    }
  }
}

ArbMergeResult? _mergeOnDisk(Directory root) {
  final sep = Platform.pathSeparator;
  final partsDir = Directory('${root.path}$sep$_fragmentsDir');
  final files = partsDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.toLowerCase().endsWith('.arb'))
      .toList()
    ..sort((a, b) => _baseName(a.path).compareTo(_baseName(b.path)));

  if (files.isEmpty) {
    stderr.writeln('l10n: ERROR - no fragments found in $_fragmentsDir/');
    return null;
  }

  final sources = <ArbSource>[];
  for (final file in files) {
    try {
      sources.add(ArbSource(_baseName(file.path), file.readAsStringSync()));
    } on FileSystemException catch (e) {
      stderr.writeln('l10n: ERROR - cannot read ${file.path}: ${e.message}');
      return null;
    }
  }

  final result = mergeArbFragments(sources);
  for (final w in result.warnings) {
    stdout.writeln('l10n: warning - $w');
  }
  if (!result.ok) {
    stderr.writeln('');
    stderr.writeln('l10n: MERGE FAILED - ${result.errors.length} problem(s):');
    for (final e in result.errors) {
      stderr.writeln('  x $e');
    }
    stderr.writeln('');
    stderr.writeln('l10n: $_templatePath was NOT changed. Fix the fragment(s) '
        'above and run again.');
    return null;
  }

  final template = File('${root.path}$sep${_templatePath.replaceAll('/', sep)}');
  final encoded = encodeArb(result.merged);
  final previous = template.existsSync() ? template.readAsStringSync() : null;
  final changed = previous != encoded;
  if (changed) {
    template.parent.createSync(recursive: true);
    final tmp = File('${template.path}.tmp-$pid');
    tmp.writeAsStringSync(encoded, flush: true);
    tmp.renameSync(template.path);
  }

  final width = result.keysPerSource.keys.fold<int>(0, (w, k) => max(w, k.length));
  stdout.writeln('l10n: merged ${sources.length} fragment(s) from '
      '$_fragmentsDir/ -> $_templatePath');
  for (final e in result.keysPerSource.entries) {
    stdout.writeln('  ${e.key.padRight(width)}  ${e.value.toString().padLeft(4)} keys');
  }
  stdout.writeln('  ${'total'.padRight(width)}  '
      '${result.messageCount.toString().padLeft(4)} keys '
      '(${changed ? 'template updated' : 'template unchanged'})');
  return result;
}

Future<int> _runGenL10n(Directory root, Map<String, String> keyOrigin) async {
  final flutter = Platform.environment['FLUTTER_BIN'] ?? 'flutter';
  stdout.writeln('l10n: running "$flutter gen-l10n"...');
  final watch = Stopwatch()..start();
  final Process process;
  try {
    process = await Process.start(
      flutter,
      const ['gen-l10n'],
      workingDirectory: root.path,
      runInShell: Platform.isWindows,
    );
  } on ProcessException catch (e) {
    stderr.writeln('l10n: ERROR - could not start "$flutter": ${e.message}. '
        'Is Flutter on PATH? (or set FLUTTER_BIN)');
    return 4;
  }

  final output = StringBuffer();
  final done = Future.wait([
    process.stdout.transform(utf8.decoder).forEach((s) {
      output.write(s);
      stdout.write(s);
    }),
    process.stderr.transform(utf8.decoder).forEach((s) {
      output.write(s);
      stderr.write(s);
    }),
  ]);
  final code = await process.exitCode;
  await done;

  if (code == 0) {
    stdout.writeln('l10n: flutter gen-l10n OK (${_secs(watch.elapsed)})');
    return 0;
  }

  stderr.writeln('l10n: flutter gen-l10n FAILED (exit $code).');
  final text = output.toString();
  final hints = keyOrigin.entries
      .where((e) => RegExp('\\b${RegExp.escape(e.key)}\\b').hasMatch(text))
      .take(20)
      .toList();
  if (hints.isNotEmpty) {
    stderr.writeln('l10n: keys mentioned above come from:');
    for (final h in hints) {
      stderr.writeln('  ${h.key}  ->  $_fragmentsDir/${h.value}');
    }
  }
  return code;
}

Directory? _findAppRoot() {
  bool isRoot(Directory d) {
    final sep = Platform.pathSeparator;
    return File('${d.path}${sep}pubspec.yaml').existsSync() &&
        Directory('${d.path}$sep$_fragmentsDir').existsSync();
  }

  final candidates = <Directory>[Directory.current];
  try {
    final script = File.fromUri(Platform.script);
    candidates.add(script.parent.parent); // <root>/tool/l10n.dart
  } on Object {
    // Platform.script may not be a file (snapshots).
  }
  for (final start in candidates) {
    Directory dir = start.absolute;
    for (var i = 0; i < 6; i++) {
      if (isRoot(dir)) return dir;
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
  }
  // Also accept being run from the repository root.
  final nested = Directory(
      '${Directory.current.path}${Platform.pathSeparator}family_hub_app');
  return nested.existsSync() && isRoot(nested) ? nested : null;
}

String _baseName(String path) => path.split(RegExp(r'[\\/]')).last;

String _secs(Duration d) => '${(d.inMilliseconds / 1000).toStringAsFixed(1)}s';

String _usage(bool generate) => '''
Usage: dart run tool/${generate ? 'l10n' : 'merge_arb'}.dart [--no-gen]

Merges every $_fragmentsDir/*.arb (sorted by file name) into $_templatePath
("@@locale": "en")${generate ? ' and runs "flutter gen-l10n"' : ''}.
Fails on duplicate keys and prints both files. Safe to run concurrently: an
atomic lock directory ($lockDirName) serialises runs (wait <= ${defaultLockTimeout.inSeconds}s,
locks older than ${defaultStaleAfter.inSeconds}s are treated as stale).

Options:
  --no-gen   only merge, do not run flutter gen-l10n
  -h, --help show this help
Environment:
  FLUTTER_BIN  flutter executable to use (default: flutter)''';
