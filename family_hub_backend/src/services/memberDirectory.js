import { toId } from '../lib/access.js';
import { ROLE } from '../lib/constants.js';
import { Member } from '../models/index.js';

/**
 * Member lookups used to denormalise names into responses (`assigneeName`, `createdByName`,
 * `authorName`, `memberName`, …). Families are small, so one query per request loads them all.
 */

/**
 * @param {string} familyId
 * @returns {Promise<Map<string, object>>} memberId (hex string) → lean member
 */
export async function getMemberMap(familyId) {
  const map = new Map();
  if (!familyId) return map;
  const members = await Member.find({ familyId }).lean();
  for (const m of members) map.set(String(m._id), m);
  return map;
}

/** The member for an id (any id shape) or null. */
export function memberOf(map, id) {
  const key = toId(id);
  return key ? (map?.get(key) ?? null) : null;
}

/** Name of a member or null (e.g. deleted member). */
export function nameOf(map, id) {
  return memberOf(map, id)?.name ?? null;
}

/** Avatar URL of a member or null. */
export function avatarOf(map, id) {
  return memberOf(map, id)?.avatarUrl ?? null;
}

/** Number of members in a family. */
export function countMembers(familyId) {
  if (!familyId) return Promise.resolve(0);
  return Member.countDocuments({ familyId }).exec();
}

/** Number of admins in a family (LAST_ADMIN checks). */
export function countAdmins(familyId) {
  if (!familyId) return Promise.resolve(0);
  return Member.countDocuments({ familyId, role: ROLE.ADMIN }).exec();
}
