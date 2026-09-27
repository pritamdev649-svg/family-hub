import { Router } from 'express';
import { validate } from '../../lib/validate.js';
import { familyMember } from '../../middleware/auth.js';
import * as controller from './ledger.controller.js';
import { createEntryBody, entryIdParams, listEntriesQuery, summaryQuery, updateEntryBody } from './ledger.schemas.js';

/**
 * `/api/v1/ledger` (docs/03-API_CONTRACT.md §8). Every route needs a signed-in family member; the
 * finer rules (visibility, admin / creator, goal-linked entries) live in ledger.service.js.
 *
 *   GET    /entries        list (month/type/memberId/goalId filters, `date` desc, pagination)
 *   POST   /entries        create                     → 201 LedgerEntry
 *   PATCH  /entries/:id    edit (admin or creator)    → LedgerEntry
 *   DELETE /entries/:id    delete (admin or creator)  → data: null
 *   GET    /summary        month totals (admin → family, member → personal)
 *
 * Order inside a route: 401 → 403 NO_FAMILY → 400 (malformed id) → 422 (query / body) → service
 * (404 → 403 → 422 business rules).
 */
const router = Router();

router.use(...familyMember);

router.get('/entries', validate({ query: listEntriesQuery }), controller.listEntries);
router.post('/entries', validate({ body: createEntryBody }), controller.createEntry);
router.patch('/entries/:id', validate({ params: entryIdParams, body: updateEntryBody }), controller.updateEntry);
router.delete('/entries/:id', validate({ params: entryIdParams }), controller.deleteEntry);
router.get('/summary', validate({ query: summaryQuery }), controller.summary);

export default router;
