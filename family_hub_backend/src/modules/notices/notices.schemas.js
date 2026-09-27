import { z } from 'zod';
import { LIMITS } from '../../lib/constants.js';
import { cloudinaryUrl, idParams, nullableField, paginationQuery } from '../../lib/validate.js';
import { hasVisibleText, toMultiLine, toSingleLine } from '../tasks/tasks.schemas.js';

/**
 * Validation for `/notices` (docs/03-API_CONTRACT.md §9).
 *
 * Body rules (the app sends explicit `null` to clear a field, see lib/validate.js#nullableField):
 *   - title: single line (every run of control characters, incl. line breaks / tabs / NUL → one
 *     space), trimmed, 1–100 UTF-16 code units, at least one visible character (letter, digit,
 *     symbol / emoji or punctuation — a title of only zero-width / format characters is "blank").
 *     Required on POST, optional on PATCH but never null / blank.
 *   - body: multi-line (CRLF / CR → LF; control characters other than `\n` / `\t` removed), trimmed,
 *     1–2000 UTF-16 code units, at least one visible character; same presence rules as title.
 *   - Text is made well-formed UTF-16 first (a lone surrogate → U+FFFD, exactly what MongoDB would
 *     store), so the response always equals what was saved. Scripts, emoji, RTL text and bidi marks
 *     are kept as typed (same rules as task titles / descriptions, tasks.schemas.js).
 *   - Lengths are counted in UTF-16 code units like the Notice model (`maxlength`) and the app's
 *     validator (Dart `String.length`). zod 4's `.max()` counts code points, so an emoji-heavy title
 *     would pass zod and then fail in Mongoose with a raw message that echoes the whole input.
 *   - imageUrl: https URL on res.cloudinary.com (contract §12) without user info (`user@`) or an
 *     explicit port, stored in its canonical WHATWG form (e.g. `\` → `/`, spaces → `%20`) so every
 *     URL parser that later reads it sees the same host; ≤ 1024 characters after canonicalisation.
 *     null / '' → no image (PATCH: removes it).
 *   - pinned: a real JSON boolean (no `"true"` / `1` coercion). Who may set it is the service's job:
 *     POST silently ignores it for non-admins, PATCH answers 403 when a non-admin changes it.
 *   - Unknown keys (`authorId`, `familyId`, `createdAt`, `$set`, …) are stripped, so they can never
 *     be forged; object / array values for known keys are 422 (no operator injection).
 *
 * Query (`GET /notices`): `?page&limit` (contract §1 pagination).
 */

const isMissing = (issue) => issue.input === undefined || issue.input === null;

/** `value.length <= max` — UTF-16 code units, the unit of the model's `maxlength` and of the app. */
const maxUnits = (max, message) => [(value) => value.length <= max, message];

/**
 * Required text with contract length bounds and field-specific messages.
 * @param {string} label   field name used in the messages
 * @param {number} max     UTF-16 code units
 * @param {(value: string) => string} normalise  toSingleLine | toMultiLine
 */
function requiredText(label, max, normalise) {
  return z
    .string({ error: (issue) => (isMissing(issue) ? `${label} is required` : `${label} must be text`) })
    .overwrite(normalise)
    .trim()
    .min(1, `${label} is required`)
    .refine(hasVisibleText, `${label} is required`)
    .refine(...maxUnits(max, `${label} must be at most ${max} characters`));
}

const title = requiredText('Title', LIMITS.NOTICE_TITLE_MAX, toSingleLine);
const body = requiredText('Body', LIMITS.NOTICE_BODY_MAX, toMultiLine);
const pinned = z.boolean({ error: 'Pinned must be true or false' });

/** true when the URL has no `user:pass@` part and no explicit port (a Cloudinary secure_url never has either). */
function hasPlainAuthority(value) {
  try {
    const url = new URL(value);
    return !url.username && !url.password && !url.port;
  } catch {
    return false;
  }
}

/**
 * Notice image: the shared `cloudinaryUrl` rule (https, host res.cloudinary.com, ≤ 1024) plus a plain
 * authority, returned as the canonical `URL#href`.
 */
const imageUrl = nullableField(
  cloudinaryUrl
    .refine(hasPlainAuthority, 'Image must be hosted on res.cloudinary.com')
    .transform((value) => new URL(value).href)
    .refine(...maxUnits(LIMITS.URL_MAX, `Image URL must be at most ${LIMITS.URL_MAX} characters`)),
);

export const noticeIdParams = idParams;

/** `GET /notices?page&limit` */
export const listNoticesQuery = paginationQuery;

/** `POST /notices` */
export const createNoticeBody = z.object({
  title,
  body,
  imageUrl,
  pinned: pinned.optional(),
});

/** `PATCH /notices/:id` — every field optional; only the keys present are changed. */
export const updateNoticeBody = z.object({
  title: title.optional(),
  body: body.optional(),
  imageUrl,
  pinned: pinned.optional(),
});
