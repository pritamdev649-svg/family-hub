import { DEFAULT_PAGE_LIMIT, MAX_PAGE_LIMIT } from './constants.js';

/**
 * Pagination helpers (contract §1: `?page=1&limit=20`, page ≥ 1, 1 ≤ limit ≤ 100).
 * Pair with `validate({ query: z.object({ ...pagination }) })` from lib/validate.js and
 * respond with `paged(res, result)` from lib/response.js.
 */

/** Clamps page/limit to the contract bounds (defensive; zod already validates). */
export function normalizePage({ page, limit } = {}) {
  const p = Number.isInteger(Number(page)) && Number(page) >= 1 ? Number(page) : 1;
  const l = Number.isInteger(Number(limit)) && Number(limit) >= 1 ? Math.min(Number(limit), MAX_PAGE_LIMIT) : DEFAULT_PAGE_LIMIT;
  return { page: p, limit: l, skip: (p - 1) * l };
}

/**
 * Paginated `find` + `countDocuments` (run in parallel).
 *
 * @param {import('mongoose').Model} Model
 * @param {object} filter      Mongo filter — must include `familyId` for family data
 * @param {object} [opts]
 * @param {number} [opts.page=1]
 * @param {number} [opts.limit=20]
 * @param {object|string} [opts.sort]  e.g. `{ createdAt: -1, _id: -1 }` (add `_id` for a stable order)
 * @param {object|string} [opts.projection]
 * @param {boolean} [opts.lean=false]  true → plain objects (with `_id`, no `id` virtual)
 * @param {object|string|Array} [opts.populate]
 * @returns {Promise<{ items: any[], page: number, limit: number, total: number }>}
 */
export async function paginate(Model, filter = {}, { page, limit, sort, projection, lean = false, populate } = {}) {
  const { page: p, limit: l, skip } = normalizePage({ page, limit });
  let query = Model.find(filter, projection).skip(skip).limit(l);
  if (sort) query = query.sort(sort);
  if (populate) query = query.populate(populate);
  if (lean) query = query.lean();
  const [items, total] = await Promise.all([query.exec(), Model.countDocuments(filter).exec()]);
  return { items, page: p, limit: l, total };
}

/**
 * Paginates an aggregation pipeline with a single `$facet` round trip — useful for sorts
 * Mongo `find` cannot express (e.g. "dueDate asc, nulls last"). Items are plain objects.
 *
 * @param {import('mongoose').Model} Model
 * @param {object[]} pipeline  stages producing the full, sorted result set (start with `$match` on familyId)
 * @returns {Promise<{ items: object[], page: number, limit: number, total: number }>}
 */
export async function paginateAggregate(Model, pipeline, { page, limit } = {}) {
  const { page: p, limit: l, skip } = normalizePage({ page, limit });
  const [res] = await Model.aggregate([
    ...pipeline,
    { $facet: { items: [{ $skip: skip }, { $limit: l }], total: [{ $count: 'n' }] } },
  ]).exec();
  return { items: res?.items ?? [], page: p, limit: l, total: res?.total?.[0]?.n ?? 0 };
}

/** Paginates an in-memory, already sorted array (small family-sized lists). */
export function paginateArray(list, { page, limit } = {}) {
  const { page: p, limit: l, skip } = normalizePage({ page, limit });
  return { items: list.slice(skip, skip + l), page: p, limit: l, total: list.length };
}
