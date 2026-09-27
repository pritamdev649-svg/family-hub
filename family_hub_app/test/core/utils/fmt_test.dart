import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:family_hub/core/utils/fmt.dart';
import 'package:family_hub/l10n/app_localizations.dart';

void main() {
  setUpAll(() async {
    // In the app, flutter_localizations loads the date symbols.
    await initializeDateFormatting();
  });

  final l10n = lookupAppLocalizations(const Locale('en'));

  group('Fmt locale resolution', () {
    test('<lang>_<COUNTRY> when intl knows it', () {
      expect(Fmt.resolveIntlLocale(const Locale('en'), 'IN'), 'en_IN');
      expect(Fmt.resolveIntlLocale(const Locale('en'), 'us'), 'en_US');
      expect(Fmt.resolveIntlLocale(const Locale('en', 'GB')), 'en_GB');
    });
    test('falls back to <lang>, then en', () {
      expect(
        Fmt.resolveIntlLocale(const Locale('hi'), 'IN'),
        anyOf('hi_IN', 'hi'),
      );
      expect(Fmt.resolveIntlLocale(const Locale('ta'), 'ZZ'), 'ta');
      expect(Fmt.resolveIntlLocale(const Locale('xx'), 'IN'), 'en');
    });
  });

  group('Fmt money & numbers', () {
    final inr = Fmt(locale: const Locale('en'), currency: 'INR', country: 'IN');
    final usd = Fmt(locale: const Locale('en'), currency: 'usd', country: 'US');
    final eur = Fmt(locale: const Locale('de'), currency: 'EUR', country: 'DE');

    test('Indian lakh grouping', () {
      expect(inr.money(1234567.5), '₹12,34,567.50');
      expect(inr.money(60000), '₹60,000');
      expect(inr.number(1234567), '12,34,567');
      expect(inr.currencySymbol, '₹');
    });

    test('signs use a true minus', () {
      expect(inr.money(1250.5, signed: true), '+₹1,250.50');
      expect(inr.money(-1250.5), '−₹1,250.50');
      expect(inr.money(0, signed: true), '₹0');
      expect(inr.money(0.1 + 0.2), '₹0.30', reason: 'rounded to 2 decimals');
    });

    test('other currencies / locales', () {
      expect(usd.currency, 'USD');
      expect(usd.money(1234.5), r'$1,234.50');
      final de = eur.money(1234.5);
      expect(de, contains('1.234,50'));
      expect(de, contains('€'));
      expect(
        Fmt(locale: const Locale('en'), currency: 'JPY').money(1500),
        '¥1,500',
      );
    });

    test('compact and percent', () {
      expect(usd.compactMoney(1200000), r'$1.2M');
      expect(usd.compactMoney(-1500), '−\$1.5K');
      expect(usd.percent(0.2083), '21%');
    });

    test('blank currency falls back safely', () {
      expect(Fmt(locale: const Locale('en'), currency: ' ').currency, 'USD');
    });
  });

  group('Fmt dates', () {
    final fmt = Fmt(locale: const Locale('en'), currency: 'USD', country: 'US');
    final d = DateTime(2026, 9, 26, 10, 15);

    test('patterns (local time)', () {
      expect(fmt.date(d), 'Sep 26, 2026');
      expect(fmt.shortDate(d), 'Sep 26');
      expect(fmt.time(d), matches(RegExp(r'^10:15\sAM$')));
      expect(fmt.dateTime(d), startsWith('Sep 26, 2026, 10:15'));
      expect(fmt.monthYear(d), 'September 2026');
      expect(fmt.date(d.toUtc()), 'Sep 26, 2026', reason: 'UTC → local');
      expect(fmt.weekdayDate(DateTime(1999, 1, 1)), 'Fri, Jan 1, 1999');
    });

    test('relative', () {
      final now = DateTime(2026, 9, 26, 12);
      String rel(DateTime t) => fmt.relative(t, l10n, now: now);
      expect(
        rel(now.subtract(const Duration(seconds: 30))),
        l10n.commonJustNow,
      );
      expect(rel(now.add(const Duration(seconds: 30))), l10n.commonJustNow);
      expect(
        rel(now.subtract(const Duration(minutes: 5))),
        l10n.commonMinutesAgo(5),
      );
      expect(
        rel(now.subtract(const Duration(hours: 3))),
        l10n.commonHoursAgo(3),
      );
      expect(rel(DateTime(2026, 9, 25, 9)), l10n.commonYesterday);
      expect(rel(DateTime(2026, 9, 22, 12)), l10n.commonDaysAgo(4));
      expect(rel(DateTime(2026, 8, 1)), 'Aug 1');
      expect(rel(DateTime(2025, 8, 1)), 'Aug 1, 2025');
      expect(rel(DateTime(2026, 9, 26, 18)), l10n.commonToday);
      expect(rel(DateTime(2026, 9, 27, 9)), l10n.commonTomorrow);
      expect(rel(DateTime(2026, 10, 3)), 'Oct 3');
    });

    test('Hindi dates do not throw', () {
      final hi = Fmt(
        locale: const Locale('hi'),
        currency: 'INR',
        country: 'IN',
      );
      expect(hi.date(d), isNotEmpty);
      expect(hi.money(1250), contains('₹'));
    });
  });
}
