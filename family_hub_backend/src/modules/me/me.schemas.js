import { z } from 'zod';
import { DEVICE_PLATFORMS, LOCATION_SHARING } from '../../lib/constants.js';
import {
  isoDate,
  latLng,
  locale,
  nullableCloudinaryUrl,
  nullableField,
  nullableGender,
  nullablePhone,
  personName,
} from '../../lib/validate.js';

/**
 * Request schemas of `/me/*` (docs/03-API_CONTRACT.md §5), built from the shared zod blocks.
 *
 * `PATCH /me` is **strict**: unknown keys (e.g. `role`, `designation`, `email`) are rejected with
 * `422 VALIDATION_ERROR` instead of being silently dropped, so a client never believes it changed
 * something it cannot change here (same behaviour as the Flutter mock backend).
 * Nullable fields follow the shared PATCH rule: absent → unchanged, `null`/blank → cleared.
 */

const DAY_MS = 24 * 60 * 60 * 1000;
const OLDEST_BIRTH_YEAR = 1900;

/** Same rules as the register body: not in the future (1 day of time-zone slack), not before 1900. */
const dateOfBirth = nullableField(
  isoDate
    .refine((d) => d.getTime() <= Date.now() + DAY_MS, 'Date of birth cannot be in the future')
    .refine((d) => d.getUTCFullYear() >= OLDEST_BIRTH_YEAR, 'Invalid date of birth'),
);

const locationSharing = z.enum(LOCATION_SHARING, { error: 'Must be never, sos_only or always' });

/** C0/C1 control characters (NUL, tab, line breaks …) never belong in a display name. */
const CONTROL_CHAR = /\p{Cc}/u;
/**
 * Bidi embedding / override / isolate controls (U+202A–U+202E, U+2066–U+2069) reorder the text
 * around them, so "\u202Enimda" is displayed as "admin" (spoofing in member lists and pushes).
 * Keyboards never type them; the plain marks LRM / RLM / ALM stay allowed.
 */
const BIDI_CONTROL = /[\u202A-\u202E\u2066-\u2069]/u;
/** A character that is drawn: not a separator, control/format/private/unassigned code point or lone mark. */
const VISIBLE_CHAR = /[^\p{Z}\p{C}\p{M}]/u;

/**
 * Display name for `PATCH /me`: the shared `personName` (trimmed, 1–60) plus rules against
 * names that render as nothing (`"\u200B"`) or break lists, pushes and e-mails (control and
 * text-direction characters). Scripts, emoji and RTL text are kept exactly as sent.
 */
export const profileName = personName
  .refine((v) => !CONTROL_CHAR.test(v), 'Name cannot contain line breaks or control characters')
  .refine((v) => !BIDI_CONTROL.test(v), 'Name cannot contain text-direction control characters')
  .refine((v) => VISIBLE_CHAR.test(v), 'Name must contain a visible character');

export const updateMeSchema = z.strictObject({
  name: profileName.optional(),
  phone: nullablePhone,
  avatarUrl: nullableCloudinaryUrl,
  locale: locale.optional(),
  locationSharing: locationSharing.optional(),
  gender: nullableGender,
  dateOfBirth,
});

/** `{ lat, lng, accuracy? }` — lat −90..90, lng −180..180, accuracy ≥ 0 (plain numbers, no coercion). */
export const updateLocationSchema = latLng;

/** FCM registration token: printable ASCII without spaces, at most 4096 chars (Device model limit). */
const deviceToken = z
  .string({ error: 'Device token is required' })
  .trim()
  .min(1, 'Device token is required')
  .max(4096, 'Device token is too long')
  .regex(/^[\x21-\x7E]+$/, 'Invalid device token');

export const registerDeviceSchema = z.object({
  token: deviceToken,
  platform: z.enum(DEVICE_PLATFORMS, { error: 'Must be android or ios' }),
  /** Language of the app on this device; absent/null → pushes use the account locale. */
  locale: nullableField(locale),
});

export const deviceTokenParams = z.object({ token: deviceToken });

/** The current password, never re-checked against the password rules (only bounded). */
export const deleteMeSchema = z.object({
  password: z.string({ error: 'Password is required' }).min(1, 'Password is required').max(128, 'Password is too long'),
});
