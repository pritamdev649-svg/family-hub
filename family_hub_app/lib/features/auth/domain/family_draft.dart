import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Locale;

import 'package:family_hub/core/config/countries.dart';
import 'package:family_hub/core/config/timezones.dart';
import 'package:family_hub/core/utils/date_x.dart';
import 'package:family_hub/shared/data/family_repository.dart'
    show CreateFamilyRequest;

/// Country, currency and time zone of a family being created (the name is
/// a text field of its own). Picking a country pre-fills the other two with
/// that country's defaults (docs/07-I18N_AND_COUNTRIES.md).
@immutable
class FamilyDraft {
  const FamilyDraft({
    required this.country,
    required this.currency,
    required this.timezone,
  });

  /// Defaults of [countryCode] ([Countries.fallback] when unknown).
  factory FamilyDraft.forCountry(String? countryCode) {
    final info = Countries.byCode(countryCode);
    return FamilyDraft(
      country: info.code,
      currency: info.currency,
      timezone: Timezones.defaultFor(info.code),
    );
  }

  /// Best first guess from the device's preferred locales (`hi_IN` → India,
  /// `de_DE` → Germany); [Countries.fallback] when none names a supported
  /// country.
  factory FamilyDraft.fromLocales(Iterable<Locale> locales) {
    for (final locale in locales) {
      final code = locale.countryCode?.toUpperCase();
      if (code != null && Countries.all.any((c) => c.code == code)) {
        return FamilyDraft.forCountry(code);
      }
    }
    return FamilyDraft.forCountry(Countries.fallback.code);
  }

  /// ISO 3166-1 alpha-2.
  final String country;

  /// ISO 4217.
  final String currency;

  /// IANA zone.
  final String timezone;

  CountryInfo get countryInfo => Countries.byCode(country);

  /// Zones offered for [country]; the current zone is kept in the list so a
  /// stale value never disappears from the picker.
  List<String> get timezoneOptions {
    final zones = Timezones.forCountry(country);
    return zones.contains(timezone) ? zones : [timezone, ...zones];
  }

  /// Currencies offered in the picker (the current one always included).
  List<String> get currencyOptions {
    final all = Countries.currencies;
    return all.contains(currency) ? all : [currency, ...all];
  }

  /// Switches to [countryCode]: currency becomes the country's currency and
  /// the time zone its default (kept when it belongs to the new country).
  FamilyDraft withCountry(String countryCode) {
    final info = Countries.byCode(countryCode);
    return FamilyDraft(
      country: info.code,
      currency: info.currency,
      timezone: Timezones.normalizeFor(info.code, timezone),
    );
  }

  FamilyDraft copyWith({String? currency, String? timezone}) => FamilyDraft(
    country: country,
    currency: currency ?? this.currency,
    timezone: timezone ?? this.timezone,
  );

  /// Body of `POST /family` / register's `family` with [name].
  CreateFamilyRequest toRequest(String name) => CreateFamilyRequest(
    name: name.trim(),
    country: country,
    currency: currency,
    timezone: timezone,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FamilyDraft &&
          other.country == country &&
          other.currency == currency &&
          other.timezone == timezone;

  @override
  int get hashCode => Object.hash(country, currency, timezone);

  @override
  String toString() => 'FamilyDraft($country, $currency, $timezone)';
}

/// Self-registration age gate (docs/08-COMPLIANCE.md GAP-01, enforced by the
/// server with `GUARDIAN_CONSENT_REQUIRED`): the country's consent age when
/// somebody born on [dateOfBirth] is younger than it, else `null` (also when
/// the date is unknown).
int? signupConsentAgeIfTooYoung(
  DateTime? dateOfBirth,
  String? countryCode, {
  DateTime? now,
}) {
  final age = ageFrom(dateOfBirth, now: now);
  final consentAge = Countries.byCode(countryCode).consentAge;
  return age != null && age < consentAge ? consentAge : null;
}
