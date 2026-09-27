import { Router } from 'express';
import { validate } from '../../lib/validate.js';
import { requireAuth, requireFamily } from '../../middleware/auth.js';
import * as controller from './me.controller.js';
import {
  deleteMeSchema,
  deviceTokenParams,
  registerDeviceSchema,
  updateLocationSchema,
  updateMeSchema,
} from './me.schemas.js';

/**
 * `/api/v1/me` — the signed-in user's own account (docs/03-API_CONTRACT.md §5). Every route
 * needs a valid access token. Location and leave-family also need a family (`403 NO_FAMILY`);
 * profile, devices, export and account deletion work without one.
 *
 * Order inside a route: auth → family → validation → handler, so an anonymous caller always gets
 * `401` and a caller without a family `403 NO_FAMILY` before any `422`.
 */
const router = Router();

router.use(requireAuth);

router.patch('/', validate({ body: updateMeSchema }), controller.updateMe);
router.delete('/', validate({ body: deleteMeSchema }), controller.deleteMe);
router.put('/location', requireFamily, validate({ body: updateLocationSchema }), controller.updateLocation);
router.post('/devices', validate({ body: registerDeviceSchema }), controller.registerDevice);
router.delete('/devices/:token', validate({ params: deviceTokenParams }), controller.unregisterDevice);
router.get('/export', controller.exportData);
router.post('/leave-family', requireFamily, controller.leaveFamily);

export default router;
