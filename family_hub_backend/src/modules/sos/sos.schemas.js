import { z } from 'zod';
import { LIMITS, SOS_RESOLUTIONS } from '../../lib/constants.js';
import { idParams, latLng, pagination } from '../../lib/validate.js';

/**
 * Request schemas of `/sos` (docs/03-API_CONTRACT.md §10), built from the shared zod blocks.
 *
 * Bodies are **lenient on purpose**: unknown keys are stripped rather than rejected, so an SOS
 * never fails because an older / newer app version sends an extra field. The same stripping is
 * the mass-assignment guard: `status`, `memberId`, `familyId`, `expiresAt`, `recordedAt`,
 * `resolvedById`, `$set`, `__proto__` … can never reach the database. Coordinates use the shared
 * `latLng` block (plain finite numbers only: `"12"`, `null`, `true`, `1e400` are rejected, never
 * coerced).
 *
 * `message` clean-up (`cleanSosMessage`), applied before the length check:
 *   - made well-formed UTF-16 (a lone surrogate → U+FFFD, exactly what MongoDB would store, so the
 *     response equals what was saved; an SOS never fails because of a broken emoji);
 *   - line breaks (CRLF, CR, VT, FF, NEL, U+2028/9) → `\n`, tabs → one space, every other C0/C1
 *     control character (NUL, BEL, ESC …) removed;
 *   - bidi embedding / override / isolate controls (U+202A–U+202E, U+2066–U+2069, "Trojan Source"
 *     spoofing on relatives' screens) removed; LRM / RLM marks, ZWJ / ZWNJ, RTL and Indic text and
 *     emoji sequences are kept;
 *   - NFC, trimmed (also a leading / trailing ZWSP, word joiner or BOM);
 *   - nothing visible left (only spaces / zero-width / format characters) → `null`.
 *
 * Length: at most `LIMITS.SOS_MESSAGE_MAX` (140) **UTF-16 code units** (`String#length`), the unit
 * of the SosAlert model's `maxlength` and of the app's `Validators.maxLength` (Dart `String.length`).
 * zod 4's own `.max()` counts code points, so 71–140 emoji used to pass zod and then fail in
 * Mongoose with a raw message that echoed the (possibly health-related) text back.
 */

/** `:id` of an alert — malformed → 400 BAD_REQUEST (validate.js rule for params). */
export const sosIdParams = idParams;

const LINE_BREAKS = /\r\n?|[\v\f\u0085\u2028\u2029]/g;
/** C0/C1 control characters except LF (tabs are turned into spaces first). */
const CONTROLS_EXCEPT_LF = /[^\P{Cc}\n]/gu;
const BIDI_CONTROLS = /[\u202A-\u202E\u2066-\u2069]/g;
/** Leading / trailing whitespace plus the invisible zero-width space / word joiner / BOM. */
const EDGE_BLANKS = /^[\s\u200B\u2060\uFEFF]+|[\s\u200B\u2060\uFEFF]+$/g;
/**
 * A character that renders as something: anything except whitespace, controls, format characters
 * (ZWSP, ZWJ, LRM, …), variation selectors and the blank-looking Hangul fillers / Braille blank.
 */
const VISIBLE_CHAR = /[^\s\p{Cc}\p{Cf}\uFE00-\uFE0F\u115F\u1160\u3164\uFFA0\u2800]/u;

/**
 * SOS message as typed → as stored (see the file header). `null` for blank / invisible-only text;
 * non-strings are returned unchanged so the schema reports them.
 * @param {unknown} value
 * @returns {unknown}
 */
export function cleanSosMessage(value) {
  if (typeof value !== 'string') return value;
  const text = value
    .toWellFormed()
    .replace(LINE_BREAKS, '\n')
    .replace(/\t/g, ' ')
    .replace(CONTROLS_EXCEPT_LF, '')
    .replace(BIDI_CONTROLS, '')
    .normalize('NFC')
    .replace(EDGE_BLANKS, '');
  return VISIBLE_CHAR.test(text) ? text : null;
}

const MESSAGE_TOO_LONG = `Message must be at most ${LIMITS.SOS_MESSAGE_MAX} characters`;

/** Optional SOS message: absent stays absent, null / blank / invisible → null, else ≤ 140 UTF-16 units. */
const sosMessage = z.preprocess(
  cleanSosMessage,
  z
    .string({ error: 'Message must be text' })
    .refine((value) => value.length <= LIMITS.SOS_MESSAGE_MAX, MESSAGE_TOO_LONG)
    .nullable()
    .optional(),
);

/**
 * `POST /sos` — `{ location?: { lat, lng, accuracy? }, message?(≤140) }`. An empty / missing body is
 * valid (one-tap SOS without a fix). `location: null` = no fix. Location points are always stamped
 * with server time; a client `recordedAt` is ignored.
 */
export const createSosBody = z.object(
  {
    location: latLng.nullish(),
    message: sosMessage,
  },
  { error: 'Expected an object' },
);

/** `POST /sos/:id/location` — `{ lat, lng, accuracy? }` (extra keys such as `recordedAt` are stripped). */
export const sosLocationBody = latLng;

/** `POST /sos/:id/resolve` — `{ resolution: "safe" | "false_alarm" | "helped" }`. */
export const resolveSosBody = z.object(
  {
    resolution: z.enum(SOS_RESOLUTIONS, { error: `Must be one of ${SOS_RESOLUTIONS.join(', ')}` }),
  },
  { error: 'Expected an object' },
);

/** `GET /sos/history?page&limit` (contract §1 pagination; unknown query keys are ignored). */
export const sosHistoryQuery = z.object({ ...pagination });
