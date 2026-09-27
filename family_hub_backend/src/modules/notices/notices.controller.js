import { created, ok, paged } from '../../lib/response.js';
import * as service from './notices.service.js';

/** HTTP layer of `/notices` (docs/03-API_CONTRACT.md §9): read `req.valid`, call the service, send the envelope. */

export async function list(req, res) {
  paged(res, await service.listNotices(req.user, req.valid.query));
}

export async function create(req, res) {
  created(res, await service.createNotice(req.user, req.valid.body));
}

export async function update(req, res) {
  ok(res, await service.updateNotice(req.user, req.valid.params.id, req.valid.body));
}

export async function remove(req, res) {
  ok(res, await service.deleteNotice(req.user, req.valid.params.id));
}
