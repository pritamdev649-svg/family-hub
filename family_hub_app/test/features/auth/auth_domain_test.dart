// Pure logic of the auth feature: route arguments, input sanitising, the
// family draft (country → currency / time zone), error mapping, labels.
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/config/countries.dart';
import 'package:family_hub/core/config/timezones.dart';
import 'package:family_hub/core/network/api_exception.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/features/auth/application/auth_cooldown.dart';
import 'package:family_hub/features/auth/application/auth_errors.dart';
import 'package:family_hub/features/auth/domain/family_draft.dart';
import 'package:family_hub/features/auth/domain/register_args.dart';
import 'package:family_hub/l10n/app_localizations_en.dart';
import 'package:family_hub/features/auth/presentation/auth_labels.dart';
import 'package:family_hub/features/auth/presentation/auth_validators.dart';
import 'package:family_hub/features/auth/presentation/widgets/auth_code_fields.dart';
import 'package:family_hub/features/auth/presentation/widgets/auth_form.dart';
import 'package:family_hub/features/auth/presentation/widgets/country_picker.dart';

import 'auth_test_utils.dart';

void main() {
  group('RegisterArgs.fromQuery', () {
    test('defaults to create without a code', () {
      expect(RegisterArgs.fromQuery(const {}), const RegisterArgs());
    });

    test('reads mode and sanitises the code', () {
      expect(
        RegisterArgs.fromQuery(const {'mode': 'JOIN', 'code': ' k7q2-m9xd '}),
        const RegisterArgs(mode: RegisterMode.join, inviteCode: 'K7Q2M9XD'),
      );
    });

    test('a code without a mode means join (invitation links)', () {
      expect(
        RegisterArgs.fromQuery(const {'code': 'demo2345'}).mode,
        RegisterMode.join,
      );
    });

    test('an explicit create keeps the code for a later switch', () {
      final args = RegisterArgs.fromQuery(const {
        'mode': 'create',
        'code': 'abc',
      });
      expect(args.mode, RegisterMode.create);
      expect(args.inviteCode, 'ABC');
    });

    test('unknown mode falls back to create', () {
      expect(
        RegisterArgs.fromQuery(const {'mode': 'hack'}).mode,
        RegisterMode.create,
      );
    });

    test('location round-trips through the query', () {
      const args = RegisterArgs(
        mode: RegisterMode.join,
        inviteCode: 'K7Q2M9XD',
      );
      final uri = Uri.parse(args.location);
      expect(uri.path, AppRoutes.registerPath);
      expect(RegisterArgs.fromQuery(uri.queryParameters), args);
    });
  });

  group('AuthInputs', () {
    test('sanitizeOtp keeps 6 ASCII digits (native digits converted)', () {
      expect(AuthInputs.sanitizeOtp('123 456'), '123456');
      expect(AuthInputs.sanitizeOtp('١٢٣٤٥٦'), '123456');
      expect(AuthInputs.sanitizeOtp('१२३-४५६'), '123456');
      expect(AuthInputs.sanitizeOtp('12345678'), '123456');
      expect(AuthInputs.sanitizeOtp('abc'), '');
    });

    test('sanitizeInviteCode upper-cases and keeps 8 letters / digits', () {
      expect(AuthInputs.sanitizeInviteCode('k7q2-m9xd'), 'K7Q2M9XD');
      expect(AuthInputs.sanitizeInviteCode(' k7 q2 m9 xd !'), 'K7Q2M9XD');
      expect(AuthInputs.sanitizeInviteCode('ABCDEFGHJK'), 'ABCDEFGH');
    });

    test('input formatters apply the same rules', () {
      TextEditingValue format(TextInputFormatter f, String text) =>
          f.formatEditUpdate(
            TextEditingValue.empty,
            TextEditingValue(text: text),
          );
      final otp = format(otpInputFormatter(), '12 34 567');
      expect(otp.text, '123456');
      expect(otp.selection.baseOffset, 6);
      expect(format(inviteCodeInputFormatter(), 'demo-2345').text, 'DEMO2345');
    });
  });

  group('FamilyDraft', () {
    test('forCountry pre-fills currency and the default time zone', () {
      final de = FamilyDraft.forCountry('de');
      expect(de.country, 'DE');
      expect(de.currency, 'EUR');
      expect(de.timezone, Timezones.defaultFor('DE'));
    });

    test('unknown countries use the fallback country', () {
      expect(FamilyDraft.forCountry('XX').country, Countries.fallback.code);
      expect(
        FamilyDraft.forCountry(null).currency,
        Countries.fallback.currency,
      );
    });

    test('fromLocales picks the first supported device country', () {
      expect(
        FamilyDraft.fromLocales(const [
          Locale('fr'),
          Locale('en', 'GB'),
        ]).country,
        'GB',
      );
      expect(
        FamilyDraft.fromLocales(const [Locale('en')]).country,
        Countries.fallback.code,
      );
    });

    test('withCountry switches currency and time zone', () {
      final us = FamilyDraft.forCountry('IN').withCountry('US');
      expect(us.currency, 'USD');
      expect(Timezones.forCountry('US'), contains(us.timezone));
    });

    test('withCountry keeps a time zone that belongs to the new country', () {
      final zones = Timezones.forCountry('US');
      final draft = FamilyDraft.forCountry('US').copyWith(timezone: zones.last);
      expect(draft.withCountry('US').timezone, zones.last);
    });

    test('options always contain the current values', () {
      const odd = FamilyDraft(country: 'IN', currency: 'XYZ', timezone: 'UTC');
      expect(odd.currencyOptions.first, 'XYZ');
      expect(odd.timezoneOptions, contains('UTC'));
      expect(odd.timezoneOptions, containsAll(Timezones.forCountry('IN')));
    });

    test('toRequest trims the name', () {
      final request = FamilyDraft.forCountry('IN').toRequest('  Sharma  ');
      expect(request.name, 'Sharma');
      expect(request.toJson(), {
        'name': 'Sharma',
        'country': 'IN',
        'currency': 'INR',
        'timezone': Timezones.defaultFor('IN'),
      });
    });
  });

  group('signupConsentAgeIfTooYoung', () {
    final now = DateTime(2026, 9, 27);

    test('returns the consent age only when too young', () {
      expect(
        signupConsentAgeIfTooYoung(DateTime(2011, 9, 28), 'IN', now: now),
        18,
      );
      expect(
        signupConsentAgeIfTooYoung(DateTime(2011, 9, 28), 'US', now: now),
        isNull, // 14 ≥ 13
      );
      expect(
        signupConsentAgeIfTooYoung(DateTime(2013, 9, 28), 'US', now: now),
        13, // one day before the 13th birthday
      );
      expect(
        signupConsentAgeIfTooYoung(DateTime(2013, 9, 27), 'US', now: now),
        isNull, // birthday today
      );
      expect(signupConsentAgeIfTooYoung(null, 'IN', now: now), isNull);
    });
  });

  group('authFieldErrors', () {
    final l10n = enL10n;

    test('maps contract codes to their field', () {
      expect(
        authFieldErrors(
          const ApiException(code: ApiErrorCode.emailTaken, statusCode: 409),
          l10n,
        ),
        {AuthField.email: l10n.errorEmailTaken},
      );
      expect(
        authFieldErrors(
          const ApiException(code: ApiErrorCode.invalidInviteCode),
          l10n,
        ).keys,
        [AuthField.inviteCode],
      );
      expect(
        authFieldErrors(
          const ApiException(code: ApiErrorCode.otpExpired),
          l10n,
        ),
        {AuthField.otp: l10n.errorOtpExpired},
      );
    });

    test('GUARDIAN_CONSENT_REQUIRED goes to the date of birth', () {
      expect(
        authFieldErrors(
          const ApiException(
            code: ApiErrorCode.guardianConsentRequired,
            statusCode: 422,
            details: {'consentAge': 16},
          ),
          l10n,
        ),
        {AuthField.dateOfBirth: l10n.authSignupTooYoung(16)},
      );
      expect(
        authFieldErrors(
          const ApiException(code: ApiErrorCode.guardianConsentRequired),
          l10n,
        ),
        {AuthField.dateOfBirth: l10n.errorGuardianConsentRequired},
      );
    });

    test('validation details keep their paths, renamed by aliases', () {
      const e = ApiException(
        code: ApiErrorCode.validation,
        statusCode: 422,
        details: {'name': 'Too long', 'email': ' Bad ', 'x': 3},
      );
      expect(authFieldErrors(e, l10n), {'name': 'Too long', 'email': 'Bad'});
      expect(authFieldErrors(e, l10n, aliases: AuthField.createFamilyAliases), {
        AuthField.familyName: 'Too long',
        'email': 'Bad',
      });
    });

    test('other errors are not field errors', () {
      expect(
        authFieldErrors(const ApiException(code: ApiErrorCode.network), l10n),
        isEmpty,
      );
      expect(authFieldErrors(StateError('x'), l10n), isEmpty);
    });

    test('authErrorCode reads API codes only', () {
      const e = ApiException(code: ApiErrorCode.invalidCredentials);
      expect(authErrorCode(e), ApiErrorCode.invalidCredentials);
      expect(authErrorCode('oops'), isNull);
    });
  });

  group('ServerFieldErrors', () {
    test('guard prefers the server error until the field is edited', () {
      final errors = ServerFieldErrors();
      final validate = errors.guard(
        'email',
        (v) => v!.isEmpty ? 'empty' : null,
      );
      expect(validate('a@b.co'), isNull);
      expect(errors.show({'email': 'taken', 'other': 'x'}, {'email'}), isTrue);
      expect(errors['other'], isNull); // not a field of this form
      expect(validate('a@b.co'), 'taken');
      errors.clear('email');
      expect(validate(''), 'empty');
    });

    test('show returns false when no error belongs to the form', () {
      final errors = ServerFieldErrors();
      expect(errors.show({'family.name': 'x'}, {'email'}), isFalse);
      expect(errors.isEmpty, isTrue);
    });
  });

  group('labels and helpers', () {
    test('formatWait uses seconds up to 90 s, then rounded-up minutes', () {
      final l10n = enL10n;
      expect(formatWait(l10n, 0), '1 second');
      expect(formatWait(l10n, 1), '1 second');
      expect(formatWait(l10n, 42), '42 seconds');
      expect(formatWait(l10n, 90), '90 seconds');
      expect(formatWait(l10n, 91), '2 minutes');
      expect(formatWait(l10n, 900), '15 minutes');
    });

    test('cooldownSecondsLeft rounds up and never goes negative', () {
      final now = DateTime(2026);
      expect(cooldownSecondsLeft(null, now), 0);
      expect(cooldownSecondsLeft(now, now), 0);
      expect(
        cooldownSecondsLeft(now.add(const Duration(milliseconds: 1)), now),
        1,
      );
      expect(
        cooldownSecondsLeft(now.subtract(const Duration(seconds: 5)), now),
        0,
      );
    });

    test('cooldown keys normalise emails', () {
      expect(
        AuthCooldownKeys.login(' Amit@Example.com '),
        AuthCooldownKeys.login('amit@example.com'),
      );
      expect(
        AuthCooldownKeys.login('a@b.co'),
        isNot(AuthCooldownKeys.passwordReset('a@b.co')),
      );
    });

    test('filterCountries matches name, code and dial code', () {
      expect(filterCountries(''), Countries.all);
      expect(filterCountries('germ').map((c) => c.code), ['DE']);
      expect(filterCountries('de').map((c) => c.code), contains('DE'));
      expect(filterCountries('+91').map((c) => c.code), ['IN']);
      expect(filterCountries('zzz'), isEmpty);
    });
  });

  group('hardening: input rules (server parity)', () {
    final l10n = enL10n;

    test('passwords: at most 72 UTF-8 bytes (bcrypt), whatever the '
        'script', () {
      expect(AuthInputs.passwordTooLong('a1' * 36), isFalse); // 72 bytes
      expect(AuthInputs.passwordTooLong('${'a1' * 36}x'), isTrue);
      // 25 Tamil letters (3 bytes each) = 75 bytes in 25 characters.
      expect(AuthInputs.passwordTooLong('த' * 25), isTrue);

      final validate = AuthValidators.newPassword(l10n);
      expect(validate('${'क' * 26}1'), l10n.authPasswordTooLong);
      expect(validate('${'क' * 23}a1'), isNull);
      // The core rules still come first.
      expect(validate('short1'), l10n.validationPasswordLength);
      expect(validate('lettersonly'), l10n.validationPasswordComplexity);
    });

    test('names: control / bidi-override characters and invisible names '
        'are rejected; every script and emoji is fine', () {
      final rlo = String.fromCharCode(0x202E);
      final isolate = String.fromCharCode(0x2066);
      final zeroWidth = String.fromCharCode(0x200B);
      final filler = String.fromCharCode(0x3164);
      final zwj = String.fromCharCode(0x200D);

      expect(AuthInputs.hasForbiddenNameChars('Amit${rlo}x'), isTrue);
      expect(AuthInputs.hasForbiddenNameChars('Amit${isolate}x'), isTrue);
      // A pasted line break is a control character.
      expect(AuthInputs.hasForbiddenNameChars('Amit\nSharma'), isTrue);
      expect(AuthInputs.looksBlank('$zeroWidth$filler'), isTrue);
      expect(AuthInputs.looksBlank('😀'), isFalse);

      final validate = AuthValidators.displayName(l10n);
      expect(validate('  '), l10n.validationRequired);
      expect(validate('Amit${rlo}x'), l10n.authNameInvalidCharacters);
      expect(validate('$zeroWidth$filler'), l10n.authNameNeedsLetter);
      expect(validate('x' * 61), l10n.validationMaxLength(60));
      for (final ok in [
        'Amit Sharma',
        'अमित शर्मा',
        'محمد علي',
        'ਹਰਪ੍ਰੀਤ',
        'ಕನ್ನಡ',
        '王小明',
        'O’Brien-Nuñez',
        '👨$zwj👩$zwj👧 Family',
      ]) {
        expect(validate(ok), isNull, reason: ok);
      }
    });

    test('one-time codes: resend wait = max(60 s, wrong × 3 min)', () {
      expect(OtpRules.resendCooldownAfter(0), const Duration(seconds: 60));
      expect(OtpRules.resendCooldownAfter(1), const Duration(minutes: 3));
      expect(OtpRules.resendCooldownAfter(5), const Duration(minutes: 15));
      expect(OtpRules.resendCooldownAfter(-1), const Duration(seconds: 60));
      expect(AuthCooldownDefaults.resendSeconds, 60);
    });
  });

  group('hardening: error texts', () {
    final l10n = enL10n;

    test('server validation details are shown only in English; other '
        'languages get a localized text under the field', () {
      const e = ApiException(
        code: ApiErrorCode.validation,
        statusCode: 422,
        details: {'name': 'Name contains characters that are not allowed'},
      );
      expect(authFieldErrors(e, l10n), {
        'name': 'Name contains characters that are not allowed',
      });
      // Hindi UI (the English strings stand in for a translation here).
      final hindi = AppLocalizationsEn('hi');
      expect(authFieldErrors(e, hindi), {'name': hindi.authFieldRejected});
      expect(
        authFieldErrors(e, AppLocalizationsEn('en_IN')).values.single,
        'Name contains characters that are not allowed',
      );
    });

    test('authErrorText: server waits in minutes, the sign-up age gate', () {
      expect(
        authErrorText(
          const ApiException(
            code: ApiErrorCode.tooManyRequests,
            statusCode: 429,
            details: {'retryAfterSeconds': 840},
          ),
          l10n,
        ),
        l10n.authTooManyAttemptsWait(l10n.authCooldownMinutes(14)),
      );
      expect(
        authErrorText(
          const ApiException(
            code: ApiErrorCode.guardianConsentRequired,
            statusCode: 422,
            details: {'consentAge': 18},
          ),
          l10n,
        ),
        l10n.authSignupTooYoung(18),
      );
      // Everything else keeps the generic message.
      expect(
        authErrorText(
          const ApiException(code: ApiErrorCode.tooManyRequests),
          l10n,
        ),
        isNull,
      );
      expect(
        authErrorText(const ApiException(code: ApiErrorCode.network), l10n),
        isNull,
      );
      expect(authErrorText(StateError('x'), l10n), isNull);
    });
  });

  group('hardening: country picker', () {
    test('dial codes: native digits, only for numeric queries', () {
      expect(filterCountries('٩١').map((c) => c.code), ['IN']);
      expect(filterCountries('+ 49').map((c) => c.code), ['DE']);
      // A name query with digits does not match dial codes.
      expect(filterCountries('india 9'), isEmpty);
      expect(filterCountries('+'), isEmpty);
    });

    test('the dial code is isolated left-to-right for RTL layouts', () {
      final india = Countries.byCode('IN');
      final subtitle = countrySubtitle(india);
      expect(
        subtitle,
        '${String.fromCharCode(0x2066)}${india.dialCode}'
        '${String.fromCharCode(0x2069)} · ${india.currency}',
      );
    });
  });
}
