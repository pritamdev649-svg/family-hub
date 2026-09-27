import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/error_messages.dart';
import 'package:family_hub/core/network/api_exception.dart';
import 'package:family_hub/l10n/app_localizations.dart';

/// Icons used only by the auth screens (generic ones come from [AppIcons]).
abstract final class AuthIcons {
  static const IconData country = AppIcons.country;
  static const IconData currency = AppIcons.currency;
  static const IconData timezone = AppIcons.time;
  static const IconData otp = AppIcons.otp;
  static const IconData name = AppIcons.memberOutlined;
  static const IconData login = AppIcons.login;
  static const IconData verifyEmail = AppIcons.verifyEmail;
  static const IconData resetPassword = AppIcons.resetPassword;
  static const IconData demo = AppIcons.demo;
  static const IconData createFamily = AppIcons.createFamily;
  static const IconData joinFamily = AppIcons.joinFamily;
  static const IconData inviteCode = AppIcons.inviteCode;
}

/// Colours of the auth screens: the brand accent everywhere, plus one
/// accent per sign-up mode so "create" (indigo) and "join" (teal) are
/// recognisable on the welcome screen, the mode tiles and the form
/// sections (docs/12-DESIGN_LANGUAGE.md).
abstract final class AuthAccents {
  static const AppAccent brand = AppAccents.brand;
  static const AppAccent create = AppAccent.indigo;
  static const AppAccent join = AppAccent.teal;
  static const AppAccent aboutYou = AppAccent.violet;
  static const AppAccent demo = AppAccent.teal;
  static const AppAccent error = AppAccents.sos;
}

/// Opacities of the white "glass" elements drawn on gradients and solid
/// colour tiles (same recipe as the dashboard header's glass stats).
abstract final class AuthGlass {
  /// Frosted fill of pills and icon squares.
  static const double fill = 0.18;

  /// Large faint watermark icon on a tile.
  static const double watermark = 0.12;

  /// Secondary white text (taglines, subtitles).
  static const double secondaryText = 0.85;
}

/// Waits up to this long are shown in seconds, longer ones in minutes.
const _showSecondsUpTo = 90;

/// A remaining wait as text: "42 seconds", "15 minutes" (minutes rounded
/// up, so the text never promises less than the real wait).
String formatWait(AppLocalizations l10n, int seconds) {
  if (seconds <= _showSecondsUpTo) {
    return l10n.authCooldownSeconds(seconds < 1 ? 1 : seconds);
  }
  return l10n.authCooldownMinutes((seconds / Duration.secondsPerMinute).ceil());
}

/// Auth-specific text for [error] where the generic `localizedErrorMessage`
/// is worse, else `null`:
///
/// * `429` with `retryAfterSeconds` → "Too many attempts. Try again in
///   14 minutes." (the generic text counts seconds only);
/// * `GUARDIAN_CONSENT_REQUIRED` with `details.consentAge` → the sign-up
///   age gate text (the generic one is about adding somebody else).
String? authErrorText(Object error, AppLocalizations l10n) {
  final e = unwrapProviderError(error);
  if (e is! ApiException) return null;
  switch (e.code) {
    case ApiErrorCode.tooManyRequests:
      final seconds = e.retryAfterSeconds;
      return seconds != null && seconds > 0
          ? l10n.authTooManyAttemptsWait(formatWait(l10n, seconds))
          : null;
    case ApiErrorCode.guardianConsentRequired:
      final age = e.details?['consentAge'];
      return age is num ? l10n.authSignupTooYoung(age.toInt()) : null;
  }
  return null;
}
