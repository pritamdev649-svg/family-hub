import { z } from 'zod';
import { LIMITS, TASK_CATEGORIES, TASK_PRIORITIES, TASK_STATUSES } from '../../lib/constants.js';
import { isIsoDateString, nullableField, objectId, pagination } from '../../lib/validate.js';

/**
 * Validation for `/tasks` (docs/03-API_CONTRACT.md §7).
 *
 * Body rules (the app sends explicit `null` to clear a field, see lib/validate.js#nullableField):
 *   - title: single line (control characters incl. line breaks / tabs → one space), trimmed,
 *     1–120 UTF-16 code units, at least one visible character (letter, digit, symbol / emoji or
 *     punctuation: a title of only zero-width / format characters is "blank"); required on POST,
 *     optional on PATCH but never null.
 *   - description: multi-line (CRLF → LF; control characters other than `\n` / `\t` removed),
 *     trimmed, ≤ 1000 UTF-16 code units; null / blank → null (PATCH: clears it).
 *   - Text is made well-formed UTF-16 first (a lone surrogate → U+FFFD, exactly what MongoDB would
 *     store), so the response always equals what was saved. RTL text and bidi marks are kept as typed.
 *   - Lengths are counted in UTF-16 code units like the Task model (`maxlength`) and the app's
 *     validator (Dart `String.length`). zod 4's `.max()` counts code points, so an emoji-heavy title
 *     would pass zod and then fail in Mongoose with a raw message echoing the input.
 *   - assigneeId: member id (24 hex); required on POST, never null. Family membership and the
 *     "member → only self" rule are checked by the service (422 `details.assigneeId` / 403).
 *   - dueDate: ISO date-time with offset (what the app sends: local midnight → UTC) → `Date`, or a
 *     date-only `YYYY-MM-DD` → kept as that string; the service turns it into midnight in the **family
 *     time zone** (UTC midnight would be the previous local day west of UTC). null / blank → no due
 *     date. Must fall in 2000-01-01 … 2100-12-31 (local calendar days, see DUE_DATE_MIN) so typos
 *     such as year 0202 cannot create unreachable tasks.
 *   - category / priority: contract enums. POST defaults them to `other` / `medium` (model
 *     defaults, same as the app's mock backend); on PATCH they are optional but never null.
 *   - Unknown keys (e.g. `status`, `completedAt`, `familyId`) are stripped: state changes only go
 *     through `/complete` and `/reopen`.
 *
 * Query rules (`GET /tasks`): blank values count as "not given"; `status` defaults to `all`.
 */

export const TASK_LIST_STATUSES = Object.freeze([...TASK_STATUSES, 'all']);
export const TASK_DUE_FILTERS = Object.freeze(['overdue', 'today', 'week']);

/**
 * Accepted due-date window (inclusive start, exclusive end) for full ISO instants. The app sends
 * *local* midnight converted to UTC, so the first day (2000-01-01) starts up to 14 h before UTC
 * midnight (UTC+14); the last day (2100-12-31) always starts before 2101-01-01T00:00Z (UTC−12 at the
 * latest: 2100-12-31T12:00Z).
 */
export const DUE_DATE_MIN = new Date('1999-12-31T10:00:00.000Z');
export const DUE_DATE_MAX = new Date('2101-01-01T00:00:00.000Z');

const isMissing = (issue) => issue.input === undefined || issue.input === null;
const DATE_ONLY = /^\d{4}-\d{2}-\d{2}$/;

/** true for a date-only `YYYY-MM-DD` due date (resolved in the family time zone by the service). */
export const isDateOnly = (value) => typeof value === 'string' && DATE_ONLY.test(value);

// ---------------------------------------------------------------- text normalisation

const CONTROL_RUN = /\p{Cc}+/gu; // C0 (incl. \t \n \r), DEL, C1
const CONTROL_EXCEPT_TAB_LF = /[^\P{Cc}\t\n]/gu;
const VISIBLE = /[\p{L}\p{N}\p{S}\p{P}]/u;

/** Single-line text (titles): well-formed UTF-16, every run of control characters → one space. */
export const toSingleLine = (value) => value.toWellFormed().replace(CONTROL_RUN, ' ');

/** Multi-line text (descriptions): well-formed UTF-16, CRLF / CR → LF, other controls except LF / TAB removed. */
export const toMultiLine = (value) => value.toWellFormed().replace(/\r\n?/g, '\n').replace(CONTROL_EXCEPT_TAB_LF, '');

/** true when the text has something a person can see (not only spaces / zero-width / format characters). */
export const hasVisibleText = (value) => VISIBLE.test(value);

/** Length in UTF-16 code units — the unit of the Task model's `maxlength` and of the app's validator. */
const maxUnits = (max, message) => [(value) => value.length <= max, message];

const title = z
  .string({ error: (issue) => (isMissing(issue) ? 'Title is required' : 'Title must be text') })
  .overwrite(toSingleLine)
  .trim()
  .min(1, 'Title is required')
  .refine(hasVisibleText, 'Title is required')
  .refine(...maxUnits(LIMITS.TASK_TITLE_MAX, `Title must be at most ${LIMITS.TASK_TITLE_MAX} characters`));

const description = nullableField(
  z
    .string({ error: 'Description must be text' })
    .overwrite(toMultiLine)
    .trim()
    .refine(
      ...maxUnits(LIMITS.TASK_DESCRIPTION_MAX, `Description must be at most ${LIMITS.TASK_DESCRIPTION_MAX} characters`),
    )
    .transform((value) => value || null),
);

const assigneeId = z
  .string({ error: (issue) => (isMissing(issue) ? 'Assignee is required' : 'Invalid assignee') })
  .pipe(objectId);

const dueDate = nullableField(
  z
    .string({ error: 'Invalid date' })
    .trim()
    .refine(isIsoDateString, { error: 'Invalid date', abort: true })
    .refine((v) => {
      const time = new Date(v).getTime();
      return time >= DUE_DATE_MIN.getTime() && time < DUE_DATE_MAX.getTime();
    }, 'Due date must be between 2000 and 2100')
    .transform((v) => (isDateOnly(v) ? v : new Date(v))),
);

const category = z.enum(TASK_CATEGORIES, {
  error: `Category must be one of: ${TASK_CATEGORIES.join(', ')}`,
});

const priority = z.enum(TASK_PRIORITIES, {
  error: `Priority must be one of: ${TASK_PRIORITIES.join(', ')}`,
});

export const taskIdParams = z.object({ id: objectId });

/** `POST /tasks` */
export const createTaskBody = z.object({
  title,
  description,
  assigneeId,
  dueDate,
  category: category.default('other'),
  priority: priority.default('medium'),
});

/** `PATCH /tasks/:id` — every field optional; only the keys present are changed. */
export const updateTaskBody = z.object({
  title: title.optional(),
  description,
  assigneeId: assigneeId.optional(),
  dueDate,
  category: category.optional(),
  priority: priority.optional(),
});

/** `GET /tasks?assigneeId=&status=pending|done|all&due=overdue|today|week&page&limit` */
export const listTasksQuery = z.object({
  assigneeId: nullableField(objectId),
  status: nullableField(
    z.enum(TASK_LIST_STATUSES, { error: `Status must be one of: ${TASK_LIST_STATUSES.join(', ')}` }),
  ).transform((v) => v ?? 'all'),
  due: nullableField(z.enum(TASK_DUE_FILTERS, { error: `Due must be one of: ${TASK_DUE_FILTERS.join(', ')}` })),
  ...pagination,
});
