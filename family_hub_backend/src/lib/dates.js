/**
 * Time-zone aware date helpers (docs/06-BACKEND_GUIDE.md rule 8).
 *
 * Dates are stored in UTC. "This month", "today" and "this week" are evaluated in the
 * **family time zone** (IANA name, e.g. `Asia/Kolkata`) using only `Intl.DateTimeFormat`
 * (no extra dependencies). All ranges are half-open: `{ start (inclusive), end (exclusive) }`
 * → query with `{ $gte: start, $lt: end }`. DST transitions are handled.
 */

const DAY_MS = 24 * 60 * 60 * 1000;
export const DEFAULT_TIME_ZONE = 'UTC';

const formatterCache = new Map();

function formatter(timeZone) {
  let f = formatterCache.get(timeZone);
  if (!f) {
    f = new Intl.DateTimeFormat('en-US', {
      timeZone,
      hourCycle: 'h23',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
      weekday: 'short',
    });
    formatterCache.set(timeZone, f);
  }
  return f;
}

/** true when `tz` is an IANA time zone known to this runtime. */
export function isValidTimeZone(tz) {
  if (typeof tz !== 'string' || !tz.trim()) return false;
  try {
    formatter(tz);
    return true;
  } catch {
    return false;
  }
}

/** Invalid / missing zones fall back to UTC instead of throwing mid-request. */
function zoneOr(tz) {
  return isValidTimeZone(tz) ? tz : DEFAULT_TIME_ZONE;
}

function toDate(value) {
  const d = value instanceof Date ? value : new Date(value ?? Date.now());
  if (Number.isNaN(d.getTime())) throw new RangeError(`Invalid date: ${value}`);
  return d;
}

const WEEKDAYS = { Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6, Sun: 7 };

/** Date.UTC without its "years 0–99 mean 1900–1999" quirk. */
function utcMs(year, month, day = 1, hour = 0, minute = 0, second = 0) {
  const d = new Date(0);
  d.setUTCFullYear(year, month - 1, day);
  d.setUTCHours(hour, minute, second, 0);
  return d.getTime();
}

/**
 * Wall-clock parts of `date` in `timeZone`.
 * @returns {{ year:number, month:number, day:number, hour:number, minute:number, second:number, weekday:number }}
 *          month 1–12, weekday ISO 1 (Mon) … 7 (Sun)
 */
export function zonedParts(date, timeZone) {
  const parts = formatter(zoneOr(timeZone)).formatToParts(toDate(date));
  const out = {};
  for (const p of parts) {
    if (p.type === 'weekday') out.weekday = WEEKDAYS[p.value];
    else if (p.type !== 'literal') out[p.type] = Number(p.value);
  }
  return out;
}

/** Offset (ms) of `timeZone` from UTC at the instant `date` (e.g. +19800000 for IST). */
export function timeZoneOffsetMs(date, timeZone) {
  const d = toDate(date);
  const p = zonedParts(d, timeZone);
  const asUtc = utcMs(p.year, p.month, p.day, p.hour, p.minute, p.second);
  return asUtc - (d.getTime() - d.getUTCMilliseconds());
}

/**
 * UTC instant of a wall-clock time in `timeZone`. Out-of-range fields roll over
 * (day 32 → next month). Non-existent DST times resolve forward, ambiguous ones to the
 * first occurrence.
 */
export function zonedTimeToUtc({ year, month, day = 1, hour = 0, minute = 0, second = 0 }, timeZone) {
  const tz = zoneOr(timeZone);
  const guess = utcMs(year, month, day, hour, minute, second);
  const offset1 = timeZoneOffsetMs(guess, tz);
  let result = guess - offset1;
  const offset2 = timeZoneOffsetMs(result, tz);
  if (offset2 !== offset1) {
    const alt = guess - offset2;
    // Prefer the candidate that maps back to the requested wall-clock time.
    result = timeZoneOffsetMs(alt, tz) === offset2 ? alt : Math.max(result, alt);
  }
  return new Date(result);
}

/** Local midnight (as a UTC Date) of the day containing `date` in `timeZone`. */
export function startOfDay(date = new Date(), timeZone = DEFAULT_TIME_ZONE) {
  const p = zonedParts(date, timeZone);
  return zonedTimeToUtc({ year: p.year, month: p.month, day: p.day }, timeZone);
}

/** Local midnight of the day after the one containing `date`. */
export function startOfNextDay(date = new Date(), timeZone = DEFAULT_TIME_ZONE) {
  const p = zonedParts(date, timeZone);
  return zonedTimeToUtc({ year: p.year, month: p.month, day: p.day + 1 }, timeZone);
}

/** Local midnight of the Monday of the week containing `date` (ISO week). */
export function startOfWeek(date = new Date(), timeZone = DEFAULT_TIME_ZONE) {
  const p = zonedParts(date, timeZone);
  return zonedTimeToUtc({ year: p.year, month: p.month, day: p.day - (p.weekday - 1) }, timeZone);
}

/** `{ start, end }` of the local day containing `date`. */
export function dayRange(date = new Date(), timeZone = DEFAULT_TIME_ZONE) {
  return { start: startOfDay(date, timeZone), end: startOfNextDay(date, timeZone) };
}

/** `{ start, end }` of the local Monday-based week containing `date`. */
export function weekRange(date = new Date(), timeZone = DEFAULT_TIME_ZONE) {
  const p = zonedParts(date, timeZone);
  const monday = p.day - (p.weekday - 1);
  return {
    start: zonedTimeToUtc({ year: p.year, month: p.month, day: monday }, timeZone),
    end: zonedTimeToUtc({ year: p.year, month: p.month, day: monday + 7 }, timeZone),
  };
}

const MONTH_RE = /^(\d{4})-(0[1-9]|1[0-2])$/;

export function isMonthString(value) {
  return typeof value === 'string' && MONTH_RE.test(value);
}

/**
 * `{ start, end }` of a calendar month (`YYYY-MM`) in `timeZone`.
 * @throws {RangeError} for a malformed month (validate with zod `monthString` first)
 */
export function monthRange(month, timeZone = DEFAULT_TIME_ZONE) {
  const m = MONTH_RE.exec(month ?? '');
  if (!m) throw new RangeError(`Invalid month (expected YYYY-MM): ${month}`);
  const year = Number(m[1]);
  const mon = Number(m[2]);
  return {
    start: zonedTimeToUtc({ year, month: mon, day: 1 }, timeZone),
    end: zonedTimeToUtc({ year, month: mon + 1, day: 1 }, timeZone),
  };
}

/** Current month (`YYYY-MM`) in `timeZone`. */
export function currentMonth(timeZone = DEFAULT_TIME_ZONE, now = new Date()) {
  const p = zonedParts(now, timeZone);
  return `${p.year}-${String(p.month).padStart(2, '0')}`;
}

/**
 * Age in completed years at `now`. When `timeZone` is given, both dates are read as
 * wall-clock dates in that zone (date-only fields are sent as local midnight → UTC, so
 * reading them in the family zone avoids off-by-one-day birthdays).
 * @returns {number|null} null when `dob` is missing/invalid
 */
export function ageFrom(dob, now = new Date(), timeZone = DEFAULT_TIME_ZONE) {
  if (dob === null || dob === undefined) return null;
  const birth = dob instanceof Date ? dob : new Date(dob);
  if (Number.isNaN(birth.getTime())) return null;
  const b = zonedParts(birth, timeZone);
  const n = zonedParts(toDate(now), timeZone);
  let age = n.year - b.year;
  if (n.month < b.month || (n.month === b.month && n.day < b.day)) age -= 1;
  return Math.max(0, age);
}

/** Adds whole days (24 h) to an instant. For local-calendar days use startOfNextDay. */
export function addDays(date, days) {
  return new Date(toDate(date).getTime() + days * DAY_MS);
}

/** Adds milliseconds to an instant. */
export function addMs(date, ms) {
  return new Date(toDate(date).getTime() + ms);
}

/** ISO-8601 string or null. */
export function toIso(value) {
  if (value === null || value === undefined) return null;
  const d = value instanceof Date ? value : new Date(value);
  return Number.isNaN(d.getTime()) ? null : d.toISOString();
}
