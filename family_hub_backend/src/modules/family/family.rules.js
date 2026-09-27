import { ApiError } from '../../lib/ApiError.js';
import { toId } from '../../lib/access.js';
import { DEFAULT_LOCALE } from '../../lib/constants.js';
import { consentAge } from '../../lib/countries.js';
import { randomInviteCode, sha256 } from '../../lib/crypto.js';
import { ageFrom } from '../../lib/dates.js';
import { logger } from '../../lib/logger.js';
import { Family, User } from '../../models/index.js';
import { sendTemplate } from '../../services/mailer.js';

/**
 * Rules shared by the family and member services: loading the caller's family, the guardian
 * consent gate (contract §6 + docs/08-COMPLIANCE.md GAP-05), the family-scoped e-mail
 * uniqueness error, the family size limit, invite-code rotation and the invitation e-mail
 * (with its abuse limits).
 */

/**
 * The caller's family (lean). A family deleted after `requireAuth` ran (its last member left a
 * moment ago) answers like any later request would: `403 NO_FAMILY`.
 * @param {string} familyId
 */
export async function loadFamily(familyId) {
  const family = familyId ? await Family.findById(familyId).lean() : null;
  if (!family) throw ApiError.noFamily();
  return family;
}

/** `409 MEMBER_EMAIL_EXISTS` (contract §1). */
export function memberEmailExistsError() {
  return ApiError.conflict('MEMBER_EMAIL_EXISTS', 'A member with this email already exists');
}

/** true for a duplicate-key error (11000) on `field` (any field when the driver does not say). */
export function isDuplicateKeyOn(err, field) {
  const e = err?.code === 11000 ? err : err?.cause?.code === 11000 ? err.cause : null;
  if (!e) return false;
  const fields = Object.keys(e.keyPattern ?? e.keyValue ?? {});
  return fields.length ? fields.includes(field) : String(e.message ?? '').includes(field);
}

// ---------------------------------------------------------------- family size

/**
 * Most members (with or without an account) one family can have. A family is small; the cap
 * keeps one admin from creating unbounded profiles, because every family-scoped request loads the
 * whole member list (member directory, lists, pushes).
 */
export const MAX_FAMILY_MEMBERS = 100;

/** `409 CONFLICT`: the family already has `MAX_FAMILY_MEMBERS` members. */
export function memberLimitError() {
  return ApiError.conflict('CONFLICT', `A family can have at most ${MAX_FAMILY_MEMBERS} members`, {
    messageKey: 'family.errors.memberLimitReached',
    details: { limit: MAX_FAMILY_MEMBERS },
    vars: { limit: MAX_FAMILY_MEMBERS },
  });
}

// ---------------------------------------------------------------- joining

/**
 * `403 FORBIDDEN`: an account whose e-mail address is not verified yet asked to be linked to the
 * profile an admin pre-added with that address. The address is the only proof that the account
 * belongs to that person (members see each other's e-mail addresses), so it must be verified first.
 */
export function verifyEmailToLinkError() {
  return ApiError.forbidden('Verify your email address first, then join the family again', {
    messageKey: 'family.errors.verifyEmailToLink',
  });
}

// ---------------------------------------------------------------- guardian consent

/**
 * true when a person born on `dateOfBirth` is younger than the consent age of `family.country`
 * (age in the family's time zone, so the birthday boundary is the family's local midnight) and
 * no guardian consent is recorded. An unknown date of birth never needs consent (contract:
 * "If computed age < consentAge(family.country)").
 *
 * @param {{ dateOfBirth: Date|string|null|undefined, guardianConsent?: boolean,
 *           family: { country: string, timezone?: string }, now?: Date }} p
 */
export function needsGuardianConsent({ dateOfBirth, guardianConsent = false, family, now = new Date() }) {
  if (guardianConsent === true || !dateOfBirth) return false;
  const age = ageFrom(dateOfBirth, now, family?.timezone || undefined);
  return age !== null && age < consentAge(family?.country);
}

/**
 * `422 GUARDIAN_CONSENT_REQUIRED` (contract §1).
 * `details`: `{ [field]: message, consentAge, memberIds? }` — `memberIds` lists the existing members
 * that need consent (GAP-05), so the app can point the admin at them.
 *
 * @param {{ country: string, field?: string, memberIds?: string[], messageKey?: string }} p
 */
export function guardianConsentError({
  country,
  field = 'guardianConsent',
  memberIds,
  messageKey = 'family.errors.guardianConsentRequired',
}) {
  const minAge = consentAge(country);
  const details = { [field]: `Guardian consent is required below the age of ${minAge}`, consentAge: minAge };
  if (memberIds) details.memberIds = memberIds;
  return new ApiError(422, 'GUARDIAN_CONSENT_REQUIRED', 'Guardian consent is required for this member', {
    messageKey,
    details,
    vars: { age: minAge },
  });
}

/**
 * Throws `422 GUARDIAN_CONSENT_REQUIRED` when the member described by `dateOfBirth` /
 * `guardianConsent` needs guardian consent in `family` (see `needsGuardianConsent`).
 * @param {Parameters<typeof needsGuardianConsent>[0] & { memberId?: any }} p
 */
export function assertGuardianConsent({ memberId, ...p }) {
  if (!needsGuardianConsent(p)) return;
  throw guardianConsentError({ country: p.family.country, memberIds: memberId ? [toId(memberId)] : undefined });
}

/** true when `a` and `b` give the same consent age boundary (same country and time zone). */
export function sameConsentSettings(a, b) {
  return a?.country === b?.country && (a?.timezone ?? null) === (b?.timezone ?? null);
}

// ---------------------------------------------------------------- invite code

const INVITE_CODE_ATTEMPTS = 8;

/**
 * Gives a family a new random invite code; the old one stops working at once (it is overwritten,
 * and look-ups only match the stored code). A code another family already uses (unique index)
 * is regenerated, up to `INVITE_CODE_ATTEMPTS` times.
 *
 * @param {any} familyId
 * @param {{ currentCode?: string|null, generateCode?: () => string }} [opts] `generateCode` for tests
 * @returns {Promise<object>} the updated family (lean)
 * @throws {ApiError} 403 NO_FAMILY (family gone) · 500 (no unique code found)
 */
export async function rotateInviteCode(familyId, { currentCode = null, generateCode = randomInviteCode } = {}) {
  for (let attempt = 1; attempt <= INVITE_CODE_ATTEMPTS; attempt += 1) {
    const inviteCode = generateCode();
    if (inviteCode === currentCode) continue;
    try {
      const updated = await Family.findOneAndUpdate(
        { _id: familyId },
        { $set: { inviteCode } },
        { returnDocument: 'after', runValidators: true },
      ).lean();
      if (!updated) throw ApiError.noFamily();
      return updated;
    } catch (err) {
      if (!isDuplicateKeyOn(err, 'inviteCode')) throw err;
      logger.warn(`Invite code collision (attempt ${attempt}/${INVITE_CODE_ATTEMPTS}), regenerating`);
    }
  }
  throw ApiError.internal('Could not generate a unique invite code');
}

// ---------------------------------------------------------------- invitation limits

/**
 * Small in-memory fixed-window counter (one API instance, like the rate limiters in
 * middleware/rateLimit.js; use a shared store when running several instances).
 * The map is bounded: expired windows are pruned, and the oldest window is dropped when
 * `maxKeys` is still reached.
 */
function createWindowCounter({ windowMs, limit, maxKeys = 10_000 }) {
  const windows = new Map(); // key → { count, resetAt }

  const live = (key, now) => {
    const entry = windows.get(key);
    return entry && entry.resetAt > now ? entry : null;
  };

  const makeRoom = (now) => {
    for (const [key, entry] of windows) if (entry.resetAt <= now) windows.delete(key);
    if (windows.size >= maxKeys) windows.delete(windows.keys().next().value);
  };

  return {
    /** Seconds until `key` is below its limit again; 0 when it is below it now. */
    retryAfterSeconds(key, now = Date.now()) {
      const entry = live(key, now);
      return entry && entry.count >= limit ? Math.max(1, Math.ceil((entry.resetAt - now) / 1000)) : 0;
    },
    /** Counts one use of `key`. Returns false (and counts nothing) when the limit is reached. */
    take(key, now = Date.now()) {
      let entry = live(key, now);
      if (entry && entry.count >= limit) return false;
      if (!entry) {
        if (windows.size >= maxKeys) makeRoom(now);
        entry = { count: 0, resetAt: now + windowMs };
        windows.set(key, entry);
      }
      entry.count += 1;
      return true;
    },
    clear() {
      windows.clear();
    },
  };
}

const HOUR_MS = 60 * 60 * 1000;

/**
 * Invitation e-mails go to addresses an admin types, so they are limited:
 *   - per family: `perFamily` per hour. Over the limit, adding a member with an e-mail (or giving
 *     a profile a new one) is refused with `429 TOO_MANY_REQUESTS` before anything is written
 *     (`reserveInvitation`);
 *   - per recipient address, across all families: `perRecipient` per 24 hours. Further
 *     invitations to that address are skipped silently (the person already has the code), so a
 *     sender learns nothing about who else invited the address.
 */
export const INVITATION_LIMITS = Object.freeze({ perFamily: 20, perRecipient: 3 });

const familyInvitations = createWindowCounter({ windowMs: HOUR_MS, limit: INVITATION_LIMITS.perFamily });
const recipientInvitations = createWindowCounter({ windowMs: 24 * HOUR_MS, limit: INVITATION_LIMITS.perRecipient });

const familyKey = (familyId) => `family:${toId(familyId)}`;
/** Addresses are kept hashed in memory. */
const recipientKey = (email) => `to:${sha256(String(email).toLowerCase())}`;

/**
 * Counts one invitation against the family's budget (see `INVITATION_LIMITS`), or throws
 * `429 TOO_MANY_REQUESTS` (`details.retryAfterSeconds`) when it is used up. Call once per request,
 * after the other checks and right before writing a member with a new e-mail. Checking and counting
 * are one step, so a burst of parallel requests cannot all pass; a request that fails afterwards
 * still counts (the budget limits attempts).
 */
export function reserveInvitation(familyId) {
  const key = familyKey(familyId);
  if (familyInvitations.take(key)) return;
  throw ApiError.tooManyRequests(familyInvitations.retryAfterSeconds(key), 'Too many invitations, try again later');
}

/** Forgets every invitation count (tests only). */
export function resetInvitationLimits() {
  familyInvitations.clear();
  recipientInvitations.clear();
}

// ---------------------------------------------------------------- invitation e-mail

/**
 * Language of the invitation: the family creator's locale (contract §6), else the inviting
 * admin's, else English.
 */
async function invitationLocale(family, inviter) {
  const owner = family.ownerId ? await User.findById(family.ownerId).select('locale').lean() : null;
  return owner?.locale ?? inviter?.locale ?? DEFAULT_LOCALE;
}

/**
 * E-mails an invitation with the family invite code to a member an admin added (or gave an
 * e-mail address). The person joins by registering (or signing in) with that address and
 * entering the code; their pre-added profile is then linked (contract §4 / §6).
 * The family's budget was reserved by the request (`reserveInvitation`); an address that already
 * got `INVITATION_LIMITS.perRecipient` invitations today is skipped.
 * Never throws: a failing lookup or mail server must not fail the request.
 *
 * @param {{ family: object, member: { name: string, email: string }, inviter: { name?: string, locale?: string } }} p
 * @returns {Promise<void>}
 */
export async function sendMemberInvitation({ family, member, inviter }) {
  if (!member?.email || !family?.inviteCode) return;
  try {
    if (!recipientInvitations.take(recipientKey(member.email))) {
      logger.info('Family invitation e-mail skipped: the address reached its daily invitation limit');
      return;
    }
    const locale = await invitationLocale(family, inviter);
    void sendTemplate({
      to: member.email,
      locale,
      template: 'family.invite',
      vars: {
        name: member.name,
        email: member.email,
        familyName: family.name,
        inviterName: inviter?.name ?? family.name,
        inviteCode: family.inviteCode,
      },
    });
  } catch (err) {
    logger.warn(`Family invitation e-mail skipped: ${err?.name ?? 'Error'}${err?.code ? ` (${err.code})` : ''}`);
  }
}
