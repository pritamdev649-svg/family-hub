import { z } from 'zod';
import { LIMITS, ROLES } from '../../lib/constants.js';
import { isValidTimeZone } from '../../lib/dates.js';
import {
  countryCode,
  currencyCode,
  idParams,
  inviteCode,
  isoDate,
  nullableCloudinaryUrl,
  nullableEmail,
  nullableField,
  nullableGender,
  nullablePhone,
} from '../../lib/validate.js';
import { displayName } from '../auth/auth.schemas.js';

/**
 * Request schemas of `/family/*` (docs/03-API_CONTRACT.md §6), built from the shared zod blocks.
 *
 * Every body is **strict**: an unknown key (`inviteCode`, `ownerId`, `userId`, `locationSharing` …)
 * is rejected with `422 VALIDATION_ERROR` instead of being dropped silently, so a client never
 * believes it changed something it cannot change here (same rule as `PATCH /me`).
 *
 * Nullable fields follow the shared PATCH rule of lib/validate.js: absent → unchanged,
 * `null` / blank → cleared, anything else → validated.
 *
 * Names (family and member) use the register rules (`displayName`: trimmed, 1–60, NFC, no
 * control or text-direction override characters, at least one visible character), so a profile
 * an admin creates can always be linked to an account later — plus well-formed UTF-16: a lone
 * surrogate (`"\ud800"`) would be stored by MongoDB as U+FFFD, so the saved name would differ
 * from the one echoed back.
 */

// ---------------------------------------------------------------- time zones

/**
 * Canonical IANA zones of the runtime's ICU data. Node's list holds one canonical name per zone
 * and omits aliases: `Asia/Kolkata` (a family default) is missing because ICU's canonical id is
 * `Asia/Calcutta`, and so is `UTC`. Aliases are therefore accepted when ICU resolves them to a
 * listed zone (see `normalizeFamilyTimeZone`).
 */
const SUPPORTED_TIME_ZONES = (() => {
  try {
    return Intl.supportedValuesOf('timeZone');
  } catch {
    return [];
  }
})();
const ZONE_BY_LOWER_NAME = new Map(SUPPORTED_TIME_ZONES.map((zone) => [zone.toLowerCase(), zone]));
const UTC_ZONE = 'UTC';
/** `Area/Location[/Sub]`-shaped names or single words (`UTC`); no numeric offsets such as `+05:30`. */
const ZONE_NAME_SHAPE = /^[A-Za-z][A-Za-z0-9_+-]*(?:\/[A-Za-z0-9_+-]+)*$/;

/** The zone ICU resolves `name` to (e.g. `Asia/Kolkata` → `Asia/Calcutta`), or null when unknown. */
function resolveZone(name) {
  try {
    return new Intl.DateTimeFormat('en-US', { timeZone: name }).resolvedOptions().timeZone;
  } catch {
    return null;
  }
}

/**
 * Family time zone check (`Intl.supportedValuesOf('timeZone')`), returning the value to store or
 * null when the zone is not accepted.
 *
 *   - a listed zone, any letter case         → its canonical spelling (`asia/tokyo` → `Asia/Tokyo`)
 *   - an alias of a listed zone               → as sent (`Asia/Kolkata`, `Europe/Kyiv`: the names
 *                                               the app offers, which newer tzdb releases prefer)
 *   - `UTC` and its aliases (`Etc/UTC`, `GMT`) → `UTC`
 *   - anything else (unknown names, `+05:30` offsets, `Etc/GMT+5`, blank, > 64 chars) → null
 *
 * Without `Intl.supportedValuesOf` (very old runtimes) any zone ICU accepts is taken.
 * @param {unknown} value
 * @returns {string|null}
 */
export function normalizeFamilyTimeZone(value) {
  if (typeof value !== 'string') return null;
  const name = value.trim();
  if (!name || name.length > LIMITS.TIMEZONE_MAX || !ZONE_NAME_SHAPE.test(name)) return null;
  const listed = ZONE_BY_LOWER_NAME.get(name.toLowerCase());
  if (listed) return listed;
  const resolved = resolveZone(name);
  if (!resolved) return null;
  if (resolved === UTC_ZONE) return UTC_ZONE;
  if (!SUPPORTED_TIME_ZONES.length) return isValidTimeZone(name) ? name : null;
  return ZONE_BY_LOWER_NAME.has(resolved.toLowerCase()) ? name : null;
}

const INVALID_TIME_ZONE = 'Invalid time zone';

/** IANA time zone of a family, normalised by `normalizeFamilyTimeZone`. */
export const familyTimeZone = z
  .string({ error: INVALID_TIME_ZONE })
  .transform((value, ctx) => {
    const zone = normalizeFamilyTimeZone(value);
    if (zone === null) {
      ctx.addIssue({ code: 'custom', message: INVALID_TIME_ZONE });
      return z.NEVER;
    }
    return zone;
  });

// ---------------------------------------------------------------- text

/** true for a string without lone surrogates (valid UTF-16, so it survives BSON's UTF-8). */
const isWellFormed = (value) => typeof value !== 'string' || value.isWellFormed();

/** Family / member name: `displayName` + well-formed text. */
const name = displayName.refine(isWellFormed, 'Name contains characters that are not allowed');

/** Control characters and text-direction overrides never belong in a title shown in lists and pushes. */
const FORBIDDEN_TEXT_CHARS = /[\p{Cc}\u202A-\u202E\u2066-\u2069]/u;

/**
 * Characters that render as nothing: format characters (zero-width space / joiners, LRM / RLM …),
 * separators and blank-looking letters (Hangul fillers, Braille blank). Text made only of these
 * is blank.
 */
const INVISIBLE_CHARS = /[\p{Cf}\p{Z}\u115F\u1160\u3164\uFFA0\u2800]/gu;

// ---------------------------------------------------------------- family

/** `POST /family` — the same fields as the `family` object of register (create mode). */
export const createFamilyBody = z.strictObject({
  name,
  country: countryCode,
  currency: currencyCode,
  timezone: familyTimeZone,
});

/** `PATCH /family` (admin): every field optional; `{}` changes nothing. */
export const updateFamilyBody = z.strictObject({
  name: name.optional(),
  country: countryCode.optional(),
  currency: currencyCode.optional(),
  timezone: familyTimeZone.optional(),
});

/** `POST /family/join` — case-insensitive; spaces and dashes are ignored (`"k7q2-m9xd"`). */
export const joinFamilyBody = z.strictObject({
  inviteCode,
});

// ---------------------------------------------------------------- members

const DAY_MS = 24 * 60 * 60 * 1000;
const OLDEST_BIRTH_YEAR = 1900;

/** Same rules as register and `PATCH /me`: not in the future (1 day of time-zone slack), not before 1900. */
const dateOfBirth = nullableField(
  isoDate
    .refine((d) => d.getTime() <= Date.now() + DAY_MS, 'Date of birth cannot be in the future')
    .refine((d) => d.getUTCFullYear() >= OLDEST_BIRTH_YEAR, 'Invalid date of birth'),
);

/**
 * Free-text "company title" (e.g. *Finance Head*), ≤ 80 chars, NFC. Blank — including text made
 * only of invisible characters — becomes null. No control / bidi-override characters or lone surrogates.
 */
const designation = nullableField(
  z
    .string({ error: 'Designation must be text' })
    .transform((v) => v.normalize('NFC').trim())
    .pipe(
      z
        .string()
        .max(LIMITS.DESIGNATION_MAX, `Designation must be at most ${LIMITS.DESIGNATION_MAX} characters`)
        .refine((v) => !FORBIDDEN_TEXT_CHARS.test(v) && isWellFormed(v), 'Designation contains characters that are not allowed'),
    )
    .transform((v) => (v.replace(INVISIBLE_CHARS, '') === '' ? null : v)),
);

const role = z.enum(ROLES, { error: 'Must be admin or member' });
const guardianConsent = z.boolean({ error: 'Must be true or false' });

/**
 * `POST /family/members` (admin). Contract body plus the optional `avatarUrl` (Cloudinary only),
 * so the app can save the photo in the same request. `role` defaults to `member`,
 * `guardianConsent` to `false`.
 */
export const addMemberBody = z.strictObject({
  name,
  email: nullableEmail,
  phone: nullablePhone,
  avatarUrl: nullableCloudinaryUrl,
  dateOfBirth,
  gender: nullableGender,
  designation,
  role: nullableField(role),
  guardianConsent: nullableField(guardianConsent),
});

/**
 * `PATCH /family/members/:id`. Admins may send every field; a non-admin only `SELF_EDITABLE_FIELDS`
 * on themselves (checked by the service, `403 FORBIDDEN`). `name`, `role` and `guardianConsent`
 * cannot be null. `locationSharing` is not here: only the member chooses it (`PATCH /me`).
 */
export const updateMemberBody = z.strictObject({
  name: name.optional(),
  email: nullableEmail,
  phone: nullablePhone,
  avatarUrl: nullableCloudinaryUrl,
  dateOfBirth,
  gender: nullableGender,
  designation,
  role: role.optional(),
  guardianConsent: guardianConsent.optional(),
});

/** Fields a member who is not an admin may change on their own profile (contract §6). */
export const SELF_EDITABLE_FIELDS = Object.freeze(['name', 'phone', 'avatarUrl', 'gender', 'dateOfBirth']);

/** `:id` of `/family/members/:id` (malformed → 400 BAD_REQUEST). */
export const memberIdParams = idParams;
