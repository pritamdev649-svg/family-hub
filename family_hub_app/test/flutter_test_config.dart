import 'dart:async';

import 'package:family_hub/core/design/app_typography.dart';
import 'package:google_fonts/google_fonts.dart';

/// Runs before every test file: widget tests use the platform font so they
/// never try to download the brand font over the network.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  AppTypography.useBrandFont = false;
  GoogleFonts.config.allowRuntimeFetching = false;
  await testMain();
}
