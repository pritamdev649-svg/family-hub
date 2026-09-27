import { created, ok, paged } from '../../lib/response.js';
import * as service from './tasks.service.js';

/** HTTP layer of `/tasks` (docs/03-API_CONTRACT.md §7): read `req.valid`, call the service, send the envelope. */

export async function list(req, res) {
  paged(res, await service.listTasks(req.user, req.valid.query));
}

export async function create(req, res) {
  created(res, await service.createTask(req.user, req.valid.body));
}

export async function get(req, res) {
  ok(res, await service.getTask(req.user, req.valid.params.id));
}

export async function update(req, res) {
  ok(res, await service.updateTask(req.user, req.valid.params.id, req.valid.body));
}

export async function complete(req, res) {
  ok(res, await service.completeTask(req.user, req.valid.params.id));
}

export async function reopen(req, res) {
  ok(res, await service.reopenTask(req.user, req.valid.params.id));
}

export async function remove(req, res) {
  ok(res, await service.deleteTask(req.user, req.valid.params.id));
}
