import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import 'package:family_hub/core/utils/date_x.dart';
import 'package:family_hub/l10n/app_localizations.dart';

/// Locale-aware formatting of money, numbers, dates and times.
///
/// Built from the app language + the family's country and currency (widgets
/// use `ref.watch(fmtProvider)` from `formatters.dart`); never format these
/// values by hand in widgets. Every
/// [DateTime] is converted with `.toLocal()` first (the API sends UTC).
///
/// The `intl` locale is `<lang>_<COUNTRY>` when intl knows it (e.g. `en_IN`
/// → lakh grouping `12,34,567`), else `<lang>`, else `en`.
class Fmt {
  Fmt({required Locale locale, required String currency, String? country})
    : currency = currency.trim().isEmpty
          ? 'USD'
          : currency.trim().toUpperCase(),
      intlLocale = resolveIntlLocale(locale, country),
      dateLocale = _resolveDateLocale(locale, country);

  /// Locale used for numbers and money.
  final String intlLocale;

  /// Locale used for dates (intl date data may exist for fewer locales).
  final String dateLocale;

  /// ISO-4217 code, e.g. `INR`.
  final String currency;

  /// `<lang>_<COUNTRY>` if [NumberFormat.localeExists], else `<lang>`, else
  /// `en`. The country comes from [country] (family) or the locale itself.
  static String resolveIntlLocale(Locale locale, [String? country]) {
    for (final candidate in _candidates(locale, country)) {
      if (_numberLocaleExists(candidate)) return candidate;
    }
    return 'en';
  }

  static String _resolveDateLocale(Locale locale, String? country) {
    for (final candidate in _candidates(locale, country)) {
      if (_dateLocaleExists(candidate)) return candidate;
    }
    return 'en';
  }

  static List<String> _candidates(Locale locale, String? country) {
    final lang = locale.languageCode.toLowerCase();
    final cc = (country?.trim().isNotEmpty ?? false)
        ? country!.trim().toUpperCase()
        : locale.countryCode?.toUpperCase();
    return [if (cc != null && cc.isNotEmpty) '${lang}_$cc', lang];
  }

  static bool _numberLocaleExists(String l) {
    try {
      return NumberFormat.localeExists(l);
    } catch (_) {
      return false;
    }
  }

  static bool _dateLocaleExists(String l) {
    try {
      return DateFormat.localeExists(l);
    } catch (_) {
      return false;
    }
  }

  // Formatters are created lazily and reused (Fmt lives as long as the
  // locale/currency does).
  late final NumberFormat _money = _currencyFormat();
  late final NumberFormat _moneyWhole = _currencyFormat(decimalDigits: 0);
  late final NumberFormat _compactMoney = _safe(
    () =>
        NumberFormat.compactSimpleCurrency(locale: intlLocale, name: currency),
    () => NumberFormat.compactSimpleCurrency(locale: 'en', name: currency),
  );
  late final NumberFormat _number = _safe(
    () => NumberFormat.decimalPattern(intlLocale),
    () => NumberFormat.decimalPattern('en'),
  );
  late final DateFormat _date = _dateFormat((l) => DateFormat.yMMMd(l));
  late final DateFormat _shortDate = _dateFormat((l) => DateFormat.MMMd(l));
  late final DateFormat _time = _dateFormat((l) => DateFormat.jm(l));
  late final DateFormat _monthYear = _dateFormat((l) => DateFormat.yMMMM(l));
  late final DateFormat _weekdayDate = _dateFormat((l) => DateFormat.MMMEd(l));
  late final DateFormat _weekdayDateYear = _dateFormat(
    (l) => DateFormat.yMMMEd(l),
  );

  NumberFormat _currencyFormat({int? decimalDigits}) => _safe(
    () => NumberFormat.simpleCurrency(
      locale: intlLocale,
      name: currency,
      decimalDigits: decimalDigits,
    ),
    () => NumberFormat.simpleCurrency(
      locale: 'en',
      name: currency,
      decimalDigits: decimalDigits,
    ),
  );

  DateFormat _dateFormat(DateFormat Function(String locale) build) =>
      _safe(() => build(dateLocale), () => build('en'));

  static T _safe<T>(T Function() primary, T Function() fallback) {
    try {
      return primary();
    } catch (_) {
      return fallback();
    }
  }

  static const _minus = '−';

  /// `₹1,250.50`, `₹60,000` (fraction digits only when needed).
  /// [signed]: `+₹1,250.50` / `−₹1,250.50` (true minus sign, for ledgers).
  String money(num v, {bool signed = false}) {
    final rounded = _round2(v);
    final abs = rounded.abs();
    final isWhole = abs == abs.truncateToDouble();
    final text = (isWhole ? _moneyWhole : _money).format(abs);
    if (rounded < 0) return '$_minus$text';
    if (signed && rounded > 0) return '+$text';
    return text;
  }

  /// `₹1.2L`, `$3.4K` for tight spaces (charts, chips).
  String compactMoney(num v) {
    final rounded = _round2(v);
    final text = _compactMoney.format(rounded.abs());
    return rounded < 0 ? '$_minus$text' : text;
  }

  /// Currency symbol for the family currency, e.g. `₹`, `$`, `€`.
  String get currencySymbol => _money.currencySymbol;

  /// `12,34,567.5` (locale grouping).
  String number(num v) => _number.format(v);

  /// Percentage from a 0–1 ratio: `0.2083` → `21%`.
  String percent(num ratio) => _safe(
    () => NumberFormat.percentPattern(intlLocale),
    () => NumberFormat.percentPattern('en'),
  ).format(ratio);

  /// `Sep 26, 2026` / `26 Sept 2026` / `26 सित॰ 2026`.
  String date(DateTime d) => _date.format(d.toLocal());

  /// `Sep 26` (no year).
  String shortDate(DateTime d) => _shortDate.format(d.toLocal());

  /// `Sep 26, 2026, 10:15 AM`.
  String dateTime(DateTime d) => '${date(d)}, ${time(d)}';

  /// `10:15 AM` / `10:15`.
  String time(DateTime d) => _time.format(d.toLocal());

  /// `September 2026`.
  String monthYear(DateTime d) => _monthYear.format(d.toLocal());

  /// `Sat, Sep 26` (adds the year when not the current year).
  String weekdayDate(DateTime d) {
    final local = d.toLocal();
    return local.year == DateTime.now().year
        ? _weekdayDate.format(local)
        : _weekdayDateYear.format(local);
  }

  /// Relative past time: `Just now`, `5 minutes ago`, `3 hours ago`,
  /// `Yesterday`, `4 days ago`, then the date. Future moments (e.g. due
  /// dates) show `Today`/`Tomorrow`/date.
  String relative(DateTime d, AppLocalizations l10n, {DateTime? now}) {
    final local = d.toLocal();
    final current = (now ?? DateTime.now()).toLocal();
    final diff = current.difference(local);

    if (diff.isNegative && diff.inSeconds.abs() > 60) {
      if (local.isSameDay(current)) return l10n.commonToday;
      if (local.isSameDay(current.add(const Duration(days: 1)))) {
        return l10n.commonTomorrow;
      }
      return _dateMaybeYear(local, current);
    }
    if (diff.inSeconds < 60) return l10n.commonJustNow;
    if (diff.inMinutes < 60) return l10n.commonMinutesAgo(diff.inMinutes);
    if (diff.inHours < 24) return l10n.commonHoursAgo(diff.inHours);
    final days = current.startOfDay.difference(local.startOfDay).inDays;
    if (days <= 1) return l10n.commonYesterday;
    if (days < 7) return l10n.commonDaysAgo(days);
    return _dateMaybeYear(local, current);
  }

  String _dateMaybeYear(DateTime local, DateTime current) =>
      local.year == current.year ? shortDate(local) : date(local);

  static double _round2(num v) => (v * 100).roundToDouble() / 100;
}
