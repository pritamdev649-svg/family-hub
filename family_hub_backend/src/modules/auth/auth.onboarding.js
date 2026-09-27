import { ApiError } from '../../lib/ApiError.js';
import { toId } from '../../lib/access.js';
import { DEFAULT_ADMIN_DESIGNATION, PUSH_ROUTES, PUSH_TYPE, ROLE } from '../../lib/constants.js';
import { consentAge } from '../../lib/countries.js';
import { randomInviteCode } from '../../lib/crypto.js';
import { ageFrom } from '../../lib/dates.js';
import { logger } from '../../lib/logger.js';
import { Family, Member, User } from '../../models/index.js';
import { countMembers } from '../../services/memberDirectory.js';
import { sendToMembers } from '../../services/push.js';
import { serializeFamily, serializeMember, serializeUser } from '../../services/serializers.js';

/**
 * Family membership for an account: create a family (caller becomes its admin), join one by
 * invite code (new `member`, or link to a member an admin pre-added with the same e-mail and
 * no account), and the `{ user, member, family }` session shape.
 *
 * Used by `POST /auth/register`; written so `POST /family` and `POST /family/join` can reuse
 * it (`createFamilyForUser`, `joinFamilyForUser`, `serializeSession`).
 *
 * MongoDB transactions are not assumed (standalone servers / mongodb-memory-server), so every
 * multi-document step is ordered to fail early and rolls back what it created.
 */

const INVITE_CODE_MAX_ATTEMPTS = 8;

export const invalidInviteCodeError = () => new ApiError(400, 'INVALID_INVITE_CODE', 'Invite code unknown');

function isDuplicateKeyOn(err, field) {
  const e = err?.code === 11000 ? err : err?.cause?.code === 11000 ? err.cause : null;
  if (!e) return false;
  const fields = Object.keys(e.keyPattern ?? e.keyValue ?? {});
  return fields.length ? fields.includes(field) : String(e.message ?? '').includes(field);
}

const sameMemberId = (a, b) => String(a?._id) === String(b?._id);

const plain = (doc) => (doc && typeof doc.toObject === 'function' ? doc.toObject() : doc);

// ---------------------------------------------------------------- consent-age gate

/**
 * Self-registration age gate (docs/08-COMPLIANCE.md GAP-01): a person younger than the
 * family country's digital-consent age may only get an account by being linked to a member
 * profile an admin created with guardian consent. Without a date of birth nothing is checked.
 * @throws {ApiError} 422 GUARDIAN_CONSENT_REQUIRED
 */
export function assertMaySelfRegister({ dateOfBirth, country, timeZone, guardianConsent = false }) {
  if (guardianConsent || !dateOfBirth) return;
  const age = ageFrom(dateOfBirth, new Date(), timeZone || undefined);
  const minAge = consentAge(country);
  if (age !== null && age < minAge) {
    throw new ApiError(422, 'GUARDIAN_CONSENT_REQUIRED', 'A parent or guardian must add you to the family first', {
      messageKey: 'auth.errors.guardianConsentRequired',
      details: { dateOfBirth: `Below the consent age (${minAge}) for this country`, consentAge: minAge },
      vars: { age: minAge },
    });
  }
}

// ---------------------------------------------------------------- lookups

/** The family for an (already normalised, upper-case) invite code, or `400 INVALID_INVITE_CODE`. */
export async function findFamilyByInviteCode(inviteCode) {
  const code = typeof inviteCode === 'string' ? inviteCode.replace(/[\s-]/g, '').toUpperCase() : '';
  if (!code) throw invalidInviteCodeError();
  const family = await Family.findOne({ inviteCode: code });
  if (!family) throw invalidInviteCodeError();
  return family;
}

/**
 * Member an admin pre-added with this e-mail (to be linked), or null.
 * @throws {ApiError} 409 MEMBER_EMAIL_EXISTS when that member already has an account
 */
export async function findLinkableMember(familyId, email) {
  if (!email) return null;
  const existing = await Member.findOne({ familyId, email });
  if (existing?.userId) throw ApiError.conflict('MEMBER_EMAIL_EXISTS', 'A member with this email already exists');
  return existing;
}

/**
 * Validates a join without writing anything (fail fast before an account is created).
 * @returns {Promise<{ family: object, existing: object|null }>}
 */
export async function planJoin({ inviteCode, email, dateOfBirth = null }) {
  const family = await findFamilyByInviteCode(inviteCode);
  const existing = await findLinkableMember(family._id, email);
  assertMaySelfRegister({
    dateOfBirth: existing?.dateOfBirth ?? dateOfBirth,
    country: family.country,
    timeZone: family.timezone,
    guardianConsent: Boolean(existing?.guardianConsent),
  });
  return { family, existing };
}

// ---------------------------------------------------------------- writes

/**
 * Creates a family with a unique invite code, regenerating the code on the (rare)
 * duplicate-key error.
 * @param {{ name: string, country: string, currency: string, timezone: string, ownerId: any }} data
 * @param {{ generateCode?: () => string, maxAttempts?: number }} [opts] (`generateCode` for tests)
 */
export async function createFamilyWithUniqueCode(data, { generateCode = randomInviteCode, maxAttempts = INVITE_CODE_MAX_ATTEMPTS } = {}) {
  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    try {
      return await Family.create({ ...data, inviteCode: generateCode() });
    } catch (err) {
      if (!isDuplicateKeyOn(err, 'inviteCode')) throw err;
      logger.warn(`Invite code collision (attempt ${attempt}/${maxAttempts}), regenerating`);
    }
  }
  throw ApiError.internal('Could not generate a unique invite code');
}

const alreadyInFamilyError = () => ApiError.conflict('ALREADY_IN_FAMILY', 'Already in a family');

/**
 * 409 ALREADY_IN_FAMILY when the user really belongs to a family. A *stale* membership
 * (familyId set but the member row is gone or linked to someone else — the rule
 * `requireAuth` uses) counts as "no family", otherwise such a user could never create or
 * join a family again.
 * @returns {Promise<any>} the stale familyId to replace, or null
 */
async function assertHasNoFamily(user) {
  if (!user.familyId) return null;
  if (await findMembership(user)) throw alreadyInFamilyError();
  return user.familyId;
}

/**
 * Sets familyId/memberId on a user that has no family yet (atomic: only while the user still
 * has `expectedFamilyId` — null, or the stale id seen before), else 409 ALREADY_IN_FAMILY.
 */
async function claimUserFamily(userId, familyId, memberId, expectedFamilyId = null) {
  const updated = await User.findOneAndUpdate(
    { _id: userId, familyId: expectedFamilyId ?? null },
    { $set: { familyId, memberId } },
    { returnDocument: 'after' },
  ).lean();
  if (!updated) throw alreadyInFamilyError();
  return updated;
}

/**
 * The account creates a family and becomes its admin ("Head of Family").
 * @param {object} user   User document or lean object (needs `_id`, `email`, `name`, `familyId`;
 *                        `req.user` is not enough — load the user first)
 * @param {{ name, country, currency, timezone }} input
 * @param {{ dateOfBirth?: Date|null }} [opts]
 * @returns {Promise<{ user: object, family: object, member: object }>}
 */
export async function createFamilyForUser(user, input, { dateOfBirth = null } = {}) {
  const staleFamilyId = await assertHasNoFamily(user);
  assertMaySelfRegister({ dateOfBirth, country: input.country, timeZone: input.timezone });
  const family = await createFamilyWithUniqueCode({
    name: input.name,
    country: input.country,
    currency: input.currency,
    timezone: input.timezone,
    ownerId: user._id,
  });
  try {
    const member = await Member.create({
      familyId: family._id,
      userId: user._id,
      name: user.name,
      email: user.email,
      dateOfBirth: dateOfBirth ?? null,
      role: ROLE.ADMIN,
      designation: DEFAULT_ADMIN_DESIGNATION,
    });
    const updatedUser = await claimUserFamily(user._id, family._id, member._id, staleFamilyId);
    return { user: updatedUser, family, member };
  } catch (err) {
    await Promise.allSettled([Member.deleteMany({ familyId: family._id }), Family.deleteOne({ _id: family._id })]);
    throw err;
  }
}

/**
 * The account joins the family of `inviteCode`: links the member an admin pre-added with the
 * same e-mail (keeping its name, role, designation, consent …) or creates a new `member`.
 * Admins get a `member_joined` push. `user` as for createFamilyForUser.
 * @returns {Promise<{ user: object, family: object, member: object, linked: boolean }>}
 */
export async function joinFamilyForUser(user, inviteCode, { dateOfBirth = null } = {}) {
  const staleFamilyId = await assertHasNoFamily(user);
  const { family, existing } = await planJoin({ inviteCode, email: user.email, dateOfBirth });

  let member = null;
  let undo;
  if (existing) {
    const set = { userId: user._id };
    if (!existing.dateOfBirth && dateOfBirth) set.dateOfBirth = dateOfBirth;
    member = await Member.findOneAndUpdate(
      { _id: existing._id, familyId: family._id, userId: null },
      { $set: set },
      { returnDocument: 'after' },
    );
    if (member) {
      undo = () =>
        Member.updateOne(
          { _id: member._id, userId: user._id },
          { $set: { userId: null, ...(set.dateOfBirth ? { dateOfBirth: null } : {}) } },
        );
    } else {
      // Linked by someone else in the meantime → conflict. Removed by an admin in the
      // meantime → join as a new member, without the removed profile's guardian consent.
      if (await Member.exists({ familyId: family._id, email: user.email })) {
        throw ApiError.conflict('MEMBER_EMAIL_EXISTS', 'A member with this email already exists');
      }
      assertMaySelfRegister({ dateOfBirth, country: family.country, timeZone: family.timezone });
    }
  }
  if (!member) {
    member = await Member.create({
      familyId: family._id,
      userId: user._id,
      name: user.name,
      email: user.email,
      dateOfBirth: dateOfBirth ?? null,
      role: ROLE.MEMBER,
    });
    undo = () => Member.deleteOne({ _id: member._id, userId: user._id });
  }

  let updatedUser;
  try {
    updatedUser = await claimUserFamily(user._id, family._id, member._id, staleFamilyId);
  } catch (err) {
    await Promise.resolve(undo()).catch((e) => logger.error(`Join rollback failed: ${e?.name ?? 'Error'}${e?.code ? ` (${e.code})` : ''}`));
    throw err;
  }
  await notifyMemberJoined(family, member);
  return { user: updatedUser, family, member, linked: Boolean(existing && sameMemberId(existing, member)) };
}

/** `member_joined` push to the family's admins (fire-and-forget; never throws). */
export async function notifyMemberJoined(family, member) {
  try {
    const admins = await Member.find({ familyId: family._id, role: ROLE.ADMIN, _id: { $ne: member._id } })
      .select('_id')
      .lean();
    if (!admins.length) return;
    void sendToMembers({
      familyId: toId(family._id),
      memberIds: admins.map((a) => toId(a._id)),
      excludeMemberIds: [toId(member._id)],
      type: PUSH_TYPE.MEMBER_JOINED,
      id: toId(member._id),
      route: PUSH_ROUTES.member(toId(member._id)),
      titleKey: 'auth.push.memberJoined.title',
      bodyKey: 'auth.push.memberJoined.body',
      vars: { name: member.name, familyName: family.name },
    });
  } catch (err) {
    logger.warn(`member_joined push skipped: ${err?.name ?? 'Error'}${err?.code ? ` (${err.code})` : ''}`);
  }
}

// ---------------------------------------------------------------- session shape

/**
 * The caller's member (lean) when the user is still linked to it, else null — the same
 * "stale membership = no family" rule as `requireAuth`.
 */
export async function findMembership(user) {
  if (!user?.familyId || !user?.memberId) return null;
  return Member.findOne({ _id: user.memberId, familyId: user.familyId, userId: user._id }).lean();
}

/** Contract `User` for an account; family fields are null when the membership is gone. */
export function serializeAccount(user, member) {
  const u = plain(user);
  if (!member) return serializeUser({ ...u, familyId: null, memberId: null });
  return serializeUser(u, member);
}

/**
 * `{ user, member|null, family|null }` (GET /auth/me, POST /family, POST /family/join).
 * `inviteCode` is only included for admins; `memberCount` is computed.
 */
export async function serializeSession({ user, member, family }) {
  const linked = Boolean(member && family);
  if (!linked) return { user: serializeAccount(user, null), member: null, family: null };
  const memberCount = await countMembers(family._id);
  return {
    user: serializeAccount(user, member),
    member: serializeMember(member),
    family: serializeFamily(family, { isAdmin: member.role === ROLE.ADMIN, memberCount }),
  };
}

/** Loads and serializes the session of a user id (null when the user no longer exists). */
export async function loadSession(userId) {
  const user = await User.findById(userId).lean();
  if (!user) return null;
  const member = await findMembership(user);
  const family = member ? await Family.findById(member.familyId).lean() : null;
  return serializeSession({ user, member, family });
}
