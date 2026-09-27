import { created, ok, paged } from '../../lib/response.js';
import * as service from './ledger.service.js';

/**
 * HTTP layer of `/ledger` (docs/03-API_CONTRACT.md §8): read `req.valid`, call the service, send the
 * envelope. Money data is private to the family, so responses must not be stored by shared caches.
 */

function noStore(res) {
  res.set('Cache-Control', 'private, no-store');
}

export async function listEntries(req, res) {
  noStore(res);
  paged(res, await service.listEntries(req.user, req.valid.query));
}

export async function createEntry(req, res) {
  noStore(res);
  created(res, await service.createEntry(req.user, req.valid.body));
}

export async function updateEntry(req, res) {
  noStore(res);
  ok(res, await service.updateEntry(req.user, req.valid.params.id, req.valid.body));
}

export async function deleteEntry(req, res) {
  noStore(res);
  ok(res, await service.deleteEntry(req.user, req.valid.params.id));
}

export async function summary(req, res) {
  noStore(res);
  ok(res, await service.getSummary(req.user, req.valid.query));
}
