import { created, ok } from '../../lib/response.js';
import * as service from './auth.service.js';

/** HTTP layer of `/auth/*`: read `req.valid`, call the service, send the envelope. */

/** Client info stored with refresh tokens (truncated by services/tokens.js). */
const clientMeta = (req) => ({ ip: req.ip, userAgent: req.get('user-agent') });

export async function register(req, res) {
  created(res, await service.register(req.valid.body, { locale: req.locale, meta: clientMeta(req) }));
}

export async function login(req, res) {
  ok(res, await service.login(req.valid.body, { meta: clientMeta(req) }));
}

export async function refresh(req, res) {
  ok(res, await service.refresh(req.valid.body, { meta: clientMeta(req) }));
}

export async function logout(req, res) {
  ok(res, await service.logout(req.user, req.valid.body));
}

export async function verifyEmail(req, res) {
  ok(res, await service.verifyEmail(req.user, req.member, req.valid.body));
}

export async function resendVerification(req, res) {
  ok(res, await service.resendVerification(req.user));
}

export async function forgotPassword(req, res) {
  ok(res, await service.forgotPassword(req.valid.body));
}

export async function resetPassword(req, res) {
  ok(res, await service.resetPassword(req.valid.body));
}

export async function changePassword(req, res) {
  ok(res, await service.changePassword(req.user, req.valid.body, { meta: clientMeta(req) }));
}

export async function me(req, res) {
  ok(res, await service.me(req.user, req.member));
}
