/// IANA time zones offered per country (see `countries.dart`).
///
/// A family stores one IANA zone (`family.timezone`). The backend uses it for
/// month ranges, "today" and "this week", so it must be a canonical IANA
/// identifier that Node's ICU understands. Multi-zone countries list their
/// most populous zone first; that first entry is the default.
///
/// Only long-established canonical identifiers are used (no zones added in
/// recent tzdb releases) so older server/device ICU data accepts them.
class Timezones {
  Timezones._();

  /// Used for unknown countries.
  static const utc = 'UTC';

  /// Zones per ISO 3166-1 alpha-2 country code. The first entry is the
  /// default for that country.
  static const byCountry = <String, List<String>>{
    'AE': ['Asia/Dubai'],
    'AU': [
      'Australia/Sydney',
      'Australia/Melbourne',
      'Australia/Brisbane',
      'Australia/Adelaide',
      'Australia/Perth',
      'Australia/Hobart',
      'Australia/Darwin',
    ],
    'BD': ['Asia/Dhaka'],
    'BR': [
      'America/Sao_Paulo',
      'America/Bahia',
      'America/Fortaleza',
      'America/Recife',
      'America/Belem',
      'America/Manaus',
      'America/Cuiaba',
      'America/Campo_Grande',
      'America/Porto_Velho',
      'America/Boa_Vista',
      'America/Rio_Branco',
      'America/Noronha',
    ],
    'CA': [
      'America/Toronto',
      'America/Vancouver',
      'America/Edmonton',
      'America/Winnipeg',
      'America/Regina',
      'America/Halifax',
      'America/St_Johns',
      'America/Whitehorse',
    ],
    'DE': ['Europe/Berlin'],
    'ES': ['Europe/Madrid', 'Atlantic/Canary', 'Africa/Ceuta'],
    'FR': ['Europe/Paris'],
    'GB': ['Europe/London'],
    'ID': ['Asia/Jakarta', 'Asia/Pontianak', 'Asia/Makassar', 'Asia/Jayapura'],
    'IN': ['Asia/Kolkata'],
    'IT': ['Europe/Rome'],
    'KE': ['Africa/Nairobi'],
    'LK': ['Asia/Colombo'],
    'MX': [
      'America/Mexico_City',
      'America/Monterrey',
      'America/Merida',
      'America/Cancun',
      'America/Chihuahua',
      'America/Mazatlan',
      'America/Hermosillo',
      'America/Tijuana',
    ],
    'MY': ['Asia/Kuala_Lumpur', 'Asia/Kuching'],
    'NG': ['Africa/Lagos'],
    'NL': ['Europe/Amsterdam'],
    'NP': ['Asia/Kathmandu'],
    'NZ': ['Pacific/Auckland', 'Pacific/Chatham'],
    'PH': ['Asia/Manila'],
    'PK': ['Asia/Karachi'],
    'PT': ['Europe/Lisbon', 'Atlantic/Madeira', 'Atlantic/Azores'],
    'QA': ['Asia/Qatar'],
    'SA': ['Asia/Riyadh'],
    'SG': ['Asia/Singapore'],
    'US': [
      'America/New_York',
      'America/Chicago',
      'America/Denver',
      'America/Phoenix',
      'America/Los_Angeles',
      'America/Anchorage',
      'Pacific/Honolulu',
    ],
    'ZA': ['Africa/Johannesburg'],
  };

  /// Every zone the app offers (all countries + UTC), alphabetical.
  static const all = <String>[
    'Africa/Ceuta',
    'Africa/Johannesburg',
    'Africa/Lagos',
    'Africa/Nairobi',
    'America/Anchorage',
    'America/Bahia',
    'America/Belem',
    'America/Boa_Vista',
    'America/Campo_Grande',
    'America/Cancun',
    'America/Chicago',
    'America/Chihuahua',
    'America/Cuiaba',
    'America/Denver',
    'America/Edmonton',
    'America/Fortaleza',
    'America/Halifax',
    'America/Hermosillo',
    'America/Los_Angeles',
    'America/Manaus',
    'America/Mazatlan',
    'America/Merida',
    'America/Mexico_City',
    'America/Monterrey',
    'America/New_York',
    'America/Noronha',
    'America/Phoenix',
    'America/Porto_Velho',
    'America/Recife',
    'America/Regina',
    'America/Rio_Branco',
    'America/Sao_Paulo',
    'America/St_Johns',
    'America/Tijuana',
    'America/Toronto',
    'America/Vancouver',
    'America/Whitehorse',
    'America/Winnipeg',
    'Asia/Colombo',
    'Asia/Dhaka',
    'Asia/Dubai',
    'Asia/Jakarta',
    'Asia/Jayapura',
    'Asia/Karachi',
    'Asia/Kathmandu',
    'Asia/Kolkata',
    'Asia/Kuala_Lumpur',
    'Asia/Kuching',
    'Asia/Makassar',
    'Asia/Manila',
    'Asia/Pontianak',
    'Asia/Qatar',
    'Asia/Riyadh',
    'Asia/Singapore',
    'Atlantic/Azores',
    'Atlantic/Canary',
    'Atlantic/Madeira',
    'Australia/Adelaide',
    'Australia/Brisbane',
    'Australia/Darwin',
    'Australia/Hobart',
    'Australia/Melbourne',
    'Australia/Perth',
    'Australia/Sydney',
    'Europe/Amsterdam',
    'Europe/Berlin',
    'Europe/Lisbon',
    'Europe/London',
    'Europe/Madrid',
    'Europe/Paris',
    'Europe/Rome',
    'Pacific/Auckland',
    'Pacific/Chatham',
    'Pacific/Honolulu',
    utc,
  ];

  /// Zones for [code] (case-insensitive); `['UTC']` for unknown countries.
  static List<String> forCountry(String? code) =>
      byCountry[code?.trim().toUpperCase()] ?? const [utc];

  /// Default zone for [code]; `UTC` for unknown countries.
  static String defaultFor(String? code) => forCountry(code).first;

  /// Whether [zone] is one the app offers.
  static bool isKnown(String? zone) => zone != null && all.contains(zone);

  /// Keeps [current] when it belongs to [countryCode], else the country
  /// default. Use when the user switches country in a form.
  static String normalizeFor(String? countryCode, String? current) {
    final zones = forCountry(countryCode);
    return current != null && zones.contains(current) ? current : zones.first;
  }

  /// Human friendly label: `America/Los_Angeles` → `Los Angeles`.
  static String cityName(String zone) {
    final slash = zone.lastIndexOf('/');
    final city = slash >= 0 ? zone.substring(slash + 1) : zone;
    return city.replaceAll('_', ' ');
  }
}
