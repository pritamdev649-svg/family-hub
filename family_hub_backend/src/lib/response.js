/** Success envelope: `{ success: true, data, meta? }` (docs/03-API_CONTRACT.md §1). */
export function ok(res, data = null, { status = 200, meta } = {}) {
  const body = { success: true, data };
  if (meta) body.meta = meta;
  return res.status(status).json(body);
}

export function created(res, data) {
  return ok(res, data, { status: 201 });
}

/** Paginated list: `data` = items array, `meta` = { page, limit, total, hasMore }. */
export function paged(res, { items, page, limit, total }) {
  return ok(res, items, { meta: { page, limit, total, hasMore: page * limit < total } });
}
