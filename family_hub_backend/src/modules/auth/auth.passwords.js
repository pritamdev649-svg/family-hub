import bcrypt from 'bcryptjs';
import { env } from '../../config/env.js';
import { ApiError } from '../../lib/ApiError.js';
import { BCRYPT_ROUNDS, LOGIN_LOCK_WINDOW_MS, LOGIN_MAX_FAILED_ATTEMPTS } from '../../lib/constants.js';
import { randomToken, sha256 } from '../../lib/crypto.js';
import { User } from '../../models/index.js';

/**
 * Password hashing + login lockout (docs/03-API_CONTRACT.md §4 "Login").
 *
 * - bcrypt cost 12 (10 in tests to keep the suite fast).
 * - Passwords are Unicode-normalised (NFKC, NIST SP 800-63B §5.1.1.2) before hashing and
 *   comparing, so the same password typed on keyboards that emit composed vs. decomposed
 *   characters (é vs e + ◌́) or full-width digits still matches.
 * - At most 5 password checks per account within 15 min. The 5th failure locks the account
 *   for 15 min; every attempt then answers `429 TOO_MANY_REQUESTS` with
 *   `details.retryAfterSeconds` (the 5th failure itself already answers 429).
 * - The attempt is reserved atomically *before* bcrypt runs (`checkPasswordWithLockout`), so
 *   parallel requests cannot test more than 5 passwords per window.
 * - Unknown e-mails behave exactly like known ones (same bcrypt work, same lockout) so neither
 *   timing nor the lockout reveals whether an account exists. Their counters live in a bounded
 *   in-memory map (per API instance) because there is no user row to store them on.
 */

export const PASSWORD_HASH_ROUNDS = env.isTest ? 10 : BCRYPT_ROUNDS;

/** NFKC form of a password (non-strings are returned unchanged). Idempotent. */
export function normalizePassword(plain) {
  return typeof plain === 'string' ? plain.normalize('NFKC') : plain;
}

/** bcrypt ignores everything after 72 UTF-8 bytes; new passwords longer than that are rejected. */
export function passwordTooLongForBcrypt(plain) {
  return typeof plain === 'string' && bcrypt.truncates(normalizePassword(plain));
}

export function hashPassword(plain) {
  return bcrypt.hash(normalizePassword(plain), PASSWORD_HASH_ROUNDS);
}

let dummyHash;
/** A real hash of a random secret, so a check for an unknown account costs the same time. */
function getDummyHash() {
  dummyHash ??= bcrypt.hash(randomToken(24), PASSWORD_HASH_ROUNDS);
  return dummyHash;
}

/**
 * Constant-work password check (no lockout bookkeeping — see checkPasswordWithLockout).
 * A missing/invalid hash still runs one bcrypt comparison.
 * @returns {Promise<boolean>}
 */
export async function verifyPassword(plain, hash) {
  if (typeof plain !== 'string' || !plain) return false;
  const normalized = normalizePassword(plain);
  if (typeof hash !== 'string' || !hash.startsWith('$2')) {
    await bcrypt.compare(normalized, await getDummyHash());
    return false;
  }
  try {
    return await bcrypt.compare(normalized, hash);
  } catch {
    return false;
  }
}

/** true when a stored hash uses a lower cost than the current setting (upgrade on next login). */
export function needsRehash(hash) {
  try {
    return bcrypt.getRounds(hash) < PASSWORD_HASH_ROUNDS;
  } catch {
    return false;
  }
}

// ---------------------------------------------------------------- lockout

const secondsUntil = (date, now = Date.now()) => {
  const at = date ? new Date(date).getTime() : 0;
  return at > now ? Math.ceil((at - now) / 1000) : 0;
};

/** Seconds the account is still locked for (0 = not locked). */
export function lockRemainingSeconds(user, now = Date.now()) {
  return secondsUntil(user?.lockUntil, now);
}

/** 429 while the account is locked. */
export function assertNotLocked(user, now = Date.now()) {
  const wait = lockRemainingSeconds(user, now);
  if (wait > 0) throw ApiError.tooManyRequests(wait);
}

/** Fields that reset the failed-login bookkeeping (successful login, password reset/change). */
export const CLEAR_LOCKOUT = Object.freeze({ failedLoginCount: 0, lastFailedLoginAt: null, lockUntil: null });

/** Lock state written when an attempt locks the account (the lock replaces the counter). */
const lockFields = (now) => ({
  lockUntil: new Date(now.getTime() + LOGIN_LOCK_WINDOW_MS),
  failedLoginCount: 0,
  lastFailedLoginAt: null,
});

/**
 * Reserves one password check for an account, atomically, before the (slow) bcrypt
 * comparison. `lastFailedLoginAt` is the start of the current 15-min window and
 * `failedLoginCount` the checks made in it; a success clears both.
 *
 * @returns {Promise<number>} the number of this attempt in the window (1…5)
 * @throws {ApiError} 429 while locked, or while all 5 attempts of the window are in use
 */
export async function reserveLoginAttempt(userId, now = new Date()) {
  const windowStart = new Date(now.getTime() - LOGIN_LOCK_WINDOW_MS);
  const notLocked = { $or: [{ lockUntil: null }, { lockUntil: { $lte: now } }] };
  const projection = { failedLoginCount: 1 };

  // First attempt of a new window (none yet, the last window is over, or a lock just ended).
  let doc = await User.findOneAndUpdate(
    {
      _id: userId,
      $and: [notLocked, { $or: [{ lastFailedLoginAt: null }, { lastFailedLoginAt: { $lte: windowStart } }] }],
    },
    { $set: { failedLoginCount: 1, lastFailedLoginAt: now, lockUntil: null } },
    { returnDocument: 'after', projection },
  ).lean();
  if (doc) return 1;

  // Another attempt inside the running window.
  doc = await User.findOneAndUpdate(
    {
      _id: userId,
      ...notLocked,
      lastFailedLoginAt: { $gt: windowStart },
      failedLoginCount: { $lt: LOGIN_MAX_FAILED_ATTEMPTS },
    },
    { $inc: { failedLoginCount: 1 } },
    { returnDocument: 'after', projection },
  ).lean();
  if (doc) return doc.failedLoginCount;

  // Locked, or every attempt of this window is taken (parallel requests still running).
  const current = await User.findById(userId).select('lockUntil lastFailedLoginAt').lean();
  if (!current) throw ApiError.invalidCredentials();
  const windowEnd = current.lastFailedLoginAt
    ? new Date(new Date(current.lastFailedLoginAt).getTime() + LOGIN_LOCK_WINDOW_MS)
    : null;
  throw ApiError.tooManyRequests(lockRemainingSeconds(current, now.getTime()) || secondsUntil(windowEnd, now.getTime()) || 1);
}

/**
 * Checks the password of an existing account under the lockout rules: reserves the attempt
 * first, then compares. Success clears the counters. Use this for every "type your password"
 * check (login, change password, delete account).
 *
 * @param {{ _id: any, passwordHash?: string }} user (must include `passwordHash`)
 * @returns {Promise<true>}
 * @throws {ApiError} 401 INVALID_CREDENTIALS (wrong password) or 429 (locked / this failure locked it)
 */
export async function checkPasswordWithLockout(user, plain) {
  const attempt = await reserveLoginAttempt(user._id);
  if (await verifyPassword(plain, user.passwordHash)) {
    await User.updateOne({ _id: user._id }, { $set: CLEAR_LOCKOUT });
    return true;
  }
  if (attempt >= LOGIN_MAX_FAILED_ATTEMPTS) {
    const now = new Date();
    const lock = lockFields(now);
    await User.updateOne({ _id: user._id }, { $set: lock });
    throw ApiError.tooManyRequests(secondsUntil(lock.lockUntil, now.getTime()));
  }
  throw ApiError.invalidCredentials();
}

/**
 * Records one failed password check atomically (post-check counting). Kept for callers that
 * compare the password themselves; prefer checkPasswordWithLockout, which is race-safe.
 * @returns {Promise<Date|null>} the lock end when this failure locked the account
 */
export async function recordFailedLogin(userId, now = new Date()) {
  const windowStart = new Date(now.getTime() - LOGIN_LOCK_WINDOW_MS);
  const projection = { failedLoginCount: 1 };
  let doc = await User.findOneAndUpdate(
    { _id: userId, $or: [{ lastFailedLoginAt: null }, { lastFailedLoginAt: { $lte: windowStart } }] },
    { $set: { failedLoginCount: 1, lastFailedLoginAt: now } },
    { returnDocument: 'after', projection },
  ).lean();
  doc ??= await User.findOneAndUpdate(
    { _id: userId },
    { $inc: { failedLoginCount: 1 } },
    { returnDocument: 'after', projection },
  ).lean();
  if (!doc || doc.failedLoginCount < LOGIN_MAX_FAILED_ATTEMPTS) return null;
  const lock = lockFields(now);
  // The lock replaces the counter; after it ends the next failure starts a fresh window.
  await User.updateOne({ _id: userId }, { $set: lock });
  return lock.lockUntil;
}

/**
 * Handles a wrong password for an existing account (post-check counting): counts it and
 * throws `429` when this failure locks the account, otherwise `401 INVALID_CREDENTIALS`.
 * Prefer checkPasswordWithLockout.
 * @returns {Promise<never>}
 */
export async function failPasswordCheck(userId) {
  const lockUntil = await recordFailedLogin(userId);
  if (lockUntil) throw ApiError.tooManyRequests(secondsUntil(lockUntil));
  throw ApiError.invalidCredentials();
}

// ---- unknown e-mails (no user row): bounded in-memory counters, same rules

const PHANTOM_MAX_ENTRIES = 10_000;
/** @type {Map<string, { count: number, windowStart: number, lockUntil: number }>} */
const phantom = new Map();

function phantomKey(email) {
  return sha256(`login:${String(email).toLowerCase()}`);
}

function trimPhantom() {
  while (phantom.size > PHANTOM_MAX_ENTRIES) phantom.delete(phantom.keys().next().value);
}

/**
 * Mirrors reserveLoginAttempt for an e-mail without an account (synchronous, so the
 * check-and-increment is atomic within this process).
 * @returns {number} the number of this attempt in the window (1…5)
 */
export function reservePhantomAttempt(email, now = Date.now()) {
  const key = phantomKey(email);
  let entry = phantom.get(key);
  const locked = entry ? secondsUntil(entry.lockUntil, now) : 0;
  if (locked > 0) throw ApiError.tooManyRequests(locked);
  if (!entry || entry.lockUntil || entry.windowStart <= now - LOGIN_LOCK_WINDOW_MS) {
    entry = { count: 0, windowStart: now, lockUntil: 0 };
  }
  if (entry.count >= LOGIN_MAX_FAILED_ATTEMPTS) {
    throw ApiError.tooManyRequests(secondsUntil(entry.windowStart + LOGIN_LOCK_WINDOW_MS, now) || 1);
  }
  entry.count += 1;
  phantom.delete(key); // re-insert → Map order = least recently used first
  phantom.set(key, entry);
  trimPhantom();
  return entry.count;
}

/** Mirrors the failure branch of checkPasswordWithLockout. @returns {never} */
export function failPhantomAttempt(email, attempt, now = Date.now()) {
  if (attempt >= LOGIN_MAX_FAILED_ATTEMPTS) {
    const lockUntil = now + LOGIN_LOCK_WINDOW_MS;
    const key = phantomKey(email);
    phantom.delete(key);
    phantom.set(key, { count: 0, windowStart: now, lockUntil });
    trimPhantom();
    throw ApiError.tooManyRequests(secondsUntil(lockUntil, now));
  }
  throw ApiError.invalidCredentials();
}

/**
 * The whole "password check" for an e-mail without an account: same reservation, same
 * bcrypt work, same answers as checkPasswordWithLockout. Always throws.
 * @returns {Promise<never>}
 */
export async function failUnknownAccountCheck(email, plain) {
  const attempt = reservePhantomAttempt(email);
  await verifyPassword(plain, null);
  failPhantomAttempt(email, attempt);
}

/** Test helper: forget every unknown-e-mail counter. */
export function resetPhantomLockouts() {
  phantom.clear();
}
