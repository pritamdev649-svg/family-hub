import { ApiError } from '../../lib/ApiError.js';
import { sameId, toId } from '../../lib/access.js';
import { ROLE } from '../../lib/constants.js';
import { logger } from '../../lib/logger.js';
import { getMemberMap } from '../../services/memberDirectory.js';
import { notifySosResolved } from '../sos/sos.service.js';
import {
  Device,
  EmergencyCard,
  Family,
  Goal,
  LedgerEntry,
  Member,
  Notice,
  RefreshToken,
  SosAlert,
  Task,
  User,
} from '../../models/index.js';

/**
 * Shared member-removal cascade (docs/03-API_CONTRACT.md §5 and §6, docs/04-DATA_MODELS.md §2).
 *
 * Used by
 *   - `POST /me/leave-family` and `DELETE /me` (this module), through `removeSelfFromFamily`;
 *   - `DELETE /family/members/:id` (b-family): `removeMemberGuarded` (LAST_ADMIN guard + cascade);
 *   - `PATCH /family/members/:id` demoting an admin (b-family): `claimAdminExit(target, { leaving: false })`.
 *
 * What removing a member does (contract §6 "Deleting a member"):
 *   1. active SOS alerts of the member are resolved (lazily expired ones become `expired`) and
 *      the rest of the family gets the `sos_resolved` push ("… closed the SOS alert");
 *   2. its **pending** tasks (as assignee) are deleted — done tasks and tasks it created for
 *      others stay;
 *   3. its emergency card is deleted;
 *   4. the Member row is deleted;
 *   5. its user (if any) is unlinked (`familyId = memberId = null`); with `endSessions`
 *      (default) every refresh token and push device of that user is removed;
 *   6. the family is settled: no members left → the whole family is deleted
 *      (`deleteFamilyCascade`); `Family.ownerId` moves to the longest-standing remaining admin
 *      when the owner left; a family left without any admin who can sign in (only possible
 *      when two removals race past `assertNotLastAdmin`) gets its longest-standing member
 *      with an account promoted to admin.
 * Ledger entries, goals and notices stay (entries keep `memberName`).
 *
 * MongoDB transactions are not assumed (standalone servers / mongodb-memory-server). Every
 * step is idempotent and dependents are removed before the Member row, so a failed cascade
 * can simply be run again.
 *
 * LAST_ADMIN and concurrency: `assertNotLastAdmin` alone is a read-then-act check — two admins
 * leaving (or removing each other) at the same moment could both pass it and leave the family
 * without an admin, or with nobody who can sign in at all. `claimAdminExit` closes that gap
 * with a conditional update (see there); every removal/demotion path should go through it.
 */

/** Filter for members that are linked to a user account. */
const HAS_ACCOUNT = { $type: 'objectId' };

/** `409 LAST_ADMIN` (contract §1). */
export function lastAdminError() {
  return ApiError.conflict('LAST_ADMIN', 'The family needs at least one admin');
}

/**
 * Throws `409 LAST_ADMIN` when taking the admin role away from `member` (leaving, being
 * deleted or being demoted) would leave the family without an admin.
 *
 * Only admins **with an account** count as "another admin": a managed profile (no user) can
 * never sign in, so a family whose only admin is a managed profile could not be administered.
 *
 * Read-only: on its own it is **not** race-safe (two concurrent callers can both pass) — use
 * `claimAdminExit` / `removeMemberGuarded` for the actual removal or demotion.
 *
 * @param {{ _id: any, familyId: any, role?: string }} member the member losing the admin role
 * @param {{ leaving?: boolean }} [opts]
 *   `leaving: true` (default) — the member leaves the family: when nobody else is left the
 *   family is dissolved instead, so no admin is needed. Pass `leaving: false` for a demotion,
 *   where the member stays and the family always needs an admin.
 * @returns {Promise<void>}
 */
export async function assertNotLastAdmin(member, { leaving = true } = {}) {
  if (!member || member.role !== ROLE.ADMIN) return;
  const familyId = toId(member.familyId);
  const memberId = toId(member._id ?? member.id);
  if (leaving) {
    const others = await Member.countDocuments({ familyId, _id: { $ne: memberId } });
    if (others === 0) return;
  }
  const otherAdmins = await Member.countDocuments({
    familyId,
    _id: { $ne: memberId },
    role: ROLE.ADMIN,
    userId: HAS_ACCOUNT,
  });
  if (otherAdmins === 0) throw lastAdminError();
}

/** Attempts of `claimAdminExit` before a `409 LAST_ADMIN` is final. */
const CLAIM_ATTEMPTS = 3;
/** Jittered pause between attempts (≈ 10–150 ms in total), so racing requests stop colliding. */
const claimBackoff = (attempt) => new Promise((resolve) => setTimeout(resolve, attempt * (10 + Math.floor(Math.random() * 40))));

/**
 * Race-safe LAST_ADMIN guard for taking the admin role away from `member` (it leaves, is
 * removed, or is demoted).
 *
 *   1. Plain `assertNotLastAdmin` first — a plain 409 writes nothing.
 *   2. **Claim**: one conditional update demotes the member (`role: admin → member`), so every
 *      concurrent guard of the same family now sees one admin fewer.
 *   3. Check again; when no other admin with an account is left, the role is given back.
 *
 * A `409` from step 1 or 3 is retried after a short jittered pause (`CLAIM_ATTEMPTS` in all):
 * for a moment a concurrent guard's claim looks exactly like a missing admin, and once that
 * request has finished (e.g. the other one of the last two admins has left) the retry sees
 * the real state. Only then is `409 LAST_ADMIN` final.
 *
 * Two admins racing therefore never both pass: whoever checks second sees the other's claim.
 * The worst case under heavy contention is a `409` the client can retry — never a family
 * without an admin. (A crash between steps 2 and 3 leaves the member demoted while another
 * admin was present at step 1; the removal flows repair a family without admins, see
 * `settleFamily`.)
 *
 * @param {{ _id: any, familyId: any, role?: string }} member the member losing the admin role
 * @param {{ leaving?: boolean }} [opts] as for `assertNotLastAdmin`
 * @returns {Promise<{ claimed: boolean, release: () => Promise<void> }>}
 *   `release()` gives the admin role back; call it when the operation fails after the guard
 *   (no-op when nothing was claimed or the member is gone). For a demotion (`leaving: false`)
 *   a successful guard **is** the demotion — do not write the role again.
 * @throws {ApiError} 409 LAST_ADMIN
 */
export async function claimAdminExit(member, { leaving = true } = {}) {
  if (!member || member.role !== ROLE.ADMIN) return { claimed: false, release: async () => {} };
  const familyId = toId(member.familyId);
  const memberId = toId(member._id ?? member.id);

  for (let attempt = 1; ; attempt += 1) {
    try {
      return await claimOnce(member, { familyId, memberId, leaving });
    } catch (err) {
      if (err?.code !== 'LAST_ADMIN' || attempt >= CLAIM_ATTEMPTS) throw err;
    }
    await claimBackoff(attempt);
  }
}

/** Steps 1–3 of `claimAdminExit`, once. */
async function claimOnce(member, { familyId, memberId, leaving }) {
  await assertNotLastAdmin(member, { leaving });
  const res = await Member.updateOne({ _id: memberId, familyId, role: ROLE.ADMIN }, { $set: { role: ROLE.MEMBER } });
  const claimed = (res.modifiedCount ?? 0) > 0;
  const release = async () => {
    if (claimed) await Member.updateOne({ _id: memberId, familyId, role: ROLE.MEMBER }, { $set: { role: ROLE.ADMIN } });
  };
  try {
    // Self is excluded from the count, so only the claims of *other* members matter here.
    await assertNotLastAdmin(member, { leaving });
  } catch (err) {
    await release();
    throw err;
  }
  return { claimed, release };
}

/**
 * Signs a user out everywhere and forgets their push devices.
 *
 * Refresh-token rows are **deleted**, not flagged as revoked: services/tokens.js treats a
 * revoked token as theft and would revoke every session — including one the user opens
 * later — when a stale device refreshes (same decision as b-auth for password resets).
 * @returns {Promise<{ tokens: number, devices: number }>}
 */
export async function endUserSessions(userId) {
  if (!userId) return { tokens: 0, devices: 0 };
  const [tokens, devices] = await Promise.all([
    RefreshToken.deleteMany({ userId }),
    Device.deleteMany({ userId }),
  ]);
  return { tokens: tokens.deletedCount ?? 0, devices: devices.deletedCount ?? 0 };
}

/**
 * Deletes a family and every family-scoped document (tasks, ledger entries, goals, notices,
 * SOS alerts, emergency cards, members) and unlinks every user that still points at it.
 * Sessions and devices of those users are kept (they stay signed in without a family).
 *
 * The Family row goes first so its invite code stops working at once; a member that joins
 * during the cascade is removed by the member clean-up that follows.
 *
 * @param {any} familyId
 * @returns {Promise<Record<string, number>>} deleted documents per collection
 */
export async function deleteFamilyCascade(familyId) {
  const id = toId(familyId);
  if (!id) throw new TypeError('deleteFamilyCascade: familyId is required');
  const family = await Family.deleteOne({ _id: id });
  const memberIds = (await Member.find({ familyId: id }).select('_id').lean()).map((m) => m._id);
  const [tasks, ledgerEntries, goals, notices, sosAlerts, emergencyCards] = await Promise.all([
    Task.deleteMany({ familyId: id }),
    LedgerEntry.deleteMany({ familyId: id }),
    Goal.deleteMany({ familyId: id }),
    Notice.deleteMany({ familyId: id }),
    SosAlert.deleteMany({ familyId: id }),
    EmergencyCard.deleteMany({ $or: [{ familyId: id }, { memberId: { $in: memberIds } }] }),
  ]);
  const users = await User.updateMany({ familyId: id }, { $set: { familyId: null, memberId: null } });
  const members = await Member.deleteMany({ familyId: id });
  return {
    families: family.deletedCount ?? 0,
    members: members.deletedCount ?? 0,
    tasks: tasks.deletedCount ?? 0,
    ledgerEntries: ledgerEntries.deletedCount ?? 0,
    goals: goals.deletedCount ?? 0,
    notices: notices.deletedCount ?? 0,
    sosAlerts: sosAlerts.deletedCount ?? 0,
    emergencyCards: emergencyCards.deletedCount ?? 0,
    usersUnlinked: users.modifiedCount ?? 0,
  };
}

/** Samples taken before a family without an admin is repaired, and the pause between them. */
const REPAIR_SAMPLES = 4;
const REPAIR_SAMPLE_GAP_MS = 50;
const pause = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/** Remaining members of a family, longest-standing first. */
function loadRemaining(familyId) {
  return Member.find({ familyId }).select('_id userId role createdAt').sort({ createdAt: 1, _id: 1 }).lean();
}

const accountAdmins = (members) => members.filter((m) => m.userId && m.role === ROLE.ADMIN);

/**
 * Keeps the family consistent after a member was removed (step 6 in the file header).
 *
 * Repairing a family without an admin (promote its longest-standing member with an account)
 * is a last resort for removals that bypassed `claimAdminExit`. A concurrent guard's claim
 * makes an admin look demoted for a few milliseconds, so the state is sampled a few times
 * (≤ 150 ms, only on this rare path) and nobody is promoted while an admin shows up again.
 * @returns {Promise<boolean>} true when the family was deleted (no members left)
 */
async function settleFamily(familyId, { family = null, removedUserId = null } = {}) {
  let remaining = await loadRemaining(familyId);
  for (let sample = 1; remaining.length && sample < REPAIR_SAMPLES; sample += 1) {
    const needsAdmin = remaining.some((m) => m.userId) && !accountAdmins(remaining).length;
    if (!needsAdmin) break;
    await pause(REPAIR_SAMPLE_GAP_MS);
    remaining = await loadRemaining(familyId);
  }
  if (!remaining.length) {
    await deleteFamilyCascade(familyId);
    return true;
  }

  const withAccount = remaining.filter((m) => m.userId);
  const admins = accountAdmins(remaining);
  if (withAccount.length && !admins.length) {
    const heir = withAccount[0];
    await Member.updateOne({ _id: heir._id, familyId }, { $set: { role: ROLE.ADMIN } });
    admins.push({ ...heir, role: ROLE.ADMIN });
    logger.warn('A family was left without an admin after concurrent removals; promoted its longest-standing member');
  }

  if (removedUserId && admins.length) {
    const current = family && family.ownerId !== undefined ? family : await Family.findById(familyId).select('ownerId').lean();
    if (current && sameId(current.ownerId, removedUserId)) {
      await Family.updateOne({ _id: familyId, ownerId: removedUserId }, { $set: { ownerId: admins[0].userId } });
    }
  }
  return false;
}

/**
 * Step 1 of the cascade: persists the lazy expiry, then resolves each still-active alert with a
 * conditional update (an alert the owner resolves at the same moment keeps their resolution).
 * @returns {Promise<{ expired: number, closedIds: string[] }>}
 */
async function closeActiveSos({ familyId, memberId, resolverId, now }) {
  const expired = await SosAlert.expireStale({ familyId, memberId }, now);
  const active = await SosAlert.find({ familyId, memberId, status: 'active' }).select('_id').lean();
  const closedIds = [];
  for (const { _id } of active) {
    const closed = await SosAlert.findOneAndUpdate(
      { _id, familyId, memberId, status: 'active' },
      // No resolution is claimed: the member was removed, nobody confirmed they are safe.
      { $set: { status: 'resolved', resolvedAt: now, resolvedById: resolverId, resolution: null } },
      { projection: { _id: 1 } },
    ).lean();
    if (closed) closedIds.push(toId(closed._id));
  }
  return { expired, closedIds };
}

/**
 * Removes one member from its family with the full cascade (see the file header).
 * Does **not** check permissions or the LAST_ADMIN rule — use `removeMemberGuarded` (or call
 * `claimAdminExit` first).
 *
 * @param {object} p
 * @param {{ _id: any, familyId: any, userId?: any }} p.member  member doc or lean object
 * @param {object|null} [p.family]   the member's family (doc/lean) — saves a query for the owner check
 * @param {any} [p.actorId]          **Member** id of who removes it (admin, or the member itself);
 *                                   stored as `resolvedById` on resolved SOS alerts (default: the member)
 * @param {boolean} [p.endSessions]  default true: delete the user's refresh tokens + devices.
 *                                   `false` keeps the user signed in (voluntary leave).
 * @param {Date} [p.now]
 * @returns {Promise<{ memberId: string, userId: string|null, familyId: string, removed: boolean,
 *   tasksDeleted: number, sosResolved: number, sosExpired: number, cardDeleted: boolean,
 *   familyDeleted: boolean }>}
 */
export async function removeMemberCascade({ member, family = null, actorId = null, endSessions = true, now = new Date() }) {
  const memberId = toId(member?._id ?? member?.id);
  const familyId = toId(member?.familyId);
  if (!memberId || !familyId) throw new TypeError('removeMemberCascade: member with _id and familyId is required');
  const userId = toId(member.userId);
  const resolverId = toId(actorId) ?? memberId;

  const [sos, tasks, cards] = await Promise.all([
    closeActiveSos({ familyId, memberId, resolverId, now }),
    Task.deleteMany({ familyId, assigneeId: memberId, status: 'pending' }),
    EmergencyCard.deleteMany({ memberId }),
  ]);
  // Names for the sos_resolved push must be read while the member row still exists.
  const names = sos.closedIds.length ? await getMemberMap(familyId) : null;
  const removed = await Member.deleteOne({ _id: memberId, familyId });

  if (userId) {
    await User.updateOne({ _id: userId, memberId }, { $set: { familyId: null, memberId: null } });
    if (endSessions) await endUserSessions(userId);
  }

  const familyDeleted = await settleFamily(familyId, { family, removedUserId: userId });
  if (!familyDeleted) {
    // Sent after the unlink, so the removed member is no longer a recipient; the resolver is
    // excluded by notifySosResolved. Fire-and-forget: it never throws.
    for (const alertId of sos.closedIds) {
      void notifySosResolved({ familyId, alertId, ownerMemberId: memberId, resolverMemberId: resolverId, resolution: null, members: names });
    }
  }
  return {
    memberId,
    userId,
    familyId,
    removed: (removed.deletedCount ?? 0) > 0,
    tasksDeleted: tasks.deletedCount ?? 0,
    sosResolved: sos.closedIds.length,
    sosExpired: sos.expired,
    cardDeleted: (cards.deletedCount ?? 0) > 0,
    familyDeleted,
  };
}

/**
 * `claimAdminExit` + `removeMemberCascade`: the race-safe way to take a member out of a family
 * (admin removal `DELETE /family/members/:id`, and `removeSelfFromFamily`). When the cascade
 * fails before the member row is gone, the admin role is given back.
 *
 * @param {Parameters<typeof removeMemberCascade>[0]} params same as `removeMemberCascade`
 * @returns {ReturnType<typeof removeMemberCascade>}
 * @throws {ApiError} 409 LAST_ADMIN
 */
export async function removeMemberGuarded(params) {
  const guard = await claimAdminExit(params?.member, { leaving: true });
  try {
    return await removeMemberCascade(params);
  } catch (err) {
    await guard.release().catch((e) => logger.error(`Admin role restore failed: ${e?.name ?? 'Error'}`));
    throw err;
  }
}

/**
 * A member takes themselves out of their family (`POST /me/leave-family`, `DELETE /me`):
 *   - the only member → the whole family is deleted (contract §5);
 *   - otherwise the race-safe LAST_ADMIN guard applies, then `removeMemberCascade`
 *     (`removeMemberGuarded`, actor = the member).
 *
 * @param {object} p
 * @param {object} p.member           the caller's member (doc or lean)
 * @param {object|null} [p.family]
 * @param {boolean} [p.endSessions]   default false: the user stays signed in
 * @returns {Promise<{ familyDeleted: boolean }>}
 * @throws {ApiError} 409 LAST_ADMIN
 */
export async function removeSelfFromFamily({ member, family = null, endSessions = false }) {
  const memberId = toId(member?._id ?? member?.id);
  const familyId = toId(member?.familyId);
  if (!memberId || !familyId) throw new TypeError('removeSelfFromFamily: member with _id and familyId is required');

  const others = await Member.countDocuments({ familyId, _id: { $ne: memberId } });
  if (others === 0) {
    await deleteFamilyCascade(familyId);
    if (endSessions) await endUserSessions(member.userId);
    return { familyDeleted: true };
  }
  const result = await removeMemberGuarded({ member, family, actorId: memberId, endSessions });
  return { familyDeleted: result.familyDeleted };
}
