import { ApiError } from './ApiError.js';
import { ROLE } from './constants.js';

/**
 * Family-scoped access helpers (docs/06-BACKEND_GUIDE.md rule 3: family scoping = security).
 * A document of another family is reported as `404 NOT_FOUND` — never 403, never leaked.
 */

/** String form of an ObjectId / populated doc / string; null for null-ish. */
export function toId(value) {
  if (value === null || value === undefined) return null;
  if (typeof value === 'string') return value;
  if (typeof value === 'object' && value._bsontype !== 'ObjectId') {
    const inner = value._id ?? value.id;
    if (inner !== undefined && inner !== null && inner !== value) return toId(inner);
  }
  return String(value);
}

/** Compares ids of any shape (ObjectId, string, populated doc). */
export function sameId(a, b) {
  const x = toId(a);
  const y = toId(b);
  return x !== null && y !== null && x === y;
}

/** true for a 24-hex ObjectId string or an ObjectId instance. */
export function isObjectId(value) {
  if (value && typeof value === 'object' && value._bsontype === 'ObjectId') return true;
  return typeof value === 'string' && /^[a-f0-9]{24}$/i.test(value);
}

/**
 * Loads a document by id **within a family** or throws `NOT_FOUND`.
 *
 * @template T
 * @param {import('mongoose').Model<T>} Model
 * @param {string} id
 * @param {string} familyId   usually `req.user.familyId`
 * @param {{ lean?: boolean, select?: string|object, populate?: any, session?: any }} [opts]
 * @returns {Promise<T>}
 */
export async function findInFamily(Model, id, familyId, { lean = false, select, populate, session } = {}) {
  if (!isObjectId(id) || !isObjectId(familyId)) throw ApiError.notFound();
  let query = Model.findOne({ _id: id, familyId });
  if (select) query = query.select(select);
  if (populate) query = query.populate(populate);
  if (session) query = query.session(session);
  if (lean) query = query.lean();
  const doc = await query.exec();
  if (!doc) throw ApiError.notFound();
  return doc;
}

/** Base filter for family data: `{ familyId: req.user.familyId, ...extra }`. */
export function familyFilter(req, extra = {}) {
  assertFamily(req);
  return { familyId: req.user.familyId, ...extra };
}

export function isAdmin(req) {
  return req?.user?.role === ROLE.ADMIN;
}

/** true when `memberId` is the caller's own member id. */
export function isSelf(req, memberId) {
  return sameId(req?.user?.memberId, memberId);
}

/** 403 NO_FAMILY unless the caller belongs to a family. */
export function assertFamily(req) {
  if (!req?.user?.familyId) throw ApiError.noFamily();
}

/** 403 FORBIDDEN unless the caller is a family admin. */
export function assertAdmin(req) {
  assertFamily(req);
  if (!isAdmin(req)) throw ApiError.forbidden();
}

/** 403 FORBIDDEN unless `memberId` is the caller or the caller is an admin. */
export function assertSelfOrAdmin(req, memberId) {
  assertFamily(req);
  if (!isSelf(req, memberId) && !isAdmin(req)) throw ApiError.forbidden();
}
