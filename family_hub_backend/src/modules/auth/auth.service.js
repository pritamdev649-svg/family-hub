import { ApiError } from '../../lib/ApiError.js';
import { sameId } from '../../lib/access.js';
import { DEFAULT_LOCALE, OTP_PURPOSE, OTP_RESEND_COOLDOWN_SECONDS } from '../../lib/constants.js';
import { logger } from '../../lib/logger.js';
import { Device, Family, User } from '../../models/index.js';
import { sendTemplate } from '../../services/mailer.js';
import { issueTokens } from '../../services/tokens.js';
import {
  assertMaySelfRegister,
  createFamilyForUser,
  findMembership,
  joinFamilyForUser,
  planJoin,
  serializeAccount,
  serializeSession,
} from './auth.onboarding.js';
import { OTP_TTL_MINUTES, consumeOtp, discardOtp, invalidOtpError, issueOtp } from './auth.otp.js';
import {
  CLEAR_LOCKOUT,
  checkPasswordWithLockout,
  failUnknownAccountCheck,
  hashPassword,
  needsRehash,
} from './auth.passwords.js';
import { endAllSessions, endDeviceSession, refreshSession } from './auth.sessions.js';

/**
 * Business rules of `/auth/*` (docs/03-API_CONTRACT.md §4). No HTTP here: controllers pass
 * validated input plus `{ locale, meta: { ip, userAgent } }` and send what is returned.
 */

/** Error summary for logs: name/code only — driver messages can contain e-mail addresses. */
const errorInfo = (err) => `${err?.name ?? 'Error'}${err?.code ? ` (${err.code})` : ''}`;

const EMAIL_TEMPLATES = Object.freeze({
  verifyEmail: 'auth.verifyEmail',
  resetPassword: 'auth.resetPassword',
  passwordChanged: 'auth.passwordChanged',
});

/** Fire-and-forget localized code e-mail (sendTemplate never throws). */
function mailCode(user, template, code) {
  void sendTemplate({
    to: user.email,
    locale: user.locale ?? DEFAULT_LOCALE,
    template,
    vars: { name: user.name, code, minutes: OTP_TTL_MINUTES },
  });
}

/**
 * "Your password was changed" notice (OWASP ASVS 2.2.3): lets the owner notice a takeover
 * through a reset code or a stolen session. Fire-and-forget.
 */
function mailPasswordChanged(user) {
  void sendTemplate({
    to: user.email,
    locale: user.locale ?? DEFAULT_LOCALE,
    template: EMAIL_TEMPLATES.passwordChanged,
    vars: { name: user.name },
  });
}

/** New verification code + e-mail. Failures are logged; the user can use "resend". */
async function sendVerificationCode(user, { cooldown }) {
  const { code } = await issueOtp({ email: user.email, purpose: OTP_PURPOSE.VERIFY_EMAIL, userId: user._id, cooldown });
  mailCode(user, EMAIL_TEMPLATES.verifyEmail, code);
}

async function loadUserOrUnauthorized(userId) {
  const user = await User.findById(userId);
  if (!user) throw ApiError.unauthorized();
  return user;
}

// ---------------------------------------------------------------- register / login / tokens

/**
 * POST /auth/register — creates the account and either a family (admin) or a membership
 * (join / link), then sends the verification code.
 * @returns {Promise<{ user, tokens, family, member }>}
 */
export async function register(input, { locale, meta } = {}) {
  const { email, name, dateOfBirth = null, mode } = input;

  // 1. Checks that need no writes, so predictable failures never create an account.
  //    An existing account wins over every family check: "log in instead" is the useful answer.
  if (await User.exists({ email })) throw ApiError.conflict('EMAIL_TAKEN', 'Email already registered');
  if (mode === 'join') await planJoin({ inviteCode: input.inviteCode, email, dateOfBirth });
  else assertMaySelfRegister({ dateOfBirth, country: input.family.country, timeZone: input.family.timezone });

  // 2. Account (the unique e-mail index settles races → 409 EMAIL_TAKEN via the error middleware).
  const user = await User.create({
    email,
    name,
    passwordHash: await hashPassword(input.password),
    locale: input.locale ?? locale ?? DEFAULT_LOCALE,
    consentAcceptedAt: new Date(),
  });

  // 3. Family membership; roll the account back if that fails.
  let membership;
  try {
    membership =
      mode === 'create'
        ? await createFamilyForUser(user, input.family, { dateOfBirth })
        : await joinFamilyForUser(user, input.inviteCode, { dateOfBirth });
  } catch (err) {
    await User.deleteOne({ _id: user._id }).catch((e) => logger.error(`Register rollback failed: ${errorInfo(e)}`));
    throw err;
  }

  const tokens = await issueTokens(user, meta);
  try {
    await sendVerificationCode(user, { cooldown: false });
  } catch (err) {
    logger.error(`Verification code not sent after register: ${errorInfo(err)}`);
  }

  const session = await serializeSession(membership);
  return { user: session.user, tokens, family: session.family, member: session.member };
}

/**
 * POST /auth/login — generic INVALID_CREDENTIALS; at most 5 password checks per 15 min
 * (race-safe, see checkPasswordWithLockout), unknown e-mails behave the same.
 * @returns {Promise<{ user, tokens }>}
 */
export async function login({ email, password }, { meta } = {}) {
  const user = await User.findOne({ email });
  if (!user) await failUnknownAccountCheck(email, password); // always throws (401, or 429 once "locked")

  await checkPasswordWithLockout(user, password);

  const set = { lastLoginAt: new Date() };
  if (needsRehash(user.passwordHash)) set.passwordHash = await hashPassword(password);
  await User.updateOne({ _id: user._id }, { $set: set });

  const member = await findMembership(user);
  const tokens = await issueTokens(user, meta);
  return { user: serializeAccount(user, member), tokens };
}

/** POST /auth/refresh — rotation + reuse detection (services/tokens.js), see refreshSession. */
export async function refresh({ refreshToken }, { meta } = {}) {
  return { tokens: await refreshSession(refreshToken, meta) };
}

/**
 * POST /auth/logout — ends this device's session (the token and anything rotated from it)
 * and forgets the push device. Idempotent; tokens/devices of other users are never touched.
 */
export async function logout(authUser, { refreshToken, deviceToken }) {
  await endDeviceSession(refreshToken, authUser.id);
  if (deviceToken) await Device.deleteOne({ token: deviceToken, userId: authUser.id });
  return null;
}

// ---------------------------------------------------------------- e-mail verification

/** POST /auth/verify-email — idempotent once verified. @returns {Promise<{ user }>} */
export async function verifyEmail(authUser, member, { otp }) {
  const user = await loadUserOrUnauthorized(authUser.id);
  if (user.emailVerified) return { user: serializeAccount(user, member) };

  const row = await consumeOtp({ email: user.email, purpose: OTP_PURPOSE.VERIFY_EMAIL, code: otp });
  if (row.userId && !sameId(row.userId, user._id)) throw invalidOtpError();

  const updated = await User.findOneAndUpdate(
    { _id: user._id },
    { $set: { emailVerified: true } },
    { returnDocument: 'after' },
  ).lean();
  return { user: serializeAccount(updated, member) };
}

/**
 * POST /auth/resend-verification — 60 s cooldown (429 + retryAfterSeconds).
 * Already verified → nothing is sent: `{ sent: false, retryAfterSeconds: 0 }`.
 */
export async function resendVerification(authUser) {
  const user = await loadUserOrUnauthorized(authUser.id);
  if (user.emailVerified) return { sent: false, retryAfterSeconds: 0 };
  await sendVerificationCode(user, { cooldown: true });
  return { sent: true, retryAfterSeconds: OTP_RESEND_COOLDOWN_SECONDS };
}

// ---------------------------------------------------------------- passwords

/**
 * POST /auth/forgot-password — always `{ sent: true }` (no enumeration).
 *
 * Unknown e-mails get a decoy code row that is never sent, so `reset-password` behaves the
 * same for every address (INVALID_OTP ×5 → OTP_EXPIRED, same expiry). Inside the 60 s
 * cooldown nothing new is sent (and the answer stays `{ sent: true }`).
 */
export async function forgotPassword({ email }) {
  const user = await User.findOne({ email }).select('_id email name locale').lean();
  try {
    const { code } = await issueOtp({ email, purpose: OTP_PURPOSE.RESET_PASSWORD, userId: user?._id ?? null });
    if (user) mailCode(user, EMAIL_TEMPLATES.resetPassword, code);
  } catch (err) {
    if (!(err instanceof ApiError && err.status === 429)) throw err;
  }
  return { sent: true };
}

/**
 * POST /auth/reset-password — sets the new password, unlocks the account, marks the e-mail
 * verified (the code proved access to it), ends every session and e-mails a
 * "password changed" notice.
 */
export async function resetPassword({ email, otp, newPassword }) {
  const row = await consumeOtp({ email, purpose: OTP_PURPOSE.RESET_PASSWORD, code: otp });
  const user = await User.findOne({ email }).select('_id email name locale').lean();
  // Decoy rows (unknown e-mail at request time) or a code issued for a since-deleted account.
  if (!user || !row.userId || !sameId(row.userId, user._id)) throw invalidOtpError();

  await User.updateOne(
    { _id: user._id },
    { $set: { passwordHash: await hashPassword(newPassword), emailVerified: true, ...CLEAR_LOCKOUT } },
  );
  await Promise.all([endAllSessions(user._id), discardOtp(email, OTP_PURPOSE.VERIFY_EMAIL)]);
  mailPasswordChanged(user);
  return { reset: true };
}

/**
 * POST /auth/change-password — verifies the current password (wrong → 401
 * INVALID_CREDENTIALS, counted towards the lockout), ends every session, issues a fresh
 * token pair for the calling device (`{ changed: true, tokens }`) and e-mails a
 * "password changed" notice.
 */
export async function changePassword(authUser, { currentPassword, newPassword }, { meta } = {}) {
  const user = await loadUserOrUnauthorized(authUser.id);
  await checkPasswordWithLockout(user, currentPassword);

  await User.updateOne({ _id: user._id }, { $set: { passwordHash: await hashPassword(newPassword), ...CLEAR_LOCKOUT } });
  await endAllSessions(user._id);
  const tokens = await issueTokens(user, meta);
  mailPasswordChanged(user);
  return { changed: true, tokens };
}

// ---------------------------------------------------------------- me

/** GET /auth/me — `{ user, member|null, family|null }`. `member` is `req.member` (lean). */
export async function me(authUser, member) {
  const user = await User.findById(authUser.id).lean();
  if (!user) throw ApiError.unauthorized();
  const family = member ? await Family.findById(member.familyId).lean() : null;
  return serializeSession({ user, member, family });
}
