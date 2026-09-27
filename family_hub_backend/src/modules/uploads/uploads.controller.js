import { ok } from '../../lib/response.js';
import * as service from './uploads.service.js';

/**
 * HTTP layer of `/uploads` (docs/03-API_CONTRACT.md §12): read `req.valid`, call the service,
 * send the envelope. A signature is a short-lived upload credential, so it must never be stored
 * by browsers or proxies.
 */

export function signature(req, res) {
  res.set('Cache-Control', 'no-store');
  ok(res, service.createSignature(req.user, req.valid.body));
}
