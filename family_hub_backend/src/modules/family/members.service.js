import { ApiError } from '../../lib/ApiError.js';
import { findInFamily, isAdmin, sameId, toId } from '../../lib/access.js';
import { ROLE } from '../../lib/constants.js';
import { logger } from '../../lib/logger.js';
import { Family, Member, User } from '../../models/index.js';
import { countMembers } from '../../services/memberDirectory.js';
import { serializeMember, serializeMembers } from '../../services/serializers.js';
import { claimAdminExit, removeMemberGuarded, removeSelfFromFamily } from '../me/memberCascade.js';
import { SELF_EDITABLE_FIELDS } from './family.schemas.js';
import {
  MAX_FAMILY_MEMBERS,
  assertGuardianConsent,
  guardianConsentError,
  isDuplicateKeyOn,
  loadFamily,
  memberEmailExistsError,
  memberLimitError,
  needsGuardianConsent,
  reserveInvitation,
  rotateInviteCode,
  sameConsentSettings,
  sendMemberInvitation,
} from './family.rules.js';

/**
 * Family members (docs/03-API_CONTRACT.md §6, `/family/members`).
 *
 *   list / get   any member of the family; another family's member (or an unknown id) → 404
 *   add          admin → 201 Member (managed profile: no account until the person joins)
 *   patch        admin: every field incl. `role`; a member who is not an admin: only themselves and
 *                only `name, phone, avatarUrl, gender, dateOfBirth` (else 403 FORBIDDEN)
 *   delete       admin → the shared cascade (src/modules/me/memberCascade.js)
 *
 * Check order inside a write: 404 (not in the caller's family) → 403 (role / self-limited fields)
 * → 422 (account e-mail, guardian consent) → 409 (e-mail taken, LAST_ADMIN).
 *
 * Guardian consent (contract §6 + docs/08-COMPLIANCE.md GAP-05): whenever a write sets a date of
 * birth, or withdraws consent, the resulting member must not be below the family country's consent
 * age without `guardianConsent: true` → `422 GUARDIAN_CONSENT_REQUIRED`. Consent is recorded with
 * who confirmed it and when (`guardianConsentById` = the admin's member id, `guardianConsentAt`).
 *
 * LAST_ADMIN: demotions go through `claimAdminExit` and removals through `removeMemberGuarded`,
 * which are race-safe (two admins demoting / removing each other at the same moment never leave the
 * family without an admin who can sign in). Only admins **with an account** count.
 *
 * Concurrency of the other rules (two admins editing at the same moment):
 *   - a PATCH writes only while the stored values its checks relied on are unchanged (date of
 *     birth + consent for the consent gate, "no account yet" for an e-mail change); otherwise it
 *     re-reads the profile and checks again (`UPDATE_ATTEMPTS`), so e.g. withdrawing consent and
 *     making the member a minor at the same time can never both succeed;
 *   - adding a member, or changing a date of birth / consent, re-reads the family after the write:
 *     when a concurrent `PATCH /family` changed the country and the member now needs consent, the
 *     write is undone → 422 (the family side re-checks its members after its write as well).
 *
 * Abuse limits: at most `MAX_FAMILY_MEMBERS` members per family (`409 CONFLICT`), and the
 * invitation e-mail limits of family.rules.js (`429 TOO_MANY_REQUESTS`).
 *
 * `authUser` is `req.user` (`{ id, name, locale, familyId, memberId, role }`).
 */

const asCtx = (authUser) => ({ user: authUser });
const SELF_EDITABLE = new Set(SELF_EDITABLE_FIELDS);
/** Fields copied as they are from a PATCH body (e-mail, role and consent have their own rules). */
const PLAIN_FIELDS = Object.freeze(['name', 'phone', 'avatarUrl', 'dateOfBirth', 'gender', 'designation']);
/** Tries of a PATCH whose checked values changed under it, before `409 CONFLICT`. */
const UPDATE_ATTEMPTS = 3;

const sameTime = (a, b) => (a ? new Date(a).getTime() : null) === (b ? new Date(b).getTime() : null);

function accountEmailLockedError() {
  return ApiError.validation(
    { email: 'This member signs in with this email address; it cannot be changed here' },
    'Validation failed',
    { messageKey: 'family.errors.accountEmailLocked' },
  );
}

function selfEditLimitedError(fields) {
  return ApiError.forbidden('You can only change your own name, phone, photo, gender and date of birth', {
    messageKey: 'family.errors.selfEditLimited',
    details: Object.fromEntries(fields.map((field) => [field, 'Only an admin can change this'])),
  });
}

/** `409 CONFLICT`: the profile kept changing under a PATCH (see UPDATE_ATTEMPTS). */
function concurrentEditError() {
  return ApiError.conflict('CONFLICT', 'This member was changed at the same time, please try again');
}

/** 409 MEMBER_EMAIL_EXISTS when another member of the family already uses `email`. */
async function assertEmailFree(familyId, email, exceptMemberId = null) {
  if (!email) return;
  const filter = { familyId, email };
  if (exceptMemberId) filter._id = { $ne: exceptMemberId };
  if (await Member.exists(filter)) throw memberEmailExistsError();
}

/** The filter value matching a stored `guardianConsent` (older rows may lack the field). */
const consentFilter = (consent) => (consent === true ? true : { $ne: true });

// ---------------------------------------------------------------- read

/** `GET /family/members` → Member[]: admins first, then oldest → youngest (unknown DOB last). */
export async function listMembers(authUser) {
  const members = await Member.find({ familyId: authUser.familyId }).lean();
  return serializeMembers(members);
}

/** `GET /family/members/:id` → Member. */
export async function getMember(authUser, memberId) {
  return serializeMember(await findInFamily(Member, memberId, authUser.familyId, { lean: true }));
}

// ---------------------------------------------------------------- add

/**
 * `POST /family/members` (admin) → Member. The new member has no account (`hasAccount: false`).
 * With an e-mail address, the person gets an invitation with the family invite code (in the family
 * creator's language) and is linked to this profile when they join with that address.
 *
 * @throws {ApiError} 409 MEMBER_EMAIL_EXISTS · 422 GUARDIAN_CONSENT_REQUIRED
 */
export async function addMember(authUser, body) {
  const family = await loadFamily(authUser.familyId);
  const email = body.email ?? null;
  await assertEmailFree(family._id, email);

  const guardianConsent = body.guardianConsent === true;
  assertGuardianConsent({ dateOfBirth: body.dateOfBirth, guardianConsent, family });
  if ((await countMembers(family._id)) >= MAX_FAMILY_MEMBERS) throw memberLimitError();
  if (email) reserveInvitation(family._id);

  let member;
  try {
    member = await Member.create({
      familyId: family._id,
      userId: null,
      name: body.name,
      email,
      phone: body.phone ?? null,
      avatarUrl: body.avatarUrl ?? null,
      dateOfBirth: body.dateOfBirth ?? null,
      gender: body.gender ?? null,
      designation: body.designation ?? null,
      role: body.role ?? ROLE.MEMBER,
      guardianConsent,
      guardianConsentAt: guardianConsent ? new Date() : null,
      guardianConsentById: guardianConsent ? authUser.memberId : null,
    });
  } catch (err) {
    if (isDuplicateKeyOn(err, 'email')) throw memberEmailExistsError();
    throw err;
  }

  // Checked again after the write, and the new row is removed when one fails:
  //   - the family may have been dissolved meanwhile (its last member left) → 403 NO_FAMILY;
  //   - a concurrent PATCH /family may have changed the country → the consent gate again;
  //   - concurrent adds may have passed the size check together → the members written first
  //     (smaller ids) keep their place.
  let current;
  try {
    current = await Family.findById(family._id).lean();
    if (!current) throw ApiError.noFamily();
    if (!sameConsentSettings(current, family)) {
      assertGuardianConsent({ dateOfBirth: member.dateOfBirth, guardianConsent, family: current });
    }
    if ((await Member.countDocuments({ familyId: family._id, _id: { $lt: member._id } })) >= MAX_FAMILY_MEMBERS) {
      throw memberLimitError();
    }
  } catch (err) {
    await Member.deleteOne({ _id: member._id });
    throw err;
  }

  if (email) await sendMemberInvitation({ family: current, member, inviter: authUser });
  return serializeMember(member);
}

// ---------------------------------------------------------------- patch

/**
 * What a PATCH writes on `target`, and the filter of the write: the member's id plus the stored
 * values the checks below relied on, so the write only lands while they are unchanged.
 * @returns {Promise<{ set: object, filter: object, consentFamily: object|null }>}
 *   `consentFamily`: the family the consent gate was checked against (null when it did not run)
 * @throws {ApiError} 422 (account e-mail, guardian consent) · 409 MEMBER_EMAIL_EXISTS
 */
async function planMemberUpdate(authUser, target, body) {
  const set = {};
  const filter = { _id: target._id, familyId: target.familyId };
  for (const field of PLAIN_FIELDS) {
    if (body[field] === undefined) continue;
    const unchanged = field === 'dateOfBirth' ? sameTime(body[field], target[field]) : body[field] === (target[field] ?? null);
    if (!unchanged) set[field] = body[field];
  }

  if (body.email !== undefined && body.email !== (target.email ?? null)) {
    if (target.userId) throw accountEmailLockedError();
    await assertEmailFree(target.familyId, body.email, target._id);
    set.email = body.email;
    // Only while nobody has linked an account to the profile (its e-mail is then the sign-in address).
    filter.userId = null;
  }

  if (body.guardianConsent !== undefined && body.guardianConsent !== Boolean(target.guardianConsent)) {
    set.guardianConsent = body.guardianConsent;
    set.guardianConsentAt = body.guardianConsent ? new Date() : null;
    set.guardianConsentById = body.guardianConsent ? authUser.memberId : null;
  }

  let consentFamily = null;
  if (set.dateOfBirth !== undefined || set.guardianConsent === false) {
    consentFamily = await loadFamily(authUser.familyId);
    assertGuardianConsent({
      memberId: target._id,
      dateOfBirth: set.dateOfBirth !== undefined ? set.dateOfBirth : target.dateOfBirth,
      guardianConsent: set.guardianConsent ?? Boolean(target.guardianConsent),
      family: consentFamily,
    });
    // The decision holds for the stored date of birth and consent it was made on.
    filter.dateOfBirth = target.dateOfBirth ?? null;
    filter.guardianConsent = consentFilter(target.guardianConsent);
  }

  if (body.role === ROLE.ADMIN && target.role !== ROLE.ADMIN) set.role = ROLE.ADMIN;
  return { set, filter, consentFamily };
}

/**
 * Puts back the values `set` overwrote on `target` — only while the profile still holds the values
 * written (a later edit by someone else is kept). Never throws; the caller answers with its error.
 */
async function revertMemberUpdate(target, set) {
  const filter = { _id: target._id, familyId: target.familyId };
  const restore = {};
  for (const [field, value] of Object.entries(set)) {
    filter[field] = value ?? null;
    restore[field] = target[field] ?? null;
  }
  try {
    await Member.updateOne(filter, { $set: restore });
  } catch (err) {
    logger.error(`Member update rollback failed: ${err?.name ?? 'Error'}${err?.code ? ` (${err.code})` : ''}`);
  }
}

/**
 * `PATCH /family/members/:id` → Member.
 *
 * - Admin: every field of any member, incl. `role` (promote / demote) and `guardianConsent`.
 * - Not an admin: only their own profile and only `SELF_EDITABLE_FIELDS`; anything else → 403.
 * - The e-mail of a member **with an account** is their sign-in address → it cannot be changed
 *   here (`422`, same value = no-op). Giving a managed profile a (new) e-mail sends the invitation.
 * - Renaming yourself renames your account too (as `PATCH /me` does).
 * - Demoting the last admin who can sign in → `409 LAST_ADMIN`.
 * - Race-safe checks, see the file header (`409 CONFLICT` when the profile keeps changing).
 */
export async function updateMember(authUser, memberId, body) {
  let target = await findInFamily(Member, memberId, authUser.familyId, { lean: true });
  const actorIsAdmin = isAdmin(asCtx(authUser));
  const isSelf = sameId(target._id, authUser.memberId);

  if (!actorIsAdmin) {
    if (!isSelf) throw ApiError.forbidden();
    const denied = Object.keys(body).filter((field) => !SELF_EDITABLE.has(field));
    if (denied.length) throw selfEditLimitedError(denied);
  }

  let plan = await planMemberUpdate(authUser, target, body);
  if (plan.set.email) reserveInvitation(target.familyId);
  const demote = body.role === ROLE.MEMBER && target.role === ROLE.ADMIN;
  // A successful guard *is* the demotion (race-safe LAST_ADMIN, see memberCascade.js).
  const guard = demote ? await claimAdminExit(target, { leaving: false }) : null;

  let updated = null;
  try {
    for (let attempt = 1; !updated; attempt += 1) {
      updated = Object.keys(plan.set).length
        ? await Member.findOneAndUpdate(plan.filter, { $set: plan.set }, { returnDocument: 'after', runValidators: true }).lean()
        : await Member.findOne(plan.filter).lean();
      if (updated) break;
      // Removed in the meantime (404), or a value the checks relied on changed: check again.
      target = await Member.findOne({ _id: target._id, familyId: target.familyId }).lean();
      if (!target) throw ApiError.notFound();
      if (attempt >= UPDATE_ATTEMPTS) throw concurrentEditError();
      plan = await planMemberUpdate(authUser, target, body);
    }

    if (plan.consentFamily) {
      const family = await loadFamily(authUser.familyId);
      if (
        !sameConsentSettings(family, plan.consentFamily) &&
        needsGuardianConsent({ dateOfBirth: updated.dateOfBirth, guardianConsent: Boolean(updated.guardianConsent), family })
      ) {
        await revertMemberUpdate(target, plan.set);
        throw guardianConsentError({ country: family.country, memberIds: [toId(target._id)] });
      }
    }
  } catch (err) {
    if (guard) await guard.release().catch((e) => logger.error(`Admin role restore failed: ${e?.name ?? 'Error'}`));
    if (isDuplicateKeyOn(err, 'email')) throw memberEmailExistsError();
    throw err;
  }

  if (isSelf && plan.set.name !== undefined && updated.userId) {
    await User.updateOne({ _id: updated.userId, memberId: updated._id }, { $set: { name: plan.set.name } });
  }
  if (plan.set.email && !updated.userId) {
    const family = await Family.findById(target.familyId).lean();
    if (family) await sendMemberInvitation({ family, member: updated, inviter: authUser });
  }
  return serializeMember(updated);
}

// ---------------------------------------------------------------- delete

/**
 * `DELETE /family/members/:id` (admin) → null, with the contract cascade: the person's account is
 * unlinked and signed out everywhere (refresh tokens and push devices removed), their pending tasks
 * and emergency card are deleted, their active SOS is resolved; ledger entries stay.
 *
 * Removing a member **with an account** also gives the family a new invite code: that person knows
 * the current one and could otherwise join again right away. (Managed profiles never joined, so
 * their removal keeps the code and the invitations other people have.)
 *
 * An admin removing **themselves** leaves the family, exactly like `POST /me/leave-family`: same
 * LAST_ADMIN rule, they stay signed in, the invite code is kept, and the last member leaving
 * deletes the family.
 *
 * @throws {ApiError} 404 · 409 LAST_ADMIN
 */
export async function removeMember(authUser, memberId) {
  const target = await findInFamily(Member, memberId, authUser.familyId, { lean: true });
  const family = await Family.findById(target.familyId).lean();
  if (sameId(target._id, authUser.memberId)) {
    await removeSelfFromFamily({ member: target, family, endSessions: false });
    return null;
  }
  const result = await removeMemberGuarded({ member: target, family, actorId: toId(authUser.memberId) });
  if (target.userId && !result.familyDeleted) {
    await rotateInviteCode(target.familyId, { currentCode: family?.inviteCode ?? null }).catch((err) => {
      // Dissolved meanwhile: no code left to protect.
      if (err?.code !== 'NO_FAMILY') throw err;
    });
  }
  return null;
}
