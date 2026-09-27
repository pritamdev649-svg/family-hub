/// Per-country defaults. A family picks its country at sign-up; the country
/// drives currency, the emergency number shown on SOS screens, phone dial
/// code, and the age under which a guardian must consent for a member
/// (digital age of consent under the local privacy law).
///
/// NOTE: consent ages and emergency numbers are sensible defaults, not legal
/// advice. Review with local counsel before launching in a country.
class CountryInfo {
  const CountryInfo({
    required this.code,
    required this.name,
    required this.dialCode,
    required this.currency,
    required this.emergencyNumber,
    required this.consentAge,
    required this.privacyLaw,
    required this.defaultLanguage,
  });

  /// ISO 3166-1 alpha-2 code, e.g. `IN`.
  final String code;
  final String name;
  final String dialCode;

  /// ISO 4217 currency code, e.g. `INR`.
  final String currency;
  final String emergencyNumber;

  /// Members younger than this need verifiable guardian consent.
  final int consentAge;
  final String privacyLaw;

  /// Language code suggested for new families in this country.
  final String defaultLanguage;

  /// Regional-indicator flag emoji built from the ISO code.
  String get flag => String.fromCharCodes(
    code.toUpperCase().codeUnits.map((c) => 0x1F1E6 + c - 0x41),
  );
}

class Countries {
  Countries._();

  static const fallback = CountryInfo(
    code: 'IN',
    name: 'India',
    dialCode: '+91',
    currency: 'INR',
    emergencyNumber: '112',
    consentAge: 18,
    privacyLaw: 'Digital Personal Data Protection Act, 2023',
    defaultLanguage: 'hi',
  );

  static const all = <CountryInfo>[
    fallback,
    CountryInfo(
      code: 'AE',
      name: 'United Arab Emirates',
      dialCode: '+971',
      currency: 'AED',
      emergencyNumber: '999',
      consentAge: 18,
      privacyLaw: 'UAE PDPL',
      defaultLanguage: 'ar',
    ),
    CountryInfo(
      code: 'AU',
      name: 'Australia',
      dialCode: '+61',
      currency: 'AUD',
      emergencyNumber: '000',
      consentAge: 16,
      privacyLaw: 'Privacy Act 1988',
      defaultLanguage: 'en',
    ),
    CountryInfo(
      code: 'BD',
      name: 'Bangladesh',
      dialCode: '+880',
      currency: 'BDT',
      emergencyNumber: '999',
      consentAge: 18,
      privacyLaw: 'Personal Data Protection Ordinance',
      defaultLanguage: 'bn',
    ),
    CountryInfo(
      code: 'BR',
      name: 'Brazil',
      dialCode: '+55',
      currency: 'BRL',
      emergencyNumber: '190',
      consentAge: 18,
      privacyLaw: 'LGPD',
      defaultLanguage: 'pt',
    ),
    CountryInfo(
      code: 'CA',
      name: 'Canada',
      dialCode: '+1',
      currency: 'CAD',
      emergencyNumber: '911',
      consentAge: 13,
      privacyLaw: 'PIPEDA',
      defaultLanguage: 'en',
    ),
    CountryInfo(
      code: 'DE',
      name: 'Germany',
      dialCode: '+49',
      currency: 'EUR',
      emergencyNumber: '112',
      consentAge: 16,
      privacyLaw: 'GDPR',
      defaultLanguage: 'de',
    ),
    CountryInfo(
      code: 'ES',
      name: 'Spain',
      dialCode: '+34',
      currency: 'EUR',
      emergencyNumber: '112',
      consentAge: 14,
      privacyLaw: 'GDPR',
      defaultLanguage: 'es',
    ),
    CountryInfo(
      code: 'FR',
      name: 'France',
      dialCode: '+33',
      currency: 'EUR',
      emergencyNumber: '112',
      consentAge: 15,
      privacyLaw: 'GDPR',
      defaultLanguage: 'fr',
    ),
    CountryInfo(
      code: 'GB',
      name: 'United Kingdom',
      dialCode: '+44',
      currency: 'GBP',
      emergencyNumber: '999',
      consentAge: 13,
      privacyLaw: 'UK GDPR',
      defaultLanguage: 'en',
    ),
    CountryInfo(
      code: 'ID',
      name: 'Indonesia',
      dialCode: '+62',
      currency: 'IDR',
      emergencyNumber: '112',
      consentAge: 18,
      privacyLaw: 'PDP Law',
      defaultLanguage: 'en',
    ),
    CountryInfo(
      code: 'IT',
      name: 'Italy',
      dialCode: '+39',
      currency: 'EUR',
      emergencyNumber: '112',
      consentAge: 14,
      privacyLaw: 'GDPR',
      defaultLanguage: 'en',
    ),
    CountryInfo(
      code: 'KE',
      name: 'Kenya',
      dialCode: '+254',
      currency: 'KES',
      emergencyNumber: '999',
      consentAge: 18,
      privacyLaw: 'Data Protection Act 2019',
      defaultLanguage: 'en',
    ),
    CountryInfo(
      code: 'LK',
      name: 'Sri Lanka',
      dialCode: '+94',
      currency: 'LKR',
      emergencyNumber: '119',
      consentAge: 18,
      privacyLaw: 'PDPA 2022',
      defaultLanguage: 'ta',
    ),
    CountryInfo(
      code: 'MX',
      name: 'Mexico',
      dialCode: '+52',
      currency: 'MXN',
      emergencyNumber: '911',
      consentAge: 18,
      privacyLaw: 'LFPDPPP',
      defaultLanguage: 'es',
    ),
    CountryInfo(
      code: 'MY',
      name: 'Malaysia',
      dialCode: '+60',
      currency: 'MYR',
      emergencyNumber: '999',
      consentAge: 18,
      privacyLaw: 'PDPA 2010',
      defaultLanguage: 'en',
    ),
    CountryInfo(
      code: 'NG',
      name: 'Nigeria',
      dialCode: '+234',
      currency: 'NGN',
      emergencyNumber: '112',
      consentAge: 18,
      privacyLaw: 'NDPA 2023',
      defaultLanguage: 'en',
    ),
    CountryInfo(
      code: 'NL',
      name: 'Netherlands',
      dialCode: '+31',
      currency: 'EUR',
      emergencyNumber: '112',
      consentAge: 16,
      privacyLaw: 'GDPR',
      defaultLanguage: 'en',
    ),
    CountryInfo(
      code: 'NP',
      name: 'Nepal',
      dialCode: '+977',
      currency: 'NPR',
      emergencyNumber: '100',
      consentAge: 18,
      privacyLaw: 'Privacy Act 2018',
      defaultLanguage: 'hi',
    ),
    CountryInfo(
      code: 'NZ',
      name: 'New Zealand',
      dialCode: '+64',
      currency: 'NZD',
      emergencyNumber: '111',
      consentAge: 16,
      privacyLaw: 'Privacy Act 2020',
      defaultLanguage: 'en',
    ),
    CountryInfo(
      code: 'PH',
      name: 'Philippines',
      dialCode: '+63',
      currency: 'PHP',
      emergencyNumber: '911',
      consentAge: 18,
      privacyLaw: 'Data Privacy Act 2012',
      defaultLanguage: 'en',
    ),
    CountryInfo(
      code: 'PK',
      name: 'Pakistan',
      dialCode: '+92',
      currency: 'PKR',
      emergencyNumber: '1122',
      consentAge: 18,
      privacyLaw: 'PECA 2016',
      defaultLanguage: 'en',
    ),
    CountryInfo(
      code: 'PT',
      name: 'Portugal',
      dialCode: '+351',
      currency: 'EUR',
      emergencyNumber: '112',
      consentAge: 13,
      privacyLaw: 'GDPR',
      defaultLanguage: 'pt',
    ),
    CountryInfo(
      code: 'QA',
      name: 'Qatar',
      dialCode: '+974',
      currency: 'QAR',
      emergencyNumber: '999',
      consentAge: 18,
      privacyLaw: 'PDPPL',
      defaultLanguage: 'ar',
    ),
    CountryInfo(
      code: 'SA',
      name: 'Saudi Arabia',
      dialCode: '+966',
      currency: 'SAR',
      emergencyNumber: '911',
      consentAge: 18,
      privacyLaw: 'PDPL',
      defaultLanguage: 'ar',
    ),
    CountryInfo(
      code: 'SG',
      name: 'Singapore',
      dialCode: '+65',
      currency: 'SGD',
      emergencyNumber: '995',
      consentAge: 13,
      privacyLaw: 'PDPA',
      defaultLanguage: 'en',
    ),
    CountryInfo(
      code: 'US',
      name: 'United States',
      dialCode: '+1',
      currency: 'USD',
      emergencyNumber: '911',
      consentAge: 13,
      privacyLaw: 'COPPA / state privacy laws',
      defaultLanguage: 'en',
    ),
    CountryInfo(
      code: 'ZA',
      name: 'South Africa',
      dialCode: '+27',
      currency: 'ZAR',
      emergencyNumber: '112',
      consentAge: 18,
      privacyLaw: 'POPIA',
      defaultLanguage: 'en',
    ),
  ];

  static CountryInfo byCode(String? code) {
    if (code == null) return fallback;
    final upper = code.toUpperCase();
    return all.firstWhere((c) => c.code == upper, orElse: () => fallback);
  }

  /// Currencies offered in pickers (a family may use a currency different
  /// from its country's, e.g. an expat family).
  static List<String> get currencies =>
      ({for (final c in all) c.currency}.toList()..sort());
}
