import 'package:flutter/widgets.dart';

import 'package:family_hub/core/utils/validators.dart';
import 'package:family_hub/features/auth/domain/auth_rules.dart';
import 'package:family_hub/l10n/app_localizations.dart';

/// Max length of a person's or a family's name (contract §4).
const authNameMaxLength = 60;

/// Validators of the auth forms: the core [Validators] plus the server
/// rules they do not cover ([AuthInputs]), so the user gets a localized
/// message before the round trip instead of the server's English
/// `VALIDATION_ERROR` detail.
abstract final class AuthValidators {
  /// A new password (sign-up, reset): [Validators.password] and at most
  /// [AuthInputs.passwordMaxBytes] UTF-8 bytes.
  static FormFieldValidator<String> newPassword(AppLocalizations l10n) =>
      Validators.compose([
        Validators.password(l10n),
        (v) => AuthInputs.passwordTooLong(v ?? '')
            ? l10n.authPasswordTooLong
            : null,
      ]);

  /// A person or family name: required, at most [maxLength] characters, no
  /// control / bidi-override characters, at least one visible letter,
  /// digit or symbol.
  static FormFieldValidator<String> displayName(
    AppLocalizations l10n, {
    int maxLength = authNameMaxLength,
  }) => Validators.compose([
    Validators.required(l10n),
    Validators.maxLength(l10n, maxLength),
    (v) {
      final name = v?.trim() ?? '';
      if (AuthInputs.hasForbiddenNameChars(name)) {
        return l10n.authNameInvalidCharacters;
      }
      return AuthInputs.looksBlank(name) ? l10n.authNameNeedsLetter : null;
    },
  ]);
}
