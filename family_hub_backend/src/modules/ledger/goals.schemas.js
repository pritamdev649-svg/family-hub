import { z } from 'zod';
import { GOAL_STATUSES, LIMITS } from '../../lib/constants.js';
import { idParams, moneyAmount, nullableField } from '../../lib/validate.js';
import { hasVisibleText, toSingleLine } from '../tasks/tasks.schemas.js';
import { amount, maxUnits, note, nullableBusinessDate, optionalMultiLineText } from './ledger.schemas.js';

/**
 * Validation for `/goals` (docs/03-API_CONTRACT.md §8 "SavingsGoal").
 *
 *   - title: single line (every run of control characters, incl. line breaks / tabs / NUL → one
 *     space; it is shown in the `goal_achieved` push), well-formed UTF-16, trimmed, 1–80 UTF-16 code
 *     units, at least one visible character (a title of only zero-width / format characters is
 *     "blank"); required on POST, optional on PATCH but never null. Same rules as task titles.
 *   - description: multi-line text like ledger notes (ledger.schemas.js), ≤ 1000 UTF-16 code units
 *     (model backstop); null / blank / only invisible characters → null.
 *   - targetAmount: same money rules as ledger amounts (> 0, ≤ 1e12, ≥ 0.01).
 *   - targetDate: optional business date (`YYYY-MM-DD` or ISO date-time); null clears it. The
 *     service checks the family-local day is within 2000-01-01 … 2100-12-31 (past dates are fine).
 *   - status (PATCH only): `active | achieved | archived`. `archived` archives the goal; `active` /
 *     `achieved` restore an archived goal — the service then derives the real state from the saved
 *     amount (an unfinished goal can never be marked achieved by hand).
 *   - Unknown keys (`savedAmount`, `progress`, `achievedAt`, …) are stripped: the saved amount only
 *     changes through contributions and the deletion of their ledger entries.
 *
 * Contributions: `{ amount, note?, date? }` — `date` absent / null → today in the family time zone.
 */

export const GOAL_LIST_STATUSES = Object.freeze([...GOAL_STATUSES, 'all']);

const isMissing = (issue) => issue.input === undefined;

const title = z
  .string({ error: (issue) => (isMissing(issue) ? 'Title is required' : 'Title must be text') })
  .overwrite(toSingleLine)
  .trim()
  .min(1, 'Title is required')
  .refine(hasVisibleText, 'Title is required')
  .refine(...maxUnits(LIMITS.GOAL_TITLE_MAX, `Title must be at most ${LIMITS.GOAL_TITLE_MAX} characters`));

const description = optionalMultiLineText('Description', LIMITS.GOAL_DESCRIPTION_MAX);

const status = z.enum(GOAL_STATUSES, { error: `Status must be one of: ${GOAL_STATUSES.join(', ')}` });

export const goalIdParams = idParams;

/** `GET /goals?status=active|achieved|archived|all` (default `all`). */
export const listGoalsQuery = z.object({
  status: nullableField(
    z.enum(GOAL_LIST_STATUSES, { error: `Status must be one of: ${GOAL_LIST_STATUSES.join(', ')}` }),
  ).transform((v) => v ?? 'all'),
});

/** `POST /goals` */
export const createGoalBody = z.object({
  title,
  description,
  targetAmount: amount,
  targetDate: nullableBusinessDate,
});

/** `PATCH /goals/:id` — only the keys present are changed. */
export const updateGoalBody = z.object({
  title: title.optional(),
  description,
  targetAmount: moneyAmount.optional(),
  targetDate: nullableBusinessDate,
  status: status.optional(),
});

/** `POST /goals/:id/contributions` */
export const contributionBody = z.object({
  amount,
  note,
  date: nullableBusinessDate,
});
