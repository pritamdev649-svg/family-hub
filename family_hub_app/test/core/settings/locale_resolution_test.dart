import 'package:family_hub/core/config/app_languages.dart';
import 'package:family_hub/core/settings/locale_resolution.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeLocaleCode', () {
    test('accepts every supported language', () {
      for (final lang in AppLanguages.all) {
        expect(normalizeLocaleCode(lang.code), lang.code);
      }
    });

    test('normalises case, region and script suffixes', () {
      expect(normalizeLocaleCode('HI'), 'hi');
      expect(normalizeLocaleCode(' pt-BR '), 'pt');
      expect(normalizeLocaleCode('es_419'), 'es');
      expect(normalizeLocaleCode('ar-EG'), 'ar');
    });

    test('empty, system and unsupported -> null', () {
      expect(normalizeLocaleCode(null), isNull);
      expect(normalizeLocaleCode(''), isNull);
      expect(normalizeLocaleCode('system'), isNull);
      expect(normalizeLocaleCode('zz'), isNull);
      expect(normalizeLocaleCode('ja'), isNull);
    });
  });

  group('resolveAppLocale', () {
    test('a supported choice wins over the device language', () {
      expect(
        resolveAppLocale(
          chosenCode: 'ta',
          deviceLocales: const [Locale('de', 'DE')],
        ),
        const Locale('ta'),
      );
    });

    test('no choice -> device language (region dropped)', () {
      expect(
        resolveAppLocale(
          chosenCode: null,
          deviceLocales: const [Locale('fr', 'CA')],
        ),
        const Locale('fr'),
      );
    });

    test('unsupported choice falls back to the device language', () {
      expect(
        resolveAppLocale(
          chosenCode: 'xx',
          deviceLocales: const [Locale('hi', 'IN')],
        ),
        const Locale('hi'),
      );
    });

    test('uses the first supported device fallback language', () {
      expect(
        resolveAppLocale(
          chosenCode: null,
          deviceLocales: const [
            Locale('ja', 'JP'),
            Locale('bn', 'BD'),
            Locale('en'),
          ],
        ),
        const Locale('bn'),
      );
    });

    test('nothing supported -> English', () {
      expect(
        resolveAppLocale(
          chosenCode: null,
          deviceLocales: const [Locale('ja'), Locale('ko')],
        ),
        const Locale('en'),
      );
      expect(
        resolveAppLocale(chosenCode: null, deviceLocales: const []),
        const Locale('en'),
      );
    });
  });
}
