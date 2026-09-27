import 'package:family_hub/core/config/app_languages.dart';
import 'package:flutter/widgets.dart';

/// Maps a stored / user-supplied code (`hi`, `pt-BR`, `es_419`, `HI`) to a
/// supported language code (see [AppLanguages]), or `null` if it is empty,
/// `system` or unsupported.
String? normalizeLocaleCode(String? code) {
  final raw = code?.trim();
  if (raw == null || raw.isEmpty) return null;
  final language = raw.split(RegExp('[-_]')).first.toLowerCase();
  return AppLanguages.byCode(language)?.code;
}

/// The locale the app should use:
/// 1. the language chosen in settings, if supported;
/// 2. otherwise the first device-preferred language the app supports
///    (the device's primary language first, then its fallbacks);
/// 3. otherwise English.
///
/// Returns a language-only [Locale]; formatting adds the family's country
/// (see `Fmt`).
Locale resolveAppLocale({
  required String? chosenCode,
  required List<Locale> deviceLocales,
}) {
  final chosen = normalizeLocaleCode(chosenCode);
  if (chosen != null) return Locale(chosen);
  for (final locale in deviceLocales) {
    final code = normalizeLocaleCode(locale.languageCode);
    if (code != null) return Locale(code);
  }
  return const Locale('en');
}
