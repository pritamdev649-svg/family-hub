import { MAX_AMOUNT_MINOR } from './constants.js';

/**
 * Money helpers (docs/06-BACKEND_GUIDE.md rule 7).
 *
 * The API exposes decimal major units rounded to 2 decimals (`1250.5` = ₹1,250.50);
 * the database stores integers in minor units (1/100 of the major unit) so sums are exact.
 * The 2-decimal scale is used for every currency (the contract fixes it), zero-decimal
 * currencies such as JPY simply always have `…00` minor units.
 */

export const MINOR_PER_MAJOR = 100;

/** Contract: amounts are > 0 and ≤ 1e12 major units (models cap `*Minor` at MAX_AMOUNT_MINOR = 1e14). */
export const MAX_AMOUNT = MAX_AMOUNT_MINOR / MINOR_PER_MAJOR;

/**
 * Major → minor units with correct decimal rounding (half away from zero):
 * `toMinor(1.005) === 101` (a naive `Math.round(1.005 * 100)` gives 100).
 * @param {number|string} amount
 * @returns {number} safe integer
 */
export function toMinor(amount) {
  const n = typeof amount === 'string' ? Number(amount.trim()) : amount;
  if (typeof n !== 'number' || !Number.isFinite(n)) {
    throw new TypeError(`Invalid money amount: ${amount}`);
  }
  const sign = n < 0 ? -1 : 1;
  const abs = Math.abs(n);
  const text = String(abs);
  // Shift the decimal point in the string representation to avoid binary float error.
  const shifted = text.includes('e') ? abs * MINOR_PER_MAJOR : Number(`${text}e2`);
  const minor = sign * Math.round(shifted);
  if (!Number.isSafeInteger(minor)) throw new RangeError(`Money amount out of range: ${amount}`);
  return minor === 0 ? 0 : minor; // normalise -0
}

/**
 * Minor → major units as a number with at most 2 decimals. `null`/`undefined` → 0.
 * @param {number|null|undefined} minor
 */
export function fromMinor(minor) {
  if (minor === null || minor === undefined) return 0;
  const n = Number(minor);
  if (!Number.isFinite(n)) return 0;
  const major = Math.round(n) / MINOR_PER_MAJOR;
  return major === 0 ? 0 : major;
}

/** Rounds a major-unit amount to 2 decimals using the same rules as toMinor. */
export function roundMoney(amount) {
  return fromMinor(toMinor(amount));
}

/** Sums minor-unit integers, ignoring null/undefined. */
export function sumMinor(values) {
  let total = 0;
  for (const v of values) if (v !== null && v !== undefined) total += Number(v) || 0;
  return total;
}

/** true for a positive amount ≤ MAX_AMOUNT that survives the 2-decimal conversion (> 0). */
export function isValidAmount(amount) {
  if (typeof amount !== 'number' || !Number.isFinite(amount)) return false;
  if (amount <= 0 || amount > MAX_AMOUNT) return false;
  return toMinor(amount) > 0;
}
