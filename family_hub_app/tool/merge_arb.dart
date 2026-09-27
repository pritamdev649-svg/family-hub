// Merge-only variant of `tool/l10n.dart` (kept for the command documented in
// docs/05-FLUTTER_GUIDE.md: `dart run tool/merge_arb.dart && flutter gen-l10n`).
// Prefer `dart run tool/l10n.dart`, which also runs `flutter gen-l10n` inside
// the same lock.

import 'dart:io';

import 'src/l10n_tool.dart';

Future<void> main(List<String> args) async {
  exitCode = await runL10nTool(args, generate: false);
}
