import { Router } from 'express';
import { validate } from '../../lib/validate.js';
import { familyMember } from '../../middleware/auth.js';
import * as controller from './tasks.controller.js';
import { createTaskBody, listTasksQuery, taskIdParams, updateTaskBody } from './tasks.schemas.js';

/**
 * `/api/v1/tasks` (docs/03-API_CONTRACT.md §7). Every route needs a signed-in family member; the
 * finer rules (admin / creator / assignee) live in tasks.service.js.
 *
 *   GET    /                 list (filters, contract sort, pagination)
 *   POST   /                 create                → 201 Task
 *   GET    /:id              one task
 *   PATCH  /:id              edit (admin or creator)
 *   POST   /:id/complete     done   (assignee or admin, idempotent)
 *   POST   /:id/reopen       pending (assignee or admin, idempotent)
 *   DELETE /:id              delete (admin or creator) → data: null
 *
 * Order inside a route: 401 → 403 NO_FAMILY → 400 (malformed id) → 422 (query / body) → service
 * (404 → 403 → 422 assignee).
 */
const router = Router();

router.use(...familyMember);

const withId = validate({ params: taskIdParams });

router.get('/', validate({ query: listTasksQuery }), controller.list);
router.post('/', validate({ body: createTaskBody }), controller.create);
router.get('/:id', withId, controller.get);
router.patch('/:id', validate({ params: taskIdParams, body: updateTaskBody }), controller.update);
router.post('/:id/complete', withId, controller.complete);
router.post('/:id/reopen', withId, controller.reopen);
router.delete('/:id', withId, controller.remove);

export default router;
