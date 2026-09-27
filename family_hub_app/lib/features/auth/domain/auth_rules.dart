import 'dart:convert' show utf8;

import 'package:family_hub/core/utils/validators.dart';

/// Rules and clean-up for user-typed auth input, mirroring the server's
/// schemas (family_hub_backend `auth.schemas.js`). Used by the form
/// validators / input formatters and by the `/auth` mock, so the app, the
/// mock and the server agree on what is accepted.
abstract final class AuthInputs {
  static final _notInviteChar = RegExp('[^A-Z0-9]');

  /// bcrypt ignores everything after 72 UTF-8 bytes, so the server rejects
  /// longer new passwords. Letters of many scripts (Devanagari, Tamil,
  /// Arabic …) take 2–3 bytes each, so 30 such letters already exceed it.
  static const passwordMaxBytes = 72;

  /// Control characters (newline, tab, NUL …) and the bidi embedding /
  /// override / isolate controls used for "Trojan Source" spoofing
  /// (U+202A–U+202E, U+2066–U+2069). ZWJ / ZWNJ (Indic scripts, emoji) and
  /// the plain LRM / RLM marks stay allowed.
  static final _forbiddenNameChars = RegExp(
    r'[\p{Cc}\u202A-\u202E\u2066-\u2069]',
    unicode: true,
  );

  /// Characters that render as nothing (Hangul fillers, Braille blank).
  static final _blankLookingChars = RegExp(
    r'[\u115F\u1160\u3164\uFFA0\u2800]',
    unicode: true,
  );
  static final _visibleChar = RegExp(r'[\p{L}\p{N}\p{S}]', unicode: true);

  /// Invite code as the server expects it: native digits → ASCII,
  /// upper-case, only letters / digits, at most 8 characters
  /// (`k7q2-m9xd` → `K7Q2M9XD`).
  static String sanitizeInviteCode(String input) {
    final code = Validators.normalizeDigits(
      input,
    ).toUpperCase().replaceAll(_notInviteChar, '');
    return code.length > Validators.inviteCodeLength
        ? code.substring(0, Validators.inviteCodeLength)
        : code;
  }

  /// One-time code: native digits → ASCII, digits only, at most 6
  /// (`١٢٣ ٤٥٦` → `123456`).
  static String sanitizeOtp(String input) {
    final code = Validators.normalizeOtp(input);
    return code.length > Validators.otpLength
        ? code.substring(0, Validators.otpLength)
        : code;
  }

  /// Whether a new [password] is longer than the server accepts
  /// ([passwordMaxBytes] UTF-8 bytes).
  static bool passwordTooLong(String password) =>
      utf8.encode(password).length > passwordMaxBytes;

  /// Whether a person / family [name] contains characters the server
  /// rejects (control or bidi-override characters).
  static bool hasForbiddenNameChars(String name) =>
      _forbiddenNameChars.hasMatch(name);

  /// Whether [name] has no visible letter, digit or symbol (emoji count),
  /// e.g. only zero-width or filler characters.
  static bool looksBlank(String name) =>
      !_visibleChar.hasMatch(name.replaceAll(_blankLookingChars, ''));
}

/// The server's one-time-code rules (contract §4 plus its hardening, see
/// docs/progress/b-auth.md): 6 digits, valid 10 min, 5 wrong tries, one
/// live code per email and purpose. The resend cooldown grows with the
/// wrong guesses made on the current code, so codes cannot be brute-forced
/// by requesting new ones.
abstract final class OtpRules {
  static const validity = Duration(minutes: 10);

  /// Wrong codes allowed per code (`INVALID_OTP`); then `OTP_EXPIRED`.
  static const maxAttempts = 5;

  /// Minimum time between two codes.
  static const resendCooldown = Duration(seconds: 60);

  /// Extra wait per wrong guess on the current code (5 → 15 min).
  static const wrongGuessCooldown = Duration(minutes: 3);

  /// Wait between sending a code and sending the next one after
  /// [wrongGuesses] wrong tries: `max(60 s, wrong guesses × 3 min)`.
  static Duration resendCooldownAfter(int wrongGuesses) {
    final grown = wrongGuessCooldown * (wrongGuesses < 0 ? 0 : wrongGuesses);
    return grown > resendCooldown ? grown : resendCooldown;
  }
}
