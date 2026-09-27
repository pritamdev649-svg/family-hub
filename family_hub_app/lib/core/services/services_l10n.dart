import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:family_hub/core/services/location_service.dart';
import 'package:family_hub/l10n/app_localizations.dart';

/// Localizations for code that runs without a `BuildContext` (notification
/// channels, background isolates). Picks the supported language matching
/// [locale] (default: the device locale) and falls back to English.
AppLocalizations servicesL10n([Locale? locale]) {
  final wanted = locale ?? PlatformDispatcher.instance.locale;
  const english = Locale('en');
  var pick = english;
  for (final supported in AppLocalizations.supportedLocales) {
    if (supported.languageCode == wanted.languageCode) {
      pick = supported;
      break;
    }
  }
  try {
    return lookupAppLocalizations(pick);
  } catch (_) {
    return lookupAppLocalizations(english);
  }
}

/// User-facing text for a [LocationPermissionState] (SOS + settings screens).
extension LocationPermissionStateL10n on LocationPermissionState {
  /// Explains why location is unavailable; empty for
  /// [LocationPermissionState.granted].
  String message(AppLocalizations l10n) => switch (this) {
    LocationPermissionState.granted => '',
    LocationPermissionState.denied => l10n.servicesLocationDenied,
    LocationPermissionState.deniedForever => l10n.servicesLocationDeniedForever,
    LocationPermissionState.serviceDisabled =>
      l10n.servicesLocationServiceDisabled,
  };

  /// Label of the button that fixes the problem: "Allow location" (asks
  /// again via `ensurePermission`) or "Open settings" (`openSettings`).
  String actionLabel(AppLocalizations l10n) =>
      needsSettings ? l10n.servicesOpenSettings : l10n.servicesLocationAllow;
}
