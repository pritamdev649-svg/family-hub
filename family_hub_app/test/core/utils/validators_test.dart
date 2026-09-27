import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/utils/validators.dart';
import 'package:family_hub/l10n/app_localizations.dart';
import 'package:family_hub/l10n/app_localizations_en.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  // English strings with a German locale name (decimal comma), so the test
  // does not depend on the German translation being present.
  final de = AppLocalizationsEn('de');

  group('required', () {
    final v = Validators.required(l10n);
    test('blank → error, text → ok', () {
      expect(v(null), l10n.validationRequired);
      expect(v(''), l10n.validationRequired);
      expect(v('   '), l10n.validationRequired);
      expect(v('x'), isNull);
    });
  });

  group('email', () {
    final v = Validators.email(l10n);
    test('valid addresses', () {
      for (final ok in [
        'a@b.co',
        ' amit.sharma+fh@example.co.in ',
        'priya@familyhub.app',
      ]) {
        expect(v(ok), isNull, reason: ok);
      }
    });
    test('invalid addresses', () {
      for (final bad in [
        'a@b',
        'a b@c.com',
        '@c.com',
        'a@.com',
        'a@b.',
        'ab.com',
      ]) {
        expect(v(bad), l10n.validationEmail, reason: bad);
      }
      expect(v(''), l10n.validationRequired);
    });
    test('optional allows blank', () {
      expect(Validators.email(l10n, optional: true)(''), isNull);
      expect(Validators.email(l10n, optional: true)('x'), l10n.validationEmail);
    });
  });

  group('password', () {
    final v = Validators.password(l10n);
    test('rules', () {
      expect(v(''), l10n.validationRequired);
      expect(v('abc123'), l10n.validationPasswordLength);
      expect(v('abcdefgh'), l10n.validationPasswordComplexity);
      expect(v('12345678'), l10n.validationPasswordComplexity);
      expect(v('demo1234'), isNull);
      expect(v('पासवर्ड1234'), isNull, reason: 'non-latin letters count');
      expect(v('a1' * 65), l10n.validationMaxLength(128));
    });
    test('confirmPassword', () {
      final c = TextEditingController(text: 'demo1234');
      addTearDown(c.dispose);
      final confirm = Validators.confirmPassword(l10n, c);
      expect(confirm('demo1234'), isNull);
      expect(confirm('demo12345'), l10n.validationPasswordMismatch);
      expect(confirm(''), l10n.validationRequired);
    });
  });

  group('length', () {
    test('minLength ignores blank, trims', () {
      final v = Validators.minLength(l10n, 3);
      expect(v(''), isNull);
      expect(v(' ab '), l10n.validationMinLength(3));
      expect(v('abc'), isNull);
    });
    test('maxLength counts trimmed UTF-16 units', () {
      final v = Validators.maxLength(l10n, 5);
      expect(v('12345'), isNull);
      expect(v('  12345  '), isNull);
      expect(v('123456'), l10n.validationMaxLength(5));
      expect(v(null), isNull);
    });
  });

  group('amount', () {
    final v = Validators.amount(l10n);
    test('valid amounts', () {
      for (final ok in [
        '1',
        '0.5',
        '1250.50',
        '1,250.50',
        '12,34,567',
        '₹ 999',
      ]) {
        expect(v(ok), isNull, reason: ok);
      }
    });
    test('invalid amounts', () {
      expect(v(''), l10n.validationRequired);
      expect(v('abc'), l10n.validationAmount);
      expect(v('0'), l10n.validationAmount);
      expect(v('-5'), l10n.validationAmount);
      expect(v('1.2.3,4,5'), l10n.validationAmount);
      expect(
        v('1.234'),
        l10n.validationAmountDecimals,
        reason: 'en: . is decimal',
      );
      expect(v('10.999'), l10n.validationAmountDecimals);
      expect(v('1000000000001'), l10n.validationAmountTooLarge);
      expect(v('1000000000000'), isNull);
    });
    test('optional amount', () {
      expect(Validators.amount(l10n, optional: true)(''), isNull);
    });
    test('German input style', () {
      final vd = Validators.amount(de);
      expect(vd('1.234'), isNull, reason: 'de: . is grouping');
      expect(vd('1.234,56'), isNull);
      expect(Validators.amountValue(de, '1.234,56'), 1234.56);
      expect(Validators.amountValue(de, '12,5'), 12.5);
      expect(Validators.amountValue(l10n, '1.234'), 1.234);
    });
  });

  group('parseAmount', () {
    test('locale styles', () {
      expect(Validators.parseAmount('1,250.50'), 1250.5);
      expect(Validators.parseAmount('1.250,50'), 1250.5);
      expect(Validators.parseAmount('12,34,567.89'), 1234567.89);
      expect(Validators.parseAmount('1,250'), 1250);
      expect(Validators.parseAmount('1.250', decimalSeparator: ','), 1250);
      expect(Validators.parseAmount('12,5'), 12.5);
      expect(Validators.parseAmount("1'250.75"), 1250.75);
      expect(
        Validators.parseAmount('1 250,75', decimalSeparator: ','),
        1250.75,
      );
      expect(Validators.parseAmount('.5'), 0.5);
      expect(Validators.parseAmount('€ 12'), 12);
    });
    test('native digits and Arabic separators', () {
      expect(Validators.parseAmount('१२३४.५'), 1234.5);
      expect(Validators.parseAmount('٣٬٤٥٠٫٧٥'), 3450.75);
      expect(Validators.parseAmount('১০০'), 100);
    });
    test('invalid', () {
      expect(Validators.parseAmount(null), isNull);
      expect(Validators.parseAmount(''), isNull);
      expect(Validators.parseAmount('abc'), isNull);
      expect(Validators.parseAmount('-10'), isNull);
      expect(Validators.parseAmount('1.2.3,4'), isNull);
      expect(Validators.parseAmount('1,2,3'), isNull);
      expect(Validators.parseAmount('1234,567.5'), isNull);
      expect(Validators.parseAmount('1,23,45'), isNull);
    });
    test('decimalSeparatorFor', () {
      expect(Validators.decimalSeparatorFor('en'), '.');
      expect(Validators.decimalSeparatorFor('de'), ',');
      expect(Validators.decimalSeparatorFor('fr'), ',');
      expect(Validators.decimalSeparatorFor('hi'), '.');
      expect(Validators.decimalSeparatorFor(null), '.');
      expect(Validators.decimalSeparatorFor('zz'), '.');
    });
  });

  group('phone', () {
    final v = Validators.phone(l10n);
    test('optional by default', () {
      expect(v(''), isNull);
      expect(v(null), isNull);
      expect(
        Validators.phone(l10n, isRequired: true)(''),
        l10n.validationRequired,
      );
    });
    test('formats', () {
      for (final ok in [
        '+91 98765-43210',
        '(030) 1234567',
        '9876543210',
        '+१२३४५६७८९०',
      ]) {
        expect(v(ok), isNull, reason: ok);
      }
      for (final bad in [
        '12345',
        '+1234567890123456',
        'call me',
        '++91987654',
      ]) {
        expect(v(bad), l10n.validationPhone, reason: bad);
      }
    });
    test('normalizePhone', () {
      expect(
        Validators.normalizePhone(' +91 (98765) 43.210 '),
        '+919876543210',
      );
    });
  });

  group('otp', () {
    final v = Validators.otp(l10n);
    test('6 digits', () {
      expect(v('123456'), isNull);
      expect(v('123 456'), isNull);
      expect(v('१२३४५६'), isNull);
      expect(v('12345'), l10n.validationOtp);
      expect(v('1234567'), l10n.validationOtp);
      expect(v('abcdef'), l10n.validationOtp);
      expect(v(''), l10n.validationRequired);
    });
  });

  group('inviteCode', () {
    final v = Validators.inviteCode(l10n);
    test('8 letters/digits, case-insensitive (demo code allowed)', () {
      expect(v('DEMO2345'), isNull);
      expect(v('demo2345'), isNull);
      expect(v('demo-2345'), isNull);
      expect(v(' k7q2 m9xd '), isNull);
      expect(v('DEMO234'), l10n.validationInviteCode);
      expect(v('DEMO23450'), l10n.validationInviteCode);
      expect(v('DEMO-234!'), l10n.validationInviteCode);
      expect(v('DÉMO2345'), l10n.validationInviteCode);
      expect(v(''), l10n.validationRequired);
      expect(Validators.normalizeInviteCode('k7q2-m9xd'), 'K7Q2M9XD');
    });
  });

  group('compose', () {
    test('returns the first error in order', () {
      final v = Validators.compose([
        Validators.required(l10n),
        Validators.minLength(l10n, 3),
        Validators.maxLength(l10n, 5),
      ]);
      expect(v(''), l10n.validationRequired);
      expect(v('ab'), l10n.validationMinLength(3));
      expect(v('abcdef'), l10n.validationMaxLength(5));
      expect(v('abcd'), isNull);
      expect(Validators.compose(const [])('x'), isNull);
    });
  });

  test('normalizeDigits', () {
    expect(Validators.normalizeDigits('٠١٢٣٤٥٦٧٨٩'), '0123456789');
    expect(Validators.normalizeDigits('۰۹'), '09');
    expect(Validators.normalizeDigits('௧௨'), '12');
    expect(Validators.normalizeDigits('１２'), '12');
    expect(Validators.normalizeDigits('abc'), 'abc');
  });
}
