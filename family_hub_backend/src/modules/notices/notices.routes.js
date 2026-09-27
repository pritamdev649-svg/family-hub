import { Router } from 'express';
import { validate } from '../../lib/validate.js';
import { familyMember } from '../../middleware/auth.js';
import { createRateLimiter } from '../../middleware/rateLimit.js';
import * as controller from './notices.controller.js';
import { createNoticeBody, listNoticesQuery, noticeIdParams, updateNoticeBody } from './notices.schemas.js';

/**
 * `/api/v1/notices` (docs/03-API_CONTRACT.md §9). Every route needs a signed-in family member; the
 * finer rules (author / admin, pin = admin only) live in notices.service.js.
 *
 *   GET    /       list (pinned first, then newest first; `?page&limit`)
 *   POST   /       create                 → 201 Notice (+ `notice` push to the other members)
 *   PATCH  /:id    edit (author or admin) → Notice
 *   DELETE /:id    delete (author or admin) → data: null
 *
 * Order inside a route: 401 → 403 NO_FAMILY → 429 (POST only) → 400 (malformed id) → 422 (query /
 * body) → service (404 → 403).
 */

/**
 * Notices one account may post per minute. Every notice pushes to the whole family, so without a
 * per-account budget one member could flood everyone's lock screen (the global limiter allows 300
 * requests / minute / IP, and family members often share one home IP). Keyed by user id, and it runs
 * before validation so rejected bodies count as well. `429 TOO_MANY_REQUESTS` + `retryAfterSeconds`.
 */
export const NOTICE_POST_RATE_LIMIT_PER_MINUTE = 10;

const postLimiter = createRateLimiter({
  windowMs: 60_000,
  limit: NOTICE_POST_RATE_LIMIT_PER_MINUTE,
  identifier: 'notices-post',
  keyGenerator: (req) => `user:${req.user.id}`,
});

const router = Router();

router.use(...familyMember);

router.get('/', validate({ query: listNoticesQuery }), controller.list);
router.post('/', postLimiter, validate({ body: createNoticeBody }), controller.create);
router.patch('/:id', validate({ params: noticeIdParams, body: updateNoticeBody }), controller.update);
router.delete('/:id', validate({ params: noticeIdParams }), controller.remove);

export default router;
