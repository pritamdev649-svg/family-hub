import { Router } from 'express';
import { ApiError } from '../../lib/ApiError.js';
import { validate } from '../../lib/validate.js';
import { familyMember } from '../../middleware/auth.js';
import * as controller from './emergencyCards.controller.js';
import { CARD_BODY_ERROR, emergencyCardBody, memberCardParams } from './emergencyCards.schemas.js';

/**
 * `/api/v1/family/members/:memberId/emergency-card` (docs/03-API_CONTRACT.md §6).
 * Mounted in src/routes/index.js **before** the family router; `mergeParams` exposes `:memberId`.
 *
 *   GET  → any family member                → EmergencyCard (empty card, `updatedAt: null`, when none saved)
 *   PUT  → the member themself or an admin  → EmergencyCard (whole card replaced)
 *
 * Middleware order: 401 (no/invalid token) → 403 NO_FAMILY → 400 (malformed memberId) →
 * 422 (no JSON body / invalid body) → service: 404 (member not in the caller's family) →
 * 403 FORBIDDEN (not self/admin).
 */
const router = Router({ mergeParams: true });

/**
 * PUT replaces the whole card, and the shared `validate()` reads a missing body as `{}`. So a request
 * that carries no JSON would silently wipe every field: no body, an empty body, JSON sent as
 * `text/plain`, or a form post. Such a request is a client bug, so answer 422 and change nothing.
 * Clearing the card stays possible with an explicit `{}`.
 */
function requireJsonBody(req, _res, next) {
  const noJson = req.body === undefined || Number(req.get('content-length')) === 0;
  next(noJson ? ApiError.validation({ body: CARD_BODY_ERROR }) : undefined);
}

router.get('/', ...familyMember, validate({ params: memberCardParams }), controller.getCard);
router.put(
  '/',
  ...familyMember,
  validate({ params: memberCardParams }),
  requireJsonBody,
  validate({ body: emergencyCardBody }),
  controller.putCard,
);

export default router;
