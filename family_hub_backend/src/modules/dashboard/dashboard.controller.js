import { ok } from '../../lib/response.js';
import * as service from './dashboard.service.js';

/**
 * HTTP layer of `/dashboard` (docs/03-API_CONTRACT.md §11): call the service, send the envelope.
 * The payload carries live SOS locations, member contact data and money totals, so no browser or
 * proxy may store it.
 */
export async function get(req, res) {
  res.set('Cache-Control', 'private, no-store');
  ok(res, await service.getDashboard(req.user));
}
