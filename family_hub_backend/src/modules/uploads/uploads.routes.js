import { Router } from 'express';
import { validate } from '../../lib/validate.js';
import { requireAuth, requireFamily } from '../../middleware/auth.js';
import { createRateLimiter } from '../../middleware/rateLimit.js';
import * as controller from './uploads.controller.js';
import { signatureBody } from './uploads.schemas.js';

/**
 * `/api/v1/uploads` (docs/03-API_CONTRACT.md §12).
 *
 *   POST /signature  { folder: "avatars"|"notices" }  → 200 { cloudName, apiKey, timestamp, signature, folder }
 *                    any family member (admin or member); folder = familyhub/<caller's familyId>/<folder>
 *
 * Middleware order: 401 (no/invalid/expired token) → 429 (30 signatures / minute / **user**) →
 * 403 NO_FAMILY → 422 (body) → service: 503 UPLOADS_NOT_CONFIGURED when Cloudinary credentials are
 * missing or malformed (blank / whitespace-padded values, a cloud name that is not a plain token).
 * The limiter runs right after authentication so every authenticated attempt counts, including
 * invalid bodies (it is keyed by user id, not IP: family members often share one home IP).
 */

/** Signatures per user per minute (task spec: 30/min). */
export const SIGNATURE_RATE_LIMIT_PER_MINUTE = 30;

const signatureLimiter = createRateLimiter({
  limit: SIGNATURE_RATE_LIMIT_PER_MINUTE,
  identifier: 'uploads',
  keyGenerator: (req) => `user:${req.user.id}`,
});

const router = Router();

router.post('/signature', requireAuth, signatureLimiter, requireFamily, validate({ body: signatureBody }), controller.signature);

export default router;
