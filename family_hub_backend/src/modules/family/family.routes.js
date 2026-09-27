import { Router } from 'express';
import { validate } from '../../lib/validate.js';
import { requireAdmin, requireAuth, requireFamily } from '../../middleware/auth.js';
import { createRateLimiter } from '../../middleware/rateLimit.js';
import * as controller from './family.controller.js';
import {
  addMemberBody,
  createFamilyBody,
  joinFamilyBody,
  memberIdParams,
  updateFamilyBody,
  updateMemberBody,
} from './family.schemas.js';

/**
 * `/api/v1/family` (docs/03-API_CONTRACT.md §6). Every route needs a valid access token.
 * The emergency card (`/family/members/:memberId/emergency-card`) is a separate router mounted
 * before this one in src/routes/index.js.
 *
 *   POST   /                 create a family (caller has none)      → 201 { user, family, member }
 *   POST   /join             join by invite code (caller has none)  → { user, family, member }
 *   GET    /                 member                                 → { family }
 *   PATCH  /                 admin                                  → { family }
 *   POST   /invite-code      admin, new code                        → { family }
 *   GET    /members          member                                 → Member[]
 *   POST   /members          admin                                  → 201 Member
 *   GET    /members/:id      member                                 → Member
 *   PATCH  /members/:id      admin (any) / self (limited fields)    → Member
 *   DELETE /members/:id      admin                                  → null
 *
 * Order inside a route: 401 → 403 (NO_FAMILY / FORBIDDEN for admin-only routes) → 400 (malformed
 * id) → 422 (body) → service (404 → 403 → 422 → 409).
 */

/**
 * Joining is the only way to probe invite codes, so it gets its own budget per account on top of
 * the global per-IP limiter (8 characters from a 32-letter alphabet cannot be guessed anyway;
 * this keeps scripted probing noisy and slow). Skipped in tests unless RATE_LIMIT_IN_TEST=true.
 */
const joinLimiter = createRateLimiter({
  windowMs: 15 * 60 * 1000,
  limit: 20,
  identifier: 'family-join',
  keyGenerator: (req) => `user:${req.user?.id ?? 'anonymous'}`,
});

const router = Router();

router.use(requireAuth);

// Callers without a family (the service answers 409 ALREADY_IN_FAMILY otherwise).
router.post('/', validate({ body: createFamilyBody }), controller.createFamily);
router.post('/join', joinLimiter, validate({ body: joinFamilyBody }), controller.joinFamily);

// The family.
router.get('/', requireFamily, controller.getFamily);
router.patch('/', requireAdmin, validate({ body: updateFamilyBody }), controller.updateFamily);
router.post('/invite-code', requireAdmin, controller.regenerateInviteCode);

// Members.
router.get('/members', requireFamily, controller.listMembers);
router.post('/members', requireAdmin, validate({ body: addMemberBody }), controller.addMember);
router.get('/members/:id', requireFamily, validate({ params: memberIdParams }), controller.getMember);
router.patch(
  '/members/:id',
  requireFamily,
  validate({ params: memberIdParams, body: updateMemberBody }),
  controller.updateMember,
);
router.delete('/members/:id', requireAdmin, validate({ params: memberIdParams }), controller.removeMember);

export default router;
