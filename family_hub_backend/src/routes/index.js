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

router.get('/delete-account', (_req, res) => {
  res.send(`
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Delete FamilyHub Account</title>
      <style>
        body { font-family: system-ui, -apple-system, sans-serif; max-width: 600px; margin: 40px auto; padding: 20px; line-height: 1.6; color: #333; }
        h1 { color: #d32f2f; }
        .container { background: #f9f9f9; padding: 30px; border-radius: 8px; border: 1px solid #eee; }
      </style>
    </head>
    <body>
      <div class="container">
        <h1>Account Deletion Instructions</h1>
        <p>To delete your FamilyHub account and all associated data, please follow these steps from within the mobile app:</p>
        <ol>
          <li>Open the <strong>FamilyHub</strong> app on your device.</li>
          <li>Go to the <strong>Settings</strong> tab.</li>
          <li>Tap on <strong>Account & Privacy</strong>.</li>
          <li>Select <strong>Delete Account</strong> and follow the on-screen prompts.</li>
        </ol>
        <p><em>Note: If you are the only member of your family workspace, the entire workspace and its data (tasks, ledger, goals, notices) will be permanently deleted.</em></p>
      </div>
    </body>
    </html>
  `);
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
