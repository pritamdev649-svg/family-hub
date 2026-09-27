import { env } from '../../config/env.js';
import { ApiError } from '../../lib/ApiError.js';
import {
  OTP_LENGTH,
  OTP_MAX_ATTEMPTS,
  OTP_RESEND_COOLDOWN_SECONDS,
  OTP_TTL_MS,
} from '../../lib/constants.js';
import { randomDigits, safeEqual, sha256 } from '../../lib/crypto.js';
import { Otp } from '../../models/index.js';

/**
 * E-mail one-time codes (docs/03-API_CONTRACT.md §4): 6 digits, valid 10 min, at most
 * 5 checks (then `OTP_EXPIRED`), resend cooldown 60 s. One live code per (email, purpose):
 * issuing a new code replaces the old one. Only a sha256 hash is stored; it is bound to the
 * e-mail + purpose and peppered with a server secret so a leaked hash can neither be reused
 * for another row nor brute-forced offline without the secret.
 *
 * Brute-force bound: without more, "5 guesses, then request a new code after 60 s" allows
 * 7 200 guesses a day per address (≈ 0.7 % chance to take over an account through
 * reset-password every day). So the resend cooldown grows with the wrong guesses made on the
 * current code: max(60 s, wrong guesses × 3 min) — at most 5 guesses per 15 min, the same
 * rate as the login lockout. A code that was never mistyped keeps the plain 60 s cooldown.
 */

export const OTP_TTL_MINUTES = Math.round(OTP_TTL_MS / 60_000);
const COOLDOWN_MS = OTP_RESEND_COOLDOWN_SECONDS * 1000;
/** Extra resend wait per wrong guess on the current code (5 wrong → 15 min). */
export const OTP_WRONG_GUESS_COOLDOWN_MS = 3 * 60 * 1000;
/** Optimistic-concurrency retries of issueOtp when a parallel request changed the row. */
const ISSUE_MAX_TRIES = 3;

export const invalidOtpError = () => new ApiError(400, 'INVALID_OTP', 'Invalid code');
export const otpExpiredError = () => new ApiError(400, 'OTP_EXPIRED', 'Code expired, request a new one');

function hashCode(email, purpose, code) {
  return sha256(`otp:v1:${purpose}:${email}:${code}:${env.JWT_ACCESS_SECRET}`);
}

function isDuplicateKey(err) {
  return err?.code === 11000 || err?.cause?.code === 11000;
}

/** Resend cooldown (ms) for a code row: 60 s, or 3 min per wrong guess made on it. */
export function cooldownMsFor(row) {
  const wrong = Math.max(0, Number(row?.attempts) || 0);
  return Math.max(COOLDOWN_MS, wrong * OTP_WRONG_GUESS_COOLDOWN_MS);
}

/** Whole seconds until another code may be sent for this row (≥ 1 while the cooldown runs). */
export function cooldownRemainingSeconds(row, now = new Date()) {
  if (!row?.lastSentAt) return 0;
  const ms = new Date(row.lastSentAt).getTime() + cooldownMsFor(row) - now.getTime();
  return ms > 0 ? Math.ceil(ms / 1000) : 0;
}

/**
 * Creates or replaces the code for (email, purpose) and resets its attempt counter.
 *
 * With `cooldown` (default) the replacement is atomic with the cooldown rule: the row is only
 * replaced when it still has the `lastSentAt` / `attempts` the rule was evaluated on, and the
 * first insert is settled by the unique {email, purpose} index. Inside the cooldown the call
 * fails with `429 TOO_MANY_REQUESTS` (`details.retryAfterSeconds`).
 * Without `cooldown` (first code at registration) the row is replaced unconditionally.
 *
 * @param {{ email: string, purpose: string, userId?: any, cooldown?: boolean, now?: Date }} p
 * @returns {Promise<{ code: string, expiresAt: Date }>} the plain code (to e-mail) — never stored
 */
export async function issueOtp({ email, purpose, userId = null, cooldown = true, now = new Date() }) {
  const code = randomDigits(OTP_LENGTH);
  const expiresAt = new Date(now.getTime() + OTP_TTL_MS);
  const fields = { codeHash: hashCode(email, purpose, code), expiresAt, attempts: 0, lastSentAt: now, userId: userId ?? null };

  if (!cooldown) {
    try {
      await Otp.updateOne({ email, purpose }, { $set: fields }, { upsert: true });
    } catch (err) {
      if (!isDuplicateKey(err)) throw err;
      // Two concurrent first inserts: the row exists now, replace it.
      await Otp.updateOne({ email, purpose }, { $set: fields });
    }
    return { code, expiresAt };
  }

  for (let attempt = 1; attempt <= ISSUE_MAX_TRIES; attempt += 1) {
    const current = await Otp.findOne({ email, purpose }).select('lastSentAt attempts').lean();
    if (!current) {
      try {
        await Otp.create({ email, purpose, ...fields });
        return { code, expiresAt };
      } catch (err) {
        if (!isDuplicateKey(err)) throw err;
        continue; // a parallel request inserted first → evaluate its row
      }
    }
    const wait = cooldownRemainingSeconds(current, now);
    if (wait > 0) throw ApiError.tooManyRequests(wait);
    const res = await Otp.updateOne(
      { _id: current._id, lastSentAt: current.lastSentAt ?? null, attempts: current.attempts ?? null },
      { $set: fields },
    );
    if (res.matchedCount === 1) return { code, expiresAt };
    // A guess or another resend changed the row meanwhile → evaluate again.
  }
  throw ApiError.tooManyRequests(Math.ceil(COOLDOWN_MS / 1000));
}

/**
 * Checks a code and consumes it on success (single use).
 *
 * Every check counts as an attempt (atomically, so parallel guesses cannot exceed the limit):
 * the first 5 wrong codes answer `INVALID_OTP`; after that — or when the code is older than
 * 10 min, or none was ever requested — the answer is `OTP_EXPIRED` (request a new one).
 *
 * @returns {Promise<{ userId: any }>} the consumed row (lean)
 */
export async function consumeOtp({ email, purpose, code, now = new Date() }) {
  const counted = await Otp.findOneAndUpdate(
    { email, purpose, attempts: { $lt: OTP_MAX_ATTEMPTS }, expiresAt: { $gt: now } },
    { $inc: { attempts: 1 } },
    { returnDocument: 'after' },
  ).lean();
  if (!counted) throw otpExpiredError();
  if (!safeEqual(counted.codeHash, hashCode(email, purpose, String(code)))) throw invalidOtpError();
  // Delete only the row we checked: a code replaced meanwhile (resend) or consumed by a
  // parallel request must not be accepted twice.
  const consumed = await Otp.findOneAndDelete({ _id: counted._id, codeHash: counted.codeHash }).lean();
  if (!consumed) throw otpExpiredError();
  return consumed;
}

/** Drops any pending code for (email, purpose). */
export async function discardOtp(email, purpose) {
  await Otp.deleteOne({ email, purpose });
}
