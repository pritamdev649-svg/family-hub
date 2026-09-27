import { ok } from '../../lib/response.js';
import * as service from './emergencyCards.service.js';

/**
 * HTTP layer of `/family/members/:memberId/emergency-card`: read `req.valid`, call the service,
 * send the envelope. Cards hold health data, so no response may be stored by browsers or proxies.
 */

function noStore(res) {
  res.set('Cache-Control', 'private, no-store');
}

export async function getCard(req, res) {
  noStore(res);
  ok(res, await service.getCard(req.user, req.valid.params.memberId));
}

export async function putCard(req, res) {
  noStore(res);
  ok(res, await service.saveCard(req.user, req.valid.params.memberId, req.valid.body));
}
