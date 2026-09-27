import mongoose from 'mongoose';
import { dayRange, startOfDay, weekRange } from '../../lib/dates.js';

/**
 * Filters and sort order of task lists (docs/03-API_CONTRACT.md §7), shared by `GET /tasks` and
 * reusable by other modules (e.g. dashboard counters / "my tasks").
 *
 * Sort order:
 *   - pending → `dueDate` asc with **no due date last**, then `createdAt` asc
 *   - done    → `completedAt` desc
 *   - all     → every pending task first (pending order), then the done tasks (done order)
 *   - `_id` asc breaks the remaining ties so pages never overlap or skip items.
 * Mongo `find().sort()` puts nulls first on an ascending sort, so lists use an aggregation with
 * computed sort keys; each key is constant (null) outside its own status group.
 *
 * Due filters are evaluated in the **family time zone** (`lib/dates.js`, half-open ranges):
 *   - overdue → pending tasks due before the start of today (a task due today is not overdue yet)
 *   - today   → due within today, any status (combine with `status` to narrow)
 *   - week    → due within the current Monday-based week, any status
 */

const PENDING = 'pending';
const isPending = { $eq: ['$status', PENDING] };
const hasDueDate = { $eq: [{ $type: '$dueDate' }, 'date'] };

const SORT_KEYS = Object.freeze({
  _sortStatus: { $cond: [isPending, 0, 1] },
  _sortNoDue: { $cond: [{ $and: [isPending, { $not: [hasDueDate] }] }, 1, 0] },
  _sortDue: { $cond: [{ $and: [isPending, hasDueDate] }, '$dueDate', null] },
  _sortCreated: { $cond: [isPending, '$createdAt', null] },
  _sortCompleted: { $cond: [isPending, null, '$completedAt'] },
});

/** Aggregation stages sorting tasks in contract order (append after a `$match`). */
export const TASK_SORT_STAGES = Object.freeze([
  { $addFields: SORT_KEYS },
  { $sort: { _sortStatus: 1, _sortNoDue: 1, _sortDue: 1, _sortCreated: 1, _sortCompleted: -1, _id: 1 } },
  { $project: Object.fromEntries(Object.keys(SORT_KEYS).map((k) => [k, 0])) },
]);

const toObjectId = (id) => (id instanceof mongoose.Types.ObjectId ? id : new mongoose.Types.ObjectId(String(id)));

/**
 * Mongo filter fragment for a due filter, or `null` when the combination can never match
 * (`due=overdue` with `status=done`).
 *
 * @param {'overdue'|'today'|'week'|null|undefined} due
 * @param {string} timeZone family IANA zone (invalid → UTC, see lib/dates.js)
 * @param {Date} [now]
 * @returns {object|null}
 */
export function dueFilter(due, timeZone, now = new Date()) {
  switch (due) {
    case 'overdue':
      return { status: PENDING, dueDate: { $lt: startOfDay(now, timeZone) } };
    case 'today': {
      const { start, end } = dayRange(now, timeZone);
      return { dueDate: { $gte: start, $lt: end } };
    }
    case 'week': {
      const { start, end } = weekRange(now, timeZone);
      return { dueDate: { $gte: start, $lt: end } };
    }
    default:
      return {};
  }
}

/**
 * `$match` document for a task list. Ids are cast to ObjectId because aggregation pipelines do not
 * cast like `find()` does.
 *
 * @param {{ familyId: string, assigneeId?: string|null, status?: 'pending'|'done'|'all', due?: string|null,
 *           timeZone?: string, now?: Date }} opts
 * @returns {object|null} null when nothing can match
 */
export function taskListMatch({ familyId, assigneeId, status = 'all', due, timeZone, now = new Date() }) {
  const match = { familyId: toObjectId(familyId) };
  if (assigneeId) match.assigneeId = toObjectId(assigneeId);
  if (status && status !== 'all') match.status = status;
  const dueMatch = dueFilter(due, timeZone, now);
  if (dueMatch.status && match.status && dueMatch.status !== match.status) return null;
  return { ...match, ...dueMatch };
}

/** Full pipeline (match + contract sort) for `lib/pagination.js#paginateAggregate`. */
export function taskListPipeline(match) {
  return [{ $match: match }, ...TASK_SORT_STAGES];
}
