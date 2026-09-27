import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import 'package:family_hub/l10n/app_localizations.dart';

/// Form validators (`FormFieldValidator<String>`) with localized messages.
/// Rules mirror the backend's zod schemas so the user sees problems before
/// a round trip.
///
/// ```dart
/// AppTextField(
///   label: l10n.authEmail,
///   validator: Validators.email(l10n),
/// )
/// AppTextField(
///   label: l10n.tasksTitleLabel,
///   validator: Validators.compose([
///     Validators.required(l10n),
///     Validators.maxLength(l10n, 120),
///   ]),
/// )
/// ```
///
/// Length/format validators accept an empty value (combine with [required]
/// when the field is mandatory) except [email], [password], [amount], [otp]
/// and [inviteCode], which are required unless `optional: true`.
abstract final class Validators {
  /// Invite code alphabet (no 0/O/1/I), contract §2.
  static const inviteAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const inviteCodeLength = 8;
  static const otpLength = 6;
  static const passwordMinLength = 8;
  static const passwordMaxLength = 128;
  static const maxAmount = 1e12;

  static final _email = RegExp(r'^[^\s@]+@[^\s@.]+(\.[^\s@.]+)+$');
  static final _letter = RegExp(r'\p{L}', unicode: true);
  static final _digit = RegExp(r'\d');
  static final _phone = RegExp(r'^\+?\d{6,15}$');
  static final _phoneSeparators = RegExp(r'[\s\-().]');
  static final _invite = RegExp('^[A-Z0-9]{$inviteCodeLength}\$');
  static final _otp = RegExp('^\\d{$otpLength}\$');

  static bool _blank(String? v) => v == null || v.trim().isEmpty;

  /// Non-blank value.
  static FormFieldValidator<String> required(AppLocalizations l10n) =>
      (v) => _blank(v) ? l10n.validationRequired : null;

  /// Email address (trimmed). Blank → required error unless [optional].
  static FormFieldValidator<String> email(
    AppLocalizations l10n, {
    bool optional = false,
  }) => (v) {
    if (_blank(v)) return optional ? null : l10n.validationRequired;
    final value = v!.trim();
    return value.length <= 254 && _email.hasMatch(value)
        ? null
        : l10n.validationEmail;
  };

  /// Password: at least 8 characters with at least one letter and one digit
  /// (not trimmed — spaces are allowed in passwords).
  static FormFieldValidator<String> password(AppLocalizations l10n) => (v) {
    final value = v ?? '';
    if (value.isEmpty) return l10n.validationRequired;
    if (value.length < passwordMinLength) {
      return l10n.validationPasswordLength;
    }
    if (value.length > passwordMaxLength) {
      return l10n.validationMaxLength(passwordMaxLength);
    }
    if (!_letter.hasMatch(value) || !_digit.hasMatch(value)) {
      return l10n.validationPasswordComplexity;
    }
    return null;
  };

  /// Must equal the text of [other] (the password field).
  static FormFieldValidator<String> confirmPassword(
    AppLocalizations l10n,
    TextEditingController other,
  ) => (v) {
    if ((v ?? '').isEmpty) return l10n.validationRequired;
    return v == other.text ? null : l10n.validationPasswordMismatch;
  };

  /// At least [min] characters after trimming (blank passes; use
  /// [required]). Counts UTF-16 code units like the backend.
  static FormFieldValidator<String> minLength(AppLocalizations l10n, int min) =>
      (v) {
        if (_blank(v)) return null;
        return v!.trim().length < min ? l10n.validationMinLength(min) : null;
      };

  /// At most [max] characters after trimming. Counts UTF-16 code units like
  /// the backend's zod `.max()`.
  static FormFieldValidator<String> maxLength(AppLocalizations l10n, int max) =>
      (v) {
        if (v == null) return null;
        return v.trim().length > max ? l10n.validationMaxLength(max) : null;
      };

  /// Money amount: > 0, ≤ 1e12, at most 2 decimals. Understands the
  /// user's decimal separator (from `l10n.localeName`), grouping, currency
  /// symbols and native digits — read the value with
  /// `Validators.parseAmount(text, decimalSeparator:
  /// Validators.decimalSeparatorFor(l10n.localeName))`.
  static FormFieldValidator<String> amount(
    AppLocalizations l10n, {
    bool optional = false,
  }) => (v) {
    if (_blank(v)) return optional ? null : l10n.validationRequired;
    final sep = decimalSeparatorFor(l10n.localeName);
    final split = _splitAmount(v, sep);
    final parsed = parseAmount(v, decimalSeparator: sep);
    if (split == null || parsed == null || parsed <= 0) {
      return l10n.validationAmount;
    }
    if (parsed > maxAmount) return l10n.validationAmountTooLarge;
    if (split.$2.length > 2) return l10n.validationAmountDecimals;
    return null;
  };

  /// Value of an amount field typed in the user's locale (null if invalid).
  static double? amountValue(AppLocalizations l10n, String? text) =>
      parseAmount(text, decimalSeparator: decimalSeparatorFor(l10n.localeName));

  /// Optional phone number: `^\+?\d{6,15}$` after removing spaces, dashes,
  /// dots and parentheses. Blank passes unless [isRequired].
  static FormFieldValidator<String> phone(
    AppLocalizations l10n, {
    bool isRequired = false,
  }) => (v) {
    if (_blank(v)) return isRequired ? l10n.validationRequired : null;
    return _phone.hasMatch(normalizePhone(v!)) ? null : l10n.validationPhone;
  };

  /// Exactly 6 digits (spaces ignored, native digits accepted).
  static FormFieldValidator<String> otp(AppLocalizations l10n) => (v) {
    if (_blank(v)) return l10n.validationRequired;
    return _otp.hasMatch(normalizeOtp(v!)) ? null : l10n.validationOtp;
  };

  /// 8 letters/digits, case-insensitive; spaces and dashes ignored.
  ///
  /// Server-generated codes only use [inviteAlphabet], but the check is
  /// deliberately wider: the seeded demo code `DEMO2345` contains an `O`, and
  /// the server is the authority (`INVALID_INVITE_CODE`).
  static FormFieldValidator<String> inviteCode(AppLocalizations l10n) => (v) {
    if (_blank(v)) return l10n.validationRequired;
    return _invite.hasMatch(normalizeInviteCode(v!))
        ? null
        : l10n.validationInviteCode;
  };

  /// Runs [validators] in order and returns the first error.
  static FormFieldValidator<String> compose(
    List<FormFieldValidator<String>> validators,
  ) => (v) {
    for (final validate in validators) {
      final error = validate(v);
      if (error != null) return error;
    }
    return null;
  };

  // ── Normalisers (also used by forms before sending) ─────────────────────

  /// Converts Arabic-Indic, Persian, Devanagari, Bengali, Gurmukhi, Gujarati,
  /// Tamil, Telugu, Kannada, Malayalam and full-width digits to ASCII.
  static String normalizeDigits(String input) {
    final out = StringBuffer();
    for (final rune in input.runes) {
      out.writeCharCode(_asciiDigit(rune) ?? rune);
    }
    return out.toString();
  }

  static const _zeroDigits = [
    0x0660, // Arabic-Indic
    0x06F0, // Extended Arabic-Indic (Persian/Urdu)
    0x0966, // Devanagari
    0x09E6, // Bengali
    0x0A66, // Gurmukhi
    0x0AE6, // Gujarati
    0x0BE6, // Tamil
    0x0C66, // Telugu
    0x0CE6, // Kannada
    0x0D66, // Malayalam
    0xFF10, // Full-width
  ];

  static int? _asciiDigit(int rune) {
    for (final zero in _zeroDigits) {
      if (rune >= zero && rune <= zero + 9) return 0x30 + rune - zero;
    }
    return null;
  }

  /// `+91 98765-43210` → `+919876543210` (native digits converted).
  static String normalizePhone(String input) =>
      normalizeDigits(input.trim()).replaceAll(_phoneSeparators, '');

  /// `123 456` → `123456` (native digits converted, non-digits dropped).
  static String normalizeOtp(String input) =>
      normalizeDigits(input).replaceAll(RegExp(r'\D'), '');

  /// `k7q2-m9xd` → `K7Q2M9XD`.
  static String normalizeInviteCode(String input) =>
      input.replaceAll(RegExp(r'[\s\-]'), '').toUpperCase();

  /// Parses an amount typed in any common locale style; null when invalid
  /// or negative.
  ///
  /// [decimalSeparator] is the user's locale separator (`.` for en/hi,
  /// `,` for de/fr/es/pt; see [decimalSeparatorFor]). Rules:
  /// * both `.` and `,` present → the last one is the decimal separator
  ///   (`1,250.50`, `1.250,50`);
  /// * one kind repeated → grouping (`1,25,000`, `1.250.000`);
  /// * one occurrence followed by 1–2 digits → decimal (`12,5`, `99.90`);
  /// * one occurrence followed by exactly 3 digits → decimal only if it is
  ///   the locale's decimal separator (`1.250` = 1.25 in `en` and is then
  ///   rejected for having 3 decimals; = 1250 in `de`);
  /// * spaces, NBSPs, apostrophes (`1'250`) and currency symbols are
  ///   ignored; Arabic `٫` / `٬` and native digits are understood.
  static double? parseAmount(String? input, {String decimalSeparator = '.'}) {
    final split = _splitAmount(input, decimalSeparator);
    if (split == null) return null;
    final (intPart, fracPart) = split;
    return double.tryParse(fracPart.isEmpty ? intPart : '$intPart.$fracPart');
  }

  /// Decimal separator of [localeName] (`.` when unknown).
  static String decimalSeparatorFor(String? localeName) {
    if (localeName == null || localeName.isEmpty) return '.';
    try {
      final sep = NumberFormat.decimalPattern(localeName).symbols.DECIMAL_SEP;
      return sep == ',' ? ',' : '.';
    } catch (_) {
      return '.';
    }
  }

  /// Grouped integer part: first group 1–3 digits, middle groups 2–3
  /// (Indian lakh grouping `12,34,567`), last group exactly 3.
  static bool _validGrouping(String intPart) {
    final groups = intPart.split(RegExp(r'[.,]'));
    if (groups.length == 1) return true;
    for (var i = 0; i < groups.length; i++) {
      final len = groups[i].length;
      final ok = i == 0
          ? len >= 1 && len <= 3
          : i == groups.length - 1
          ? len == 3
          : len == 2 || len == 3;
      if (!ok) return false;
    }
    return true;
  }

  /// `(integerDigits, fractionDigits)` or null when not a valid amount.
  static (String, String)? _splitAmount(String? input, String decimalSep) {
    if (input == null) return null;
    final s = normalizeDigits(input)
        .replaceAll('\u066B', decimalSep == ',' ? ',' : '.') // Arabic decimal
        .replaceAll('\u066C', '') // Arabic thousands separator
        .replaceAll(RegExp(r"[\s\u00A0\u202F'’]"), '')
        .replaceAll(RegExp(r'[^\d.,\-]'), '');
    if (s.isEmpty || s.contains('-')) return null;

    final lastDot = s.lastIndexOf('.');
    final lastComma = s.lastIndexOf(',');
    var decimalIndex = -1;
    if (lastDot >= 0 || lastComma >= 0) {
      final last = lastDot > lastComma ? lastDot : lastComma;
      final sep = s[last];
      final bothUsed = lastDot >= 0 && lastComma >= 0;
      final repeated = sep.allMatches(s).length > 1;
      final digitsAfter = s.length - last - 1;
      if (bothUsed) {
        // The decimal separator may appear only once, after all grouping.
        if (repeated) return null;
        decimalIndex = last;
      } else if (!repeated) {
        decimalIndex = digitsAfter == 3 && sep != decimalSep ? -1 : last;
      }
    }

    var intPart = decimalIndex < 0 ? s : s.substring(0, decimalIndex);
    final fracPart = decimalIndex < 0 ? '' : s.substring(decimalIndex + 1);
    if (!_validGrouping(intPart)) return null;
    intPart = intPart.replaceAll(RegExp(r'[.,]'), '');
    if (intPart.isEmpty) intPart = '0';
    if (!RegExp(r'^\d+$').hasMatch(intPart)) return null;
    if (fracPart.isNotEmpty && !RegExp(r'^\d+$').hasMatch(fracPart)) {
      return null;
    }
    if (intPart == '0' && fracPart.isEmpty && !s.contains(RegExp(r'\d'))) {
      return null;
    }
    return (intPart, fracPart);
  }
}
