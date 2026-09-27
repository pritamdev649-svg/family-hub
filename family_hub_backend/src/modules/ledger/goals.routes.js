import { Router } from 'express';
import { validate } from '../../lib/validate.js';
import { familyMember, requireAdmin } from '../../middleware/auth.js';
import * as controller from './goals.controller.js';
import { contributionBody, createGoalBody, goalIdParams, listGoalsQuery, updateGoalBody } from './goals.schemas.js';

/**
 * `/api/v1/goals` (docs/03-API_CONTRACT.md §8 "SavingsGoal").
 *
 *   GET    /                    any member        → SavingsGoal[] (active first)
 *   POST   /                    admin             → 201 SavingsGoal
 *   PATCH  /:id                 admin             → SavingsGoal
 *   DELETE /:id                 admin             → data: null (linked entries detached)
 *   POST   /:id/contributions   any member        → 201 { goal, entry }
 *
 * Order inside a route: 401 → 403 NO_FAMILY → 403 FORBIDDEN (admin routes) → 400 (malformed id) →
 * 422 (query / body) → service (404 → 409 archived → 422 business rules).
 */
const router = Router();

router.use(...familyMember);

router.get('/', validate({ query: listGoalsQuery }), controller.list);
router.post('/', requireAdmin, validate({ body: createGoalBody }), controller.create);
router.patch('/:id', requireAdmin, validate({ params: goalIdParams, body: updateGoalBody }), controller.update);
router.delete('/:id', requireAdmin, validate({ params: goalIdParams }), controller.remove);
router.post('/:id/contributions', validate({ params: goalIdParams, body: contributionBody }), controller.contribute);

export default router;
