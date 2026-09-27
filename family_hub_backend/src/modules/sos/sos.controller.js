import { created, ok, paged } from '../../lib/response.js';
import * as service from './sos.service.js';

/**
 * HTTP layer of `/sos` (docs/03-API_CONTRACT.md §10): read `req.valid`, call the service, send the
 * envelope. Alerts carry live locations, so no response may be stored by browsers or proxies.
 */

function noStore(res) {
  res.set('Cache-Control', 'private, no-store');
}

/** 201 for a new alert, 200 when the caller's active alert is returned (idempotent). */
export async function create(req, res) {
  noStore(res);
  const { alert, created: isNew } = await service.createAlert(req.user, req.valid.body);
  if (isNew) created(res, alert);
  else ok(res, alert);
}

export async function active(req, res) {
  noStore(res);
  ok(res, await service.listActive(req.user));
}

export async function history(req, res) {
  noStore(res);
  paged(res, await service.listHistory(req.user, req.valid.query));
}

export async function get(req, res) {
  noStore(res);
  ok(res, await service.getAlert(req.user, req.valid.params.id));
}

export async function location(req, res) {
  noStore(res);
  ok(res, await service.updateLocation(req.user, req.valid.params.id, req.valid.body));
}

export async function resolve(req, res) {
  noStore(res);
  ok(res, await service.resolveAlert(req.user, req.valid.params.id, req.valid.body));
}
