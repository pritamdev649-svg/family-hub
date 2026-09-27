/// `Fmt` (locale-aware money / number / date formatting) and [fmtProvider].
/// Import this file from widgets; import `fmt.dart` directly only where no
/// Riverpod scope is available (tests, background isolates).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/settings/settings_controller.dart';
import 'package:family_hub/core/utils/fmt.dart';
import 'package:family_hub/shared/session/session_controller.dart';

export 'package:family_hub/core/utils/fmt.dart';

/// App-wide [Fmt] for the current language + family currency/country.
/// Falls back to the country's default currency when no family is loaded.
final fmtProvider = Provider<Fmt>((ref) {
  final locale = ref.watch(resolvedLocaleProvider);
  final family = ref.watch(currentFamilyProvider);
  final country = ref.watch(currentCountryProvider);
  final familyCurrency = family?.currency.trim() ?? '';
  return Fmt(
    locale: locale,
    currency: familyCurrency.isNotEmpty ? familyCurrency : country.currency,
    country: country.code,
  );
});
