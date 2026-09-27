/**
 * Per-country defaults — mirrors family_hub_app/lib/core/config/countries.dart.
 * Keep both lists in sync (code, currency, consentAge, emergencyNumber must match).
 *
 * `consentAge` = age under which a guardian must consent for a member (digital age of
 * consent under the local privacy law). Values are sensible defaults, not legal advice.
 */

const list = [
  ['IN', 'India', '+91', 'INR', '112', 18, 'hi'],
  ['AE', 'United Arab Emirates', '+971', 'AED', '999', 18, 'ar'],
  ['AU', 'Australia', '+61', 'AUD', '000', 16, 'en'],
  ['BD', 'Bangladesh', '+880', 'BDT', '999', 18, 'bn'],
  ['BR', 'Brazil', '+55', 'BRL', '190', 18, 'pt'],
  ['CA', 'Canada', '+1', 'CAD', '911', 13, 'en'],
  ['DE', 'Germany', '+49', 'EUR', '112', 16, 'de'],
  ['ES', 'Spain', '+34', 'EUR', '112', 14, 'es'],
  ['FR', 'France', '+33', 'EUR', '112', 15, 'fr'],
  ['GB', 'United Kingdom', '+44', 'GBP', '999', 13, 'en'],
  ['ID', 'Indonesia', '+62', 'IDR', '112', 18, 'en'],
  ['IT', 'Italy', '+39', 'EUR', '112', 14, 'en'],
  ['KE', 'Kenya', '+254', 'KES', '999', 18, 'en'],
  ['LK', 'Sri Lanka', '+94', 'LKR', '119', 18, 'ta'],
  ['MX', 'Mexico', '+52', 'MXN', '911', 18, 'es'],
  ['MY', 'Malaysia', '+60', 'MYR', '999', 18, 'en'],
  ['NG', 'Nigeria', '+234', 'NGN', '112', 18, 'en'],
  ['NL', 'Netherlands', '+31', 'EUR', '112', 16, 'en'],
  ['NP', 'Nepal', '+977', 'NPR', '100', 18, 'hi'],
  ['NZ', 'New Zealand', '+64', 'NZD', '111', 16, 'en'],
  ['PH', 'Philippines', '+63', 'PHP', '911', 18, 'en'],
  ['PK', 'Pakistan', '+92', 'PKR', '1122', 18, 'en'],
  ['PT', 'Portugal', '+351', 'EUR', '112', 13, 'pt'],
  ['QA', 'Qatar', '+974', 'QAR', '999', 18, 'ar'],
  ['SA', 'Saudi Arabia', '+966', 'SAR', '911', 18, 'ar'],
  ['SG', 'Singapore', '+65', 'SGD', '995', 13, 'en'],
  ['US', 'United States', '+1', 'USD', '911', 13, 'en'],
  ['ZA', 'South Africa', '+27', 'ZAR', '112', 18, 'en'],
];

/** code → { code, name, dialCode, currency, emergencyNumber, consentAge, defaultLanguage } */
export const COUNTRIES = Object.freeze(
  Object.fromEntries(
    list.map(([code, name, dialCode, currency, emergencyNumber, consentAge, defaultLanguage]) => [
      code,
      Object.freeze({ code, name, dialCode, currency, emergencyNumber, consentAge, defaultLanguage }),
    ]),
  ),
);

export const COUNTRY_CODES = Object.freeze(Object.keys(COUNTRIES).sort());

/** Country used when a code is unknown (same as the app's `Countries.fallback`). */
export const FALLBACK_COUNTRY = 'IN';

/**
 * Currencies offered to families (a family may pick a currency different from its
 * country's, e.g. an expat family) — same list as the app's `Countries.currencies`.
 */
export const CURRENCIES = Object.freeze([...new Set(list.map((c) => c[3]))].sort());

/** Upper-cases and trims a country/currency code; non-strings → ''. */
function norm(code) {
  return typeof code === 'string' ? code.trim().toUpperCase() : '';
}

export function isCountry(code) {
  return Object.hasOwn(COUNTRIES, norm(code));
}

export function isCurrency(code) {
  return CURRENCIES.includes(norm(code));
}

/** Country info for a code, falling back to India (like the app). */
export function getCountry(code) {
  return COUNTRIES[norm(code)] ?? COUNTRIES[FALLBACK_COUNTRY];
}

/**
 * Age under which guardian consent is required. Unknown countries use 18 — the
 * strictest value in the list — so a typo can never lower the protection.
 */
export function consentAge(code) {
  return COUNTRIES[norm(code)]?.consentAge ?? 18;
}

export function emergencyNumber(code) {
  return getCountry(code).emergencyNumber;
}

/** Default currency of a country (unknown → INR, like the app's fallback). */
export function currencyOf(code) {
  return getCountry(code).currency;
}
