import { z } from 'zod';
import { ApiError } from './ApiError.js';
import {
  CLOUDINARY_HOST,
  DEFAULT_PAGE,
  DEFAULT_PAGE_LIMIT,
  GENDERS,
  INVITE_CODE_INPUT_REGEX,
  LIMITS,
  LOCALES,
  MAX_PAGE_LIMIT,
} from './constants.js';
import { isCountry, isCurrency } from './countries.js';
import { isValidTimeZone } from './dates.js';
import { MAX_AMOUNT, isValidAmount } from './money.js';

/**
 * Express middleware validating `req.params`, `req.query`, `req.body` with zod schemas.
 * Parsed values are stored on `req.valid = { params, query, body }` (Express 5 makes
 * `req.query` read-only, so never reassign it). Several `validate()` calls on one route
 * merge into the same `req.valid`.
 *
 *   router.post('/', validate({ body: createTaskSchema }), controller.create)
 *   // in controller: const { title } = req.valid.body;
 *
 * Errors (contract §1):
 *   - invalid `params` (e.g. malformed id)  → 400 BAD_REQUEST   with `details`
 *   - invalid `query` / `body`              → 422 VALIDATION_ERROR, `details` = { "field.path": "message" }
 */
export function validate(schemas) {
  return (req, _res, next) => {
    const valid = {};
    const paramDetails = {};
    const details = {};
    for (const part of ['params', 'query', 'body']) {
      const schema = schemas[part];
      if (!schema) continue;
      const input = part === 'body' ? (req.body ?? {}) : (req[part] ?? {});
      const result = schema.safeParse(input);
      if (result.success) {
        valid[part] = result.data;
        continue;
      }
      const target = part === 'params' ? paramDetails : details;
      Object.assign(target, zodIssuesToDetails(result.error.issues, part));
    }
    if (Object.keys(paramDetails).length) {
      return next(ApiError.badRequest('Invalid request parameters', { details: paramDetails }));
    }
    if (Object.keys(details).length) return next(ApiError.validation(details));
    req.valid = { ...(req.valid ?? {}), ...valid };
    next();
  };
}

/** Converts zod issues to `{ "path.to.field": "message" }` (first message per path). */
export function zodIssuesToDetails(issues, fallbackKey = 'body') {
  const details = {};
  for (const issue of issues ?? []) {
    const key = issue.path?.length ? issue.path.join('.') : fallbackKey;
    if (!details[key]) details[key] = issue.message;
  }
  return details;
}

// ---------- Reusable zod building blocks ----------
//
// Optional / nullable fields follow one rule so the same block works for create and PATCH
// bodies (docs/03-API_CONTRACT.md; the app sends explicit `null` to clear a field):
//   key absent            → key absent in `req.valid.body` (PATCH: "leave unchanged")
//   null / '' / '   '     → null                            (PATCH: "clear it")
//   anything else         → validated by the inner schema
// Models default missing fields to null, so create flows need no extra handling.

const blankToNull = (value) => (typeof value === 'string' && value.trim() === '' ? null : value);

/**
 * Makes any schema optional + nullable with the rule above, keeping the inner schema's own
 * error messages, e.g. `nullableField(z.enum(GENDERS))`.
 * @template {z.ZodType} T
 * @param {T} schema
 */
export function nullableField(schema) {
  return z.preprocess(blankToNull, schema.nullable().optional());
}

export const objectId = z
  .string()
  .trim()
  .regex(/^[a-f0-9]{24}$/i, 'Invalid id')
  .transform((v) => v.toLowerCase());

/** Optional member/goal/… reference; `null` clears it. */
export const nullableObjectId = nullableField(objectId);

export const idParams = z.object({ id: objectId });

export const email = z
  .string()
  .trim()
  .toLowerCase()
  .pipe(z.email('Invalid email').max(LIMITS.EMAIL_MAX));

export const nullableEmail = nullableField(email);

/** min 8 chars, at least one letter and one digit. */
export const password = z
  .string()
  .min(8, 'Password must be at least 8 characters')
  .max(128)
  .refine((v) => /\p{L}/u.test(v) && /\d/.test(v), 'Password must contain a letter and a digit');

/** Required trimmed string with min/max length, e.g. `trimmed(1, LIMITS.NAME_MAX)`. */
export const trimmed = (min, max) => z.string().trim().min(min).max(max);

/** Person / family name (contract: 1–60 chars). */
export const personName = trimmed(1, LIMITS.NAME_MAX);

/** Optional free text up to `max` chars (trimmed; blank → null). */
export const optionalText = (max) => nullableField(z.string().trim().max(max));

const isoDateTimeSchema = z.iso.datetime({ offset: true });
const isoDateOnlySchema = z.iso.date();

/**
 * true for `YYYY-MM-DD` or a full ISO-8601 date-time **with** `Z`/offset
 * (`2026-09-26T10:15:00.000Z`, `…+05:30`). Calendar-checked (no 2026-02-31) and never
 * interpreted in the server's local time zone.
 */
export function isIsoDateString(value) {
  return typeof value === 'string' && (isoDateTimeSchema.safeParse(value).success || isoDateOnlySchema.safeParse(value).success);
}

/** ISO date or date-time string → Date (see isIsoDateString). */
export const isoDate = z
  .string()
  .trim()
  .refine(isIsoDateString, 'Invalid date')
  .transform((v) => new Date(v));

export const nullableIsoDate = nullableField(isoDate);

/** YYYY-MM */
export const monthString = z.string().regex(/^\d{4}-(0[1-9]|1[0-2])$/, 'Expected YYYY-MM');

/** Contract §1: `?page=1&limit=20`, page ≥ 1, 1 ≤ limit ≤ 100. Spread into a query schema. */
export const pagination = {
  page: z.coerce.number().int().min(1).default(DEFAULT_PAGE),
  limit: z.coerce.number().int().min(1).max(MAX_PAGE_LIMIT).default(DEFAULT_PAGE_LIMIT),
};

export const paginationQuery = z.object(pagination);

/** One of the supported language codes (`en hi bn …`). */
export const locale = z.enum(LOCALES, { error: 'Unsupported language' });

/** `male | female | other`, or null to clear. */
export const nullableGender = nullableField(z.enum(GENDERS, { error: 'Invalid gender' }));

/** ISO 3166-1 alpha-2 country from the supported list (case-insensitive input). */
export const countryCode = z
  .string()
  .trim()
  .toUpperCase()
  .refine(isCountry, 'Unsupported country');

/** ISO 4217 currency from the supported list (case-insensitive input). */
export const currencyCode = z
  .string()
  .trim()
  .toUpperCase()
  .refine(isCurrency, 'Unsupported currency');

/** IANA time zone, e.g. `Asia/Kolkata`. */
export const timeZone = z.string().trim().min(1).max(LIMITS.TIMEZONE_MAX).refine(isValidTimeZone, 'Invalid time zone');

/**
 * Family invite code as typed by a user: case-insensitive, surrounding/inner spaces and
 * dashes ignored (`"demo-2345"` → `"DEMO2345"`), then 8 letters/digits. Unknown codes are
 * the service's job (`400 INVALID_INVITE_CODE`).
 */
export const inviteCode = z
  .string()
  .transform((v) => v.replace(/[\s-]/g, '').toUpperCase())
  .pipe(z.string().regex(INVITE_CODE_INPUT_REGEX, 'Invite code must be 8 letters or digits'));

/** E.164-ish phone: optional +, 6-15 digits, spaces/dashes/brackets tolerated then stripped. */
export const phone = z
  .string()
  .trim()
  .transform((v) => v.replace(/[\s\-()]/g, ''))
  .pipe(z.string().regex(/^\+?\d{6,15}$/, 'Invalid phone number'));

export const nullablePhone = nullableField(phone);

/** true for an https URL on res.cloudinary.com. */
export function isCloudinaryHostUrl(value) {
  try {
    const u = new URL(value);
    return u.protocol === 'https:' && u.hostname === CLOUDINARY_HOST;
  } catch {
    return false;
  }
}

/** Only Cloudinary-hosted https images are accepted for avatarUrl / imageUrl (contract §12). */
export const cloudinaryUrl = z
  .string()
  .trim()
  .max(LIMITS.URL_MAX)
  .refine(isCloudinaryHostUrl, 'Image must be hosted on res.cloudinary.com');

export const nullableCloudinaryUrl = nullableField(cloudinaryUrl);

/**
 * Money in decimal major units (contract: > 0 and ≤ 1e12, rounded to 2 decimals).
 * Values that round to 0 minor units (e.g. 0.001) are rejected. Convert with `toMinor`.
 */
export const moneyAmount = z
  .number({ error: 'Amount must be a number' })
  .positive('Amount must be greater than 0')
  .max(MAX_AMOUNT, 'Amount is too large')
  .refine(isValidAmount, 'Amount must be at least 0.01');

/**
 * `{ lat, lng, accuracy? }` in a JSON body. Plain numbers only (no coercion: `null`, `''`
 * or `true` must not silently become 0 / 1).
 */
export const latLng = z.object({
  lat: z.number().min(-90).max(90),
  lng: z.number().min(-180).max(180),
  accuracy: z.number().min(0).max(100_000).nullish(),
});
