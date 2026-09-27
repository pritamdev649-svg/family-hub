import { ok } from '../../lib/response.js';
import { buildExport } from './me.export.js';
import * as service from './me.service.js';

/** HTTP layer of `/me/*`: read `req.valid`, call the service, send the envelope. */

export async function updateMe(req, res) {
  ok(res, await service.updateMe(req.user, req.member, req.valid.body));
}

export async function updateLocation(req, res) {
  ok(res, await service.updateLocation(req.user, req.valid.body));
}

export async function registerDevice(req, res) {
  ok(res, await service.registerDevice(req.user, req.valid.body));
}

export async function unregisterDevice(req, res) {
  ok(res, await service.unregisterDevice(req.user, req.valid.params.token));
}

export async function exportData(req, res) {
  // Personal data: never cached by browsers or proxies.
  res.set('Cache-Control', 'no-store');
  ok(res, await buildExport(req.user));
}

export async function deleteMe(req, res) {
  ok(res, await service.deleteAccount(req.user, req.member, req.valid.body));
}

export async function leaveFamily(req, res) {
  ok(res, await service.leaveFamily(req.user, req.member));
}
