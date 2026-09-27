import { Router } from 'express';
import { validate } from '../../lib/validate.js';
import { familyMember } from '../../middleware/auth.js';
import * as controller from './dashboard.controller.js';
import { dashboardQuery } from './dashboard.schemas.js';

/**
 * `/api/v1/dashboard` (docs/03-API_CONTRACT.md §11). Any signed-in family member; what each role
 * sees (invite code, ledger scope) is decided in dashboard.service.js.
 *
 *   GET /    family, me, members with task counters, my tasks, goals, notices, active SOS,
 *            month summary — in one request
 *
 * Order: 401 (no / bad token) → 403 NO_FAMILY → service.
 */
const router = Router();

router.use(...familyMember);

router.get('/', validate({ query: dashboardQuery }), controller.get);

export default router;
