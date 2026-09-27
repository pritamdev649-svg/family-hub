// Merges l10n_parts/*.arb -> lib/l10n/app_en.arb and runs `flutter gen-l10n`.
//
//   cd family_hub_app && dart run tool/l10n.dart          # merge + generate
//   cd family_hub_app && dart run tool/l10n.dart --no-gen # merge only
//
// Safe to run concurrently (atomic lock directory `.l10n.lock`).

import 'dart:io';

import 'src/l10n_tool.dart';

Future<void> main(List<String> args) async {
  exitCode = await runL10nTool(args, generate: true);
}
