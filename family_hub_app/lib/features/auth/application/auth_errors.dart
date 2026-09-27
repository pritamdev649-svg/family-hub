import 'package:family_hub/core/l10n/error_messages.dart';
import 'package:family_hub/core/network/api_exception.dart';
import 'package:family_hub/l10n/app_localizations.dart';

/// Ids of the fields in the auth forms. They equal the field paths the API
/// uses in `VALIDATION_ERROR` details for `POST /auth/*` (contract §1), so
/// server errors can be shown under the right field.
abstract final class AuthField {
  static const name = 'name';
  static const email = 'email';
  static const password = 'password';
  static const dateOfBirth = 'dateOfBirth';
  static const inviteCode = 'inviteCode';
  static const otp = 'otp';
  static const newPassword = 'newPassword';
  static const familyName = 'family.name';
  static const familyCountry = 'family.country';
  static const familyCurrency = 'family.currency';
  static const familyTimezone = 'family.timezone';

  /// The family form's fields (register in create mode, family setup).
  static const familyFields = {
    familyName,
    familyCountry,
    familyCurrency,
    familyTimezone,
  };

  /// `POST /family` reports its fields without the `family.` prefix; pass
  /// this to [authFieldErrors] so they land on the same form fields.
  static const createFamilyAliases = {
    'name': familyName,
    'country': familyCountry,
    'currency': familyCurrency,
    'timezone': familyTimezone,
  };
}

/// The error code of [error] (unwrapping Riverpod wrappers), or null when it
/// is not an [ApiException].
String? authErrorCode(Object error) {
  final e = unwrapProviderError(error);
  return e is ApiException ? e.code : null;
}

/// Inline, localized field errors for [error]: field id ([AuthField]) →
/// message. Empty when the error is not about a particular field — show it
/// with `context.showError` instead.
///
/// * `EMAIL_TAKEN` → email, `INVALID_INVITE_CODE` → invite code,
///   `INVALID_OTP` / `OTP_EXPIRED` → code field, `GUARDIAN_CONSENT_REQUIRED`
///   → date of birth (app texts, localized);
/// * `VALIDATION_ERROR` → one entry per field of the server's `details`,
///   keys renamed through [aliases]. The server writes those details in
///   English (only its top-level `message` follows `Accept-Language`), so
///   they are shown as they are only in English; other languages get the
///   localized `authFieldRejected` under the field. The forms check the
///   server's rules themselves first, so this is rare.
Map<String, String> authFieldErrors(
  Object error,
  AppLocalizations l10n, {
  Map<String, String> aliases = const {},
}) {
  final e = unwrapProviderError(error);
  if (e is! ApiException) return const {};
  final serverTextReadable =
      l10n.localeName.split(RegExp('[_-]')).first == 'en';
  return switch (e.code) {
    ApiErrorCode.emailTaken => {AuthField.email: l10n.errorEmailTaken},
    ApiErrorCode.invalidInviteCode => {
      AuthField.inviteCode: l10n.errorInvalidInviteCode,
    },
    ApiErrorCode.invalidOtp => {AuthField.otp: l10n.errorInvalidOtp},
    ApiErrorCode.otpExpired => {AuthField.otp: l10n.errorOtpExpired},
    // Sign-up below the country's consent age (`details.consentAge`).
    ApiErrorCode.guardianConsentRequired => {
      AuthField.dateOfBirth: switch (e.details?['consentAge']) {
        final num age => l10n.authSignupTooYoung(age.toInt()),
        _ => l10n.errorGuardianConsentRequired,
      },
    },
    ApiErrorCode.validation => {
      for (final entry in e.fieldErrors.entries)
        if (entry.value.trim().isNotEmpty)
          aliases[entry.key] ?? entry.key: serverTextReadable
              ? entry.value.trim()
              : l10n.authFieldRejected,
    },
    _ => const {},
  };
}
