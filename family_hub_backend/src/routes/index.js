import { Router } from 'express';
import { env } from '../config/env.js';
import { isDbUp } from '../config/db.js';
import { ok } from '../lib/response.js';
import authRoutes from '../modules/auth/auth.routes.js';
import dashboardRoutes from '../modules/dashboard/dashboard.routes.js';
import emergencyCardsRoutes from '../modules/emergencyCards/emergencyCards.routes.js';
import familyRoutes from '../modules/family/family.routes.js';
import goalsRoutes from '../modules/ledger/goals.routes.js';
import ledgerRoutes from '../modules/ledger/ledger.routes.js';
import meRoutes from '../modules/me/me.routes.js';
import noticesRoutes from '../modules/notices/notices.routes.js';
import sosRoutes from '../modules/sos/sos.routes.js';
import tasksRoutes from '../modules/tasks/tasks.routes.js';
import uploadsRoutes from '../modules/uploads/uploads.routes.js';

/**
 * Mounts every module router under /api/v1 (docs/06-BACKEND_GUIDE.md §2 table).
 * Order matters: the emergency-card router is mounted **before** the family router so
 * `/family/members/:memberId/emergency-card` is not swallowed by `/family/members/:id`.
 */
const router = Router();

/** GET /health — liveness + DB state (contract §3). Always 200 so the process is "alive". */
router.get('/health', (_req, res) => {
  res.setHeader('Cache-Control', 'no-store');
  ok(res, { status: 'ok', db: isDbUp() ? 'up' : 'down', version: env.version });
});

router.use('/auth', authRoutes);
router.use('/me', meRoutes);
router.use('/family/members/:memberId/emergency-card', emergencyCardsRoutes);
router.use('/family', familyRoutes);
router.use('/tasks', tasksRoutes);
router.use('/ledger', ledgerRoutes);
router.use('/goals', goalsRoutes);
router.use('/notices', noticesRoutes);
router.use('/sos', sosRoutes);
router.use('/dashboard', dashboardRoutes);
router.use('/uploads', uploadsRoutes);

export default router;
