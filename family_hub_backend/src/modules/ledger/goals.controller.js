import { created, ok } from '../../lib/response.js';
import * as service from './goals.service.js';

/** HTTP layer of `/goals` (docs/03-API_CONTRACT.md §8): read `req.valid`, call the service, send the envelope. */

function noStore(res) {
  res.set('Cache-Control', 'private, no-store');
}

export async function list(req, res) {
  noStore(res);
  ok(res, await service.listGoals(req.user, req.valid.query));
}

export async function create(req, res) {
  noStore(res);
  created(res, await service.createGoal(req.user, req.valid.body));
}

export async function update(req, res) {
  noStore(res);
  ok(res, await service.updateGoal(req.user, req.valid.params.id, req.valid.body));
}

export async function remove(req, res) {
  noStore(res);
  ok(res, await service.deleteGoal(req.user, req.valid.params.id));
}

export async function contribute(req, res) {
  noStore(res);
  created(res, await service.contribute(req.user, req.valid.params.id, req.valid.body));
}
