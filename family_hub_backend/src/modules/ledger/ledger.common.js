import { isAdmin, sameId } from '../../lib/access.js';
import { ApiError } from '../../lib/ApiError.js';
import { DEFAULT_TIME_ZONE, addMs, isValidTimeZone, startOfDay, zonedParts, zonedTimeToUtc } from '../../lib/dates.js';
import { Family } from '../../models/index.js';
import { isDateOnly } from './ledger.schemas.js';

/**
 * Helpers shared by the ledger and goals services (docs/03-API_CONTRACT.md §8).
 *
 * Business dates (`LedgerEntry.date`, `Goal.targetDate`) are stored as **family-local midnight**
 * in UTC (docs/04-DATA_MODELS.md), so month ranges in the family time zone (`lib/dates.js#monthRange`)
 * put every entry in the month the family sees:
 *   - `YYYY-MM-DD`            → midnight of that day in the family time zone;
 *   - an ISO date-time        → the nearest family-local midnight. The app sends "local midnight →
 *     UTC" from the phone's zone, which usually *is* the family zone (no change); a phone travelling
 *     up to ±12 h away still lands on the intended day. (Same idea as the app's `calendarDate`,
 *     which rounds to the nearest UTC midnight.)
 * The accepted window is 2000-01-01 … tomorrow in the family time zone (contract: `date ≤ today +
 * 1 day`, the extra day absorbs phone/family time-zone differences).
 */

const HALF_DAY_MS = 12 * 60 * 60 * 1000;

/** Earliest business day accepted for ledger entries and goal target dates (matches the app's date picker). */
export const FIRST_ENTRY_DAY = Object.freeze({ year: 2000, month: 1, day: 1 });
/** Latest goal target date (same upper bound as task due dates). */
export const LAST_TARGET_DAY = Object.freeze({ year: 2100, month: 12, day: 31 });

/** `{ timeZone, currency }` of the caller's family (invalid zone → UTC). */
export async function familySettings(familyId) {
  const family = await Family.findById(familyId).select('timezone currency').lean();
  if (!family) throw ApiError.noFamily();
  return {
    timeZone: isValidTimeZone(family.timezone) ? family.timezone : DEFAULT_TIME_ZONE,
    currency: family.currency,
  };
}

/**
 * Validated business date (string `YYYY-MM-DD` or Date, see ledger.schemas.js#businessDate) →
 * family-local midnight as a UTC Date. null / undefined pass through.
 */
export function resolveBusinessDate(value, timeZone) {
  if (value === null || value === undefined) return value;
  if (isDateOnly(value)) {
    const [year, month, day] = value.split('-').map(Number);
    return zonedTimeToUtc({ year, month, day }, timeZone);
  }
  const p = zonedParts(addMs(value, HALF_DAY_MS), timeZone);
  return zonedTimeToUtc({ year: p.year, month: p.month, day: p.day }, timeZone);
}

/** `{ min, max }` (both inclusive, family-local midnights) of the allowed entry dates at `now`. */
export function entryDateWindow(timeZone, now = new Date()) {
  const today = zonedParts(now, timeZone);
  return {
    min: zonedTimeToUtc(FIRST_ENTRY_DAY, timeZone),
    max: zonedTimeToUtc({ year: today.year, month: today.month, day: today.day + 1 }, timeZone),
  };
}

/** Today's business date (family-local midnight) — default date of a goal contribution. */
export function todayIn(timeZone, now = new Date()) {
  return startOfDay(now, timeZone);
}

/**
 * Collects service-level validation problems so one response reports all of them
 * (422 VALIDATION_ERROR, `details` = field → English message). The top-level message is the
 * specific translated one (`ledger.errors.*`) when there is a single problem, else the generic one.
 */
export class ValidationIssues {
  constructor() {
    this.details = {};
    this.keys = [];
  }

  add(field, message, messageKey) {
    if (this.details[field]) return this;
    this.details[field] = message;
    this.keys.push(messageKey);
    return this;
  }

  has(field) {
    return field === undefined ? this.keys.length > 0 : Boolean(this.details[field]);
  }

  throwIfAny() {
    if (!this.keys.length) return;
    const messageKey = this.keys.length === 1 ? this.keys[0] : undefined;
    throw ApiError.validation(this.details, 'Validation failed', messageKey ? { messageKey } : {});
  }
}

/**
 * Resolves `value` for `field` and checks the entry-date window; adds an issue when it is out of range.
 * @returns {Date|undefined} the resolved date (undefined when invalid or not given)
 */
export function resolveEntryDate(value, field, { timeZone, issues, now = new Date() }) {
  if (value === null || value === undefined) return undefined;
  const date = resolveBusinessDate(value, timeZone);
  const { min, max } = entryDateWindow(timeZone, now);
  if (date.getTime() > max.getTime()) {
    issues.add(field, 'Date cannot be later than tomorrow', 'ledger.errors.dateInFuture');
    return undefined;
  }
  if (date.getTime() < min.getTime()) {
    issues.add(field, 'Date cannot be before 1 January 2000', 'ledger.errors.dateTooOld');
    return undefined;
  }
  return date;
}

/**
 * Resolves a goal `targetDate` (null clears it) and checks the family-local day is within
 * 2000-01-01 … 2100-12-31 — the zod block only bounds the UTC instant, so e.g. `1999-12-31` would
 * otherwise be stored. Past days are allowed (an existing goal may be overdue).
 * @returns {Date|null|undefined} the resolved date, null to clear it, undefined when invalid / not given
 */
export function resolveTargetDate(value, field, { timeZone, issues }) {
  if (value === null || value === undefined) return value;
  const date = resolveBusinessDate(value, timeZone);
  const min = zonedTimeToUtc(FIRST_ENTRY_DAY, timeZone);
  const max = zonedTimeToUtc(LAST_TARGET_DAY, timeZone);
  if (date.getTime() < min.getTime() || date.getTime() > max.getTime()) {
    issues.add(field, 'Date must be between 1 January 2000 and 31 December 2100', 'ledger.errors.targetDateRange');
    return undefined;
  }
  return date;
}

// ---------------------------------------------------------------- visibility

/** Admins see every entry; members those they own (`memberId`) or created (contract §8). */
export function canSeeEntry(actor, entry) {
  return (
    isAdmin({ user: actor }) || sameId(entry.memberId, actor.memberId) || sameId(entry.createdById, actor.memberId)
  );
}

/** Mongo filter part implementing canSeeEntry (empty for admins). */
export function visibilityFilter(actor) {
  if (isAdmin({ user: actor })) return {};
  return { $or: [{ memberId: actor.memberId }, { createdById: actor.memberId }] };
}

/** Admin or the entry's creator may edit / delete it. */
export function canModifyEntry(actor, entry) {
  return isAdmin({ user: actor }) || sameId(entry.createdById, actor.memberId);
}
