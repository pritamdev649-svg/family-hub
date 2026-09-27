import { z } from 'zod';
import { BLOOD_GROUPS, LIMITS } from '../../lib/constants.js';
import { nullablePhone, objectId } from '../../lib/validate.js';

/**
 * Validation for `/family/members/:memberId/emergency-card` (docs/03-API_CONTRACT.md §6 "EmergencyCard").
 *
 * Contract limits: allergies / medications / conditions ≤ 20 items × 80 chars, emergencyContacts ≤ 5,
 * notes ≤ 500. The remaining text fields use the model backstops from `LIMITS` (doctorName,
 * insuranceProvider, contact name ≤ 100; relation ≤ 60; policy number ≤ 100).
 *
 * Lengths are UTF-16 code units after clean-up (`String#length`). That is what the app's
 * `Validators.maxLength` and the Mongoose `maxlength` backstops count. zod 4's own `.max()`
 * counts code points, so an emoji-heavy value could pass zod and then fail in Mongoose with a
 * message that echoes the value.
 *
 * Input rules (the app sends explicit `null` / `''` to clear a field):
 *   - text clean-up (`cleanText`), applied to every text value before it is checked:
 *       NFC; C0/C1 control characters and the bidi embedding / override / isolate controls
 *       (U+202A–U+202E, U+2066–U+2069, "Trojan Source" spoofing) are removed; line breaks and
 *       tabs become a space in single-line fields, and line breaks become `\n` in `notes`; trimmed.
 *       Text with nothing visible in it (only zero-width / filler / format characters) counts
 *       as blank. ZWJ / ZWNJ and LRM / RLM inside real text are kept, because Indic and Persian
 *       scripts and emoji sequences need them. Malformed UTF-16 (lone surrogates) → 422, because
 *       MongoDB would silently store U+FFFD instead.
 *   - bloodGroup: case-, width- and dash-insensitive (`"ab−"` → `"AB-"`, `"Ｏ＋"` → `"O+"`);
 *     absent / null / blank → `"unknown"`.
 *   - lists: absent / null → `[]`; at most `RAW_LIST_MAX` raw entries (checked before any item is
 *     validated, so a huge array cannot produce a huge error response); items cleaned, blank items
 *     dropped, case-insensitive duplicates removed (first spelling kept), then the 20-item limit.
 *   - text fields: null / blank → null (absent keys are resolved by the service: PUT = replace).
 *   - phones: the shared `phone` block (`+`, 6–15 digits; spaces, dashes and brackets stripped).
 *   - read-only keys a client may round-trip from GET (`memberId`, `updatedAt`, `updatedById`) and any
 *     unknown key (e.g. `allergiesEnc`, `familyId`, `__proto__`) are stripped. They can never be
 *     written through the API.
 */

export const memberCardParams = z.object({ memberId: objectId });

/** Used for a body that is not a JSON object, including a PUT that sends no JSON at all (routes). */
export const CARD_BODY_ERROR = 'Expected an emergency card object';

/** Raw list entries accepted before clean-up: room for blanks / duplicates, bounded work per request. */
export const RAW_LIST_MAX = LIMITS.CARD_LIST_MAX_ITEMS * 5;

const isNullish = (value) => value === null || value === undefined;
const nullishToEmpty = (value) => (isNullish(value) ? [] : value);
const tooLong = (max) => `At most ${max} characters`;
const tooManyItems = `At most ${LIMITS.CARD_LIST_MAX_ITEMS} items`;
const INVALID_CHARACTERS = 'Contains characters that are not allowed';

// ---------------------------------------------------------------- text clean-up

/** Line breaks (and tabs) that become one space in single-line fields. */
const SINGLE_LINE_BREAKS = /[\t\n\v\f\r\u0085\u2028\u2029]+/g;
/** Line breaks normalised to `\n` in multi-line fields (tabs are kept there). */
const MULTI_LINE_BREAKS = /\r\n?|[\v\f\u0085\u2028\u2029]/g;
/** C0/C1 controls other than tab / LF (already handled above) + bidi embedding / override / isolate. */
const STRIPPED_CHARS = /[\u0000-\u0008\u000B-\u001F\u007F-\u009F\u202A-\u202E\u2066-\u2069]/g;
/** Leading / trailing whitespace and the invisible zero-width space / word joiner / BOM. */
const EDGE_BLANKS = /^[\s\u200B\u2060\uFEFF]+|[\s\u200B\u2060\uFEFF]+$/g;
/**
 * A character that renders as something: anything except whitespace, controls, format characters
 * (ZWSP, ZWJ, LRM, …), variation selectors and the blank-looking Hangul fillers / Braille blank.
 */
const VISIBLE_CHAR = /[^\s\p{Cc}\p{Cf}\uFE00-\uFE0F\u115F\u1160\u3164\uFFA0\u2800]/u;

/**
 * Card text as typed → as stored (see the module comment). Non-strings are returned unchanged so
 * the schema reports them. Lone surrogates survive untouched and are rejected by `cardString`.
 */
export function cleanText(value, { multiline = false } = {}) {
  if (typeof value !== 'string') return value;
  const text = (multiline ? value.replace(MULTI_LINE_BREAKS, '\n') : value.replace(SINGLE_LINE_BREAKS, ' '))
    .replace(STRIPPED_CHARS, '')
    .normalize('NFC')
    .replace(EDGE_BLANKS, '');
  return VISIBLE_CHAR.test(text) ? text : '';
}

/** A well-formed string of at most `max` UTF-16 units (`String#length`, see the module comment). */
const boundedString = (max, typeMessage, tooLongMessage = tooLong(max)) =>
  z
    .string({ error: typeMessage })
    .refine((v) => v.isWellFormed(), INVALID_CHARACTERS)
    .refine((v) => v.length <= max, tooLongMessage);

/**
 * Cleaned card text of at most `max` UTF-16 units.
 * `required` → blank is an error (`requiredMessage`); otherwise null / blank → null and absent stays absent.
 */
function cardString(max, { multiline = false, required = false, requiredMessage } = {}) {
  const schema = required
    ? boundedString(max, requiredMessage).min(1, requiredMessage)
    : boundedString(max, 'Must be text').nullable().optional();
  return z.preprocess((value) => {
    const cleaned = cleanText(value, { multiline });
    return !required && cleaned === '' ? null : cleaned;
  }, schema);
}

/** Optional single-line text (null / blank → null). */
const cardText = (max) => cardString(max);

// ---------------------------------------------------------------- blood group

/** Hyphen, dashes, minus signs (incl. full-width / small forms) → `-`. */
const DASHES = /[\u2010-\u2015\u2212\uFE58\uFE63\uFF0D]/g;

/** `"ab +"` → `"AB+"`, `"Ｏ－"` → `"O-"`, `"Unknown"` → `"unknown"`, null / blank → `"unknown"`. Non-strings reach the enum (→ error). */
function normalizeBloodGroup(value) {
  if (isNullish(value)) return 'unknown';
  if (typeof value !== 'string') return value;
  const compact = value.normalize('NFKC').replace(DASHES, '-').replace(/\s+/g, '');
  if (compact === '' || compact.toLowerCase() === 'unknown') return 'unknown';
  return compact.toUpperCase();
}

export const bloodGroup = z.preprocess(
  normalizeBloodGroup,
  z.enum(BLOOD_GROUPS, { error: `Blood group must be one of ${BLOOD_GROUPS.join(', ')}` }),
);

// ---------------------------------------------------------------- lists

/** Non-blank, case-insensitively unique items in their original order (items are already cleaned). */
function cleanItems(items) {
  const seen = new Set();
  const out = [];
  for (const item of items) {
    if (!item) continue;
    const key = item.toLowerCase(); // locale-independent on purpose
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(item);
  }
  return out;
}

const listItem = z.preprocess(
  (value) => cleanText(value),
  boundedString(
    LIMITS.CARD_LIST_ITEM_MAX,
    'Each item must be text',
    `Each item can have at most ${LIMITS.CARD_LIST_ITEM_MAX} characters`,
  ),
);

/**
 * A JSON array of at most `maxRaw` entries, checked **before** its items are parsed: zod's
 * array `.max()` only runs after every element was validated, reporting one issue per item.
 */
const boundedArray = (maxRaw, typeMessage, tooManyMessage, items) =>
  z.preprocess(
    nullishToEmpty,
    z.array(z.unknown(), { error: typeMessage }).max(maxRaw, tooManyMessage).pipe(items),
  );

/** allergies / medications / conditions. */
export const cardList = boundedArray(
  RAW_LIST_MAX,
  'Must be a list of text items',
  tooManyItems,
  z
    .array(listItem)
    .transform(cleanItems)
    .pipe(z.array(z.string()).max(LIMITS.CARD_LIST_MAX_ITEMS, tooManyItems)),
);

// ---------------------------------------------------------------- contacts

export const emergencyContact = z.object(
  {
    name: cardString(LIMITS.CARD_TEXT_MAX, { required: true, requiredMessage: 'Name is required' }),
    phone: nullablePhone,
    relation: cardText(LIMITS.CARD_RELATION_MAX),
  },
  { error: 'Each emergency contact must be an object' },
);

const tooManyContacts = `At most ${LIMITS.CARD_CONTACTS_MAX} emergency contacts`;

export const emergencyContacts = boundedArray(
  LIMITS.CARD_CONTACTS_MAX,
  'Must be a list of contacts',
  tooManyContacts,
  z.array(emergencyContact),
);

// ---------------------------------------------------------------- body

/** PUT body: the editable `EmergencyCard` fields. */
export const emergencyCardBody = z.object(
  {
    bloodGroup,
    allergies: cardList,
    medications: cardList,
    conditions: cardList,
    doctorName: cardText(LIMITS.CARD_TEXT_MAX),
    doctorPhone: nullablePhone,
    insuranceProvider: cardText(LIMITS.CARD_TEXT_MAX),
    insurancePolicyNumber: cardText(LIMITS.CARD_POLICY_NUMBER_MAX),
    emergencyContacts,
    notes: cardString(LIMITS.CARD_NOTES_MAX, { multiline: true }),
  },
  { error: CARD_BODY_ERROR },
);
