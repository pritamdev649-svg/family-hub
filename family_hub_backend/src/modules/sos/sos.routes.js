import { Router } from 'express';
import { validate } from '../../lib/validate.js';
import { familyMember } from '../../middleware/auth.js';
import * as controller from './sos.controller.js';
import { createSosBody, resolveSosBody, sosHistoryQuery, sosIdParams, sosLocationBody } from './sos.schemas.js';

/**
 * `/api/v1/sos` (docs/03-API_CONTRACT.md §10). Every route needs a signed-in family member; the
 * owner / admin rules live in sos.service.js.
 *
 *   POST /                raise an SOS          → 201 SosAlert (200 with the active one when already raised)
 *   GET  /active          active alerts of the family (incl. the caller's own)
 *   GET  /history         resolved / expired alerts, newest first (paginated)
 *   GET  /:id             one alert incl. trail (≤ 100 newest points, oldest first)
 *   POST /:id/location    live location (owner only, 3 s store throttle)
 *   POST /:id/resolve     end it (owner or admin, idempotent)
 *
 * `/active` and `/history` are declared before `/:id`. Order inside a route: 401 → 403 NO_FAMILY →
 * 400 (malformed id) → 422 (query / body) → service (404 → 403 → 409 → 403 LOCATION_SHARING_DISABLED).
 */
const router = Router();

router.use(...familyMember);

router.post('/', validate({ body: createSosBody }), controller.create);
router.get('/active', controller.active);
router.get('/history', validate({ query: sosHistoryQuery }), controller.history);
router.get('/:id', validate({ params: sosIdParams }), controller.get);
router.post('/:id/location', validate({ params: sosIdParams, body: sosLocationBody }), controller.location);
router.post('/:id/resolve', validate({ params: sosIdParams, body: resolveSosBody }), controller.resolve);

export default router;
