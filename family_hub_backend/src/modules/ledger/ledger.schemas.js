import { z } from 'zod';
import { ALL_LEDGER_CATEGORIES, LEDGER_TYPES, LIMITS, isLedgerCategoryFor } from '../../lib/constants.js';
import {
  idParams,
  isIsoDateString,
  moneyAmount,
  monthString,
  nullableField,
  objectId,
  pagination,
} from '../../lib/validate.js';
import { hasVisibleText, toMultiLine } from '../tasks/tasks.schemas.js';

/**
 * Validation for `/ledger/*` (docs/03-API_CONTRACT.md §8). Blocks shared with `/goals`
 * (dates, notes, amounts, text lengths) live here too so both routers validate them identically.
 *
 * Body rules (the app sends explicit `null` to clear a field, see lib/validate.js#nullableField):
 *   - type: `income | expense`.
 *   - amount: number (no strings), > 0, ≤ 1e12, at least 0.01 after rounding to 2 decimals.
 *   - category: one of the contract categories **and** valid for the type (`details.category`).
 *     On PATCH the pair is checked here when both are sent, otherwise by the service against the
 *     stored value.
 *   - note: multi-line text (same rules as task descriptions / notice bodies, tasks.schemas.js):
 *     well-formed UTF-16 (a lone surrogate → U+FFFD, exactly what MongoDB stores, so the response
 *     equals what was saved), CRLF → LF, other control characters (NUL, BEL, …) removed, trimmed,
 *     ≤ 200 **UTF-16 code units** (the unit of the model's `maxlength` and of the app's validator —
 *     zod 4's `.max()` counts code points, so 150 emoji would pass zod and then fail in Mongoose with
 *     a raw message echoing the text). Null / blank / only invisible characters → null (PATCH: clears it).
 *     Scripts, emoji, RTL text and bidi marks are kept as typed.
 *   - date: `YYYY-MM-DD` or an ISO date-time with `Z`/offset (the app sends local midnight → UTC).
 *     Coarse range here (1999-12-31 … 2100-12-31 UTC); the service resolves the business day in the
 *     family time zone and enforces the exact window 2000-01-01 … tomorrow (contract: `≤ today + 1 day`).
 *   - memberId: whose money it is. POST: absent / null → the caller. PATCH: optional, never null.
 *   - Unknown keys (`goalId`, `createdById`, `familyId`, `amountMinor`, …) are stripped: goal links are
 *     only created by `POST /goals/:id/contributions`.
 *
 * Query rules: blank values count as "not given".
 */

const isMissing = (issue) => issue.input === undefined;

/** `YYYY-MM-DD` (a calendar day, resolved in the family time zone by the service). */
const DATE_ONLY = /^\d{4}-\d{2}-\d{2}$/;

/** true for a date-only `YYYY-MM-DD` string. */
export const isDateOnly = (value) => typeof value === 'string' && DATE_ONLY.test(value);

/**
 * Coarse accepted window for business dates (UTC instants). 1999-12-31 leaves room for
 * "2000-01-01 local midnight" in zones east of UTC; the exact bounds are checked by the service.
 */
export const LEDGER_DATE_MIN = new Date('1999-12-31T00:00:00.000Z');
export const LEDGER_DATE_MAX = new Date('2101-01-01T00:00:00.000Z');

export const ledgerType = z.enum(LEDGER_TYPES, {
  error: (issue) => (isMissing(issue) ? 'Type is required' : `Type must be one of: ${LEDGER_TYPES.join(', ')}`),
});

export const ledgerCategory = z.enum(ALL_LEDGER_CATEGORIES, {
  error: (issue) => (isMissing(issue) ? 'Category is required' : 'Unknown category'),
});

/** Money in major units (lib/validate.js#moneyAmount) with a "required" message for a missing key. */
export const amount = z.any().superRefine((value, ctx) => {
  if (value === undefined) ctx.addIssue({ code: 'custom', message: 'Amount is required' });
}).pipe(moneyAmount);

/**
 * `[check, message]` for `.refine(...)`: at most `max` UTF-16 code units (Mongoose `maxlength`,
 * Dart `String.length`), unlike zod's code-point based `.max()`.
 */
export const maxUnits = (max, message) => [(value) => value.length <= max, message];

/**
 * Optional multi-line free text (ledger notes, goal descriptions): see "note" in the header.
 * @param {string} label  field name used in the messages
 * @param {number} max    UTF-16 code units
 */
export function optionalMultiLineText(label, max) {
  return nullableField(
    z
      .string({ error: `${label} must be text` })
      .overwrite(toMultiLine)
      .trim()
      .refine(...maxUnits(max, `${label} must be at most ${max} characters`))
      .transform((value) => (hasVisibleText(value) ? value : null)),
  );
}

export const note = optionalMultiLineText('Note', LIMITS.LEDGER_NOTE_MAX);

/**
 * Business date: `YYYY-MM-DD` stays a string (the service turns it into family-local midnight);
 * a date-time becomes a `Date` (the service snaps it to the nearest family-local midnight).
 */
export const businessDate = z
  .string({ error: (issue) => (isMissing(issue) ? 'Date is required' : 'Invalid date') })
  .trim()
  .refine(isIsoDateString, 'Invalid date')
  .refine((v) => {
    const time = new Date(v).getTime();
    return time >= LEDGER_DATE_MIN.getTime() && time < LEDGER_DATE_MAX.getTime();
  }, 'Date must be between 2000 and 2100')
  .transform((v) => (isDateOnly(v) ? v : new Date(v)));

/** Optional business date; null / blank → null. */
export const nullableBusinessDate = nullableField(businessDate);

/**
 * Object-level check "category is valid for type" — only when both values are well-formed
 * (zod still runs object refinements when a property failed, so the inputs are guarded).
 */
function categoryMatchesType(value, ctx) {
  const { type, category } = value ?? {};
  if (!LEDGER_TYPES.includes(type) || !ALL_LEDGER_CATEGORIES.includes(category)) return;
  if (!isLedgerCategoryFor(type, category)) {
    ctx.addIssue({ code: 'custom', path: ['category'], message: categoryMessage(type, category) });
  }
}

/** English detail for a category that does not belong to `type`. */
export function categoryMessage(type, category) {
  return `Category "${category}" is not valid for ${type} entries`;
}

export const entryIdParams = idParams;

/** `POST /ledger/entries` */
export const createEntryBody = z
  .object({
    type: ledgerType,
    amount,
    category: ledgerCategory,
    note,
    date: businessDate,
    memberId: nullableField(objectId),
  })
  .superRefine(categoryMatchesType);

/** `PATCH /ledger/entries/:id` — every field optional; only the keys present are considered. */
export const updateEntryBody = z
  .object({
    type: ledgerType.optional(),
    amount: moneyAmount.optional(),
    category: ledgerCategory.optional(),
    note,
    date: businessDate.optional(),
    memberId: z.string({ error: 'Invalid member' }).pipe(objectId).optional(),
  })
  .superRefine(categoryMatchesType);

/** `GET /ledger/entries?month=YYYY-MM&type=&memberId=&goalId=&page&limit` */
export const listEntriesQuery = z.object({
  month: nullableField(monthString),
  type: nullableField(ledgerType),
  memberId: nullableField(objectId),
  goalId: nullableField(objectId),
  ...pagination,
});

/** `GET /ledger/summary?month=YYYY-MM` (absent → current month in the family time zone). */
export const summaryQuery = z.object({
  month: nullableField(monthString),
});
