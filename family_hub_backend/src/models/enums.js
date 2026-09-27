/**
 * Enumerations and field limits persisted by the Mongoose models.
 *
 * Values come verbatim from docs/03-API_CONTRACT.md. The models validate against
 * these lists, so zod schemas / services should import them from here (or from
 * `src/lib/constants.js`, which may re-export them) instead of re-typing strings.
 *
 * Every export is frozen so a stray `.push()` can never widen an enum at runtime.
 */

const freeze = (list) => Object.freeze([...list]);

// ---------- i18n ----------
export const LOCALES = freeze(['en', 'hi', 'bn', 'ta', 'te', 'mr', 'gu', 'kn', 'ml', 'pa', 'ar', 'es', 'fr', 'pt', 'de']);
export const DEFAULT_LOCALE = 'en';

// ---------- Family / members ----------
export const ROLES = freeze(['admin', 'member']);
export const ROLE = Object.freeze({ ADMIN: 'admin', MEMBER: 'member' });

export const LOCATION_SHARING = freeze(['never', 'sos_only', 'always']);
export const DEFAULT_LOCATION_SHARING = 'never'; // privacy by default

export const GENDERS = freeze(['male', 'female', 'other']);

/**
 * Invite codes (contract §2 "Family"). New codes are generated from the unambiguous
 * alphabet (no 0/O/1/I) by src/lib/crypto.js#randomInviteCode → `INVITE_CODE_REGEX`.
 *
 * Stored codes and user input are accepted in the wider `INVITE_CODE_INPUT_REGEX`
 * (any 8 upper-case letters/digits): the documented demo seed code `DEMO2345` contains an
 * `O`, and the app accepts any 8 letters/digits. Look-ups upper-case the input first.
 */
export const INVITE_CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
export const INVITE_CODE_LENGTH = 8;
export const INVITE_CODE_REGEX = new RegExp(`^[${INVITE_CODE_ALPHABET}]{${INVITE_CODE_LENGTH}}$`);
export const INVITE_CODE_INPUT_REGEX = new RegExp(`^[A-Z0-9]{${INVITE_CODE_LENGTH}}$`);

// ---------- Tasks ----------
export const TASK_CATEGORIES = freeze(['study', 'chore', 'skill', 'health', 'errand', 'other']);
export const TASK_PRIORITIES = freeze(['low', 'medium', 'high']);
export const TASK_STATUSES = freeze(['pending', 'done']);

// ---------- Ledger & goals ----------
export const LEDGER_TYPES = freeze(['income', 'expense']);
export const INCOME_CATEGORIES = freeze(['salary', 'business', 'allowance', 'gift', 'interest', 'other_income']);
export const EXPENSE_CATEGORIES = freeze([
  'groceries',
  'utilities',
  'rent',
  'education',
  'health',
  'transport',
  'dining',
  'shopping',
  'entertainment',
  'household_help',
  'savings',
  'other_expense',
]);
export const LEDGER_CATEGORIES = Object.freeze({ income: INCOME_CATEGORIES, expense: EXPENSE_CATEGORIES });
export const ALL_LEDGER_CATEGORIES = freeze([...INCOME_CATEGORIES, ...EXPENSE_CATEGORIES]);
/** Category used for entries created by goal contributions. */
export const SAVINGS_CATEGORY = 'savings';

/** Valid categories for a ledger `type` (empty list for an unknown type). */
export function ledgerCategoriesFor(type) {
  return LEDGER_CATEGORIES[type] ?? [];
}

/** true when `category` is valid for `type` (contract: "category(valid for type)"). */
export function isLedgerCategoryFor(type, category) {
  return ledgerCategoriesFor(type).includes(category);
}

export const GOAL_STATUSES = freeze(['active', 'achieved', 'archived']);

// ---------- SOS ----------
export const SOS_STATUSES = freeze(['active', 'resolved', 'expired']);
export const SOS_RESOLUTIONS = freeze(['safe', 'false_alarm', 'helped']);
/** `expiresAt = startedAt + 15 min`. */
export const SOS_DURATION_MS = 15 * 60 * 1000;
/** Max points kept in `trail` (`$push` + `$slice: -100`). */
export const SOS_TRAIL_MAX = 100;
/** Location updates arriving sooner than this after the previous stored one are not stored. */
export const SOS_MIN_LOCATION_INTERVAL_MS = 3 * 1000;

// ---------- Emergency card ----------
export const BLOOD_GROUPS = freeze(['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-', 'unknown']);
/** Card fields encrypted at rest with AES-256-GCM (contract §6). Stored as `<field>Enc`. */
export const EMERGENCY_CARD_ENCRYPTED_FIELDS = freeze(['allergies', 'medications', 'conditions', 'insurancePolicyNumber', 'notes']);
/** The encrypted fields that hold string lists (the others hold a single string). */
export const EMERGENCY_CARD_LIST_FIELDS = freeze(['allergies', 'medications', 'conditions']);

// ---------- Devices / auth ----------
export const DEVICE_PLATFORMS = freeze(['android', 'ios']);
export const OTP_PURPOSES = freeze(['verify_email', 'reset_password']);
export const OTP_PURPOSE = Object.freeze({ VERIFY_EMAIL: 'verify_email', RESET_PASSWORD: 'reset_password' });

// ---------- Money ----------
/** Contract: amount ≤ 1e12 major units → 1e14 minor units (still far below Number.MAX_SAFE_INTEGER). */
export const MAX_AMOUNT_MINOR = 1e14;

/**
 * String length limits enforced by the models.
 * Limits given by the contract are exact; the others (marked "backstop") are generous
 * upper bounds so that the zod schemas stay the primary, user-facing validation layer.
 */
export const LIMITS = Object.freeze({
  EMAIL_MAX: 254,
  NAME_MAX: 60, // user / member / family name (contract: 1–60)
  PHONE_MAX: 32, // backstop (zod `phone` allows +, 6–15 digits)
  URL_MAX: 1024, // backstop
  DESIGNATION_MAX: 80, // backstop
  TIMEZONE_MAX: 64,
  TASK_TITLE_MAX: 120, // contract
  TASK_DESCRIPTION_MAX: 1000, // contract
  LEDGER_NOTE_MAX: 200, // contract
  GOAL_TITLE_MAX: 80, // contract
  GOAL_DESCRIPTION_MAX: 1000, // backstop
  NOTICE_TITLE_MAX: 100, // contract
  NOTICE_BODY_MAX: 2000, // contract
  SOS_MESSAGE_MAX: 140, // contract
  CARD_TEXT_MAX: 100, // backstop: doctorName, insuranceProvider, contact name
  CARD_RELATION_MAX: 60, // backstop
  CARD_LIST_MAX_ITEMS: 20, // contract (allergies/medications/conditions)
  CARD_LIST_ITEM_MAX: 80, // contract
  CARD_CONTACTS_MAX: 5, // contract
  CARD_NOTES_MAX: 500, // contract
  CARD_POLICY_NUMBER_MAX: 100, // backstop
  META_MAX: 512, // ip / user agent are truncated (never rejected) to this length
});
