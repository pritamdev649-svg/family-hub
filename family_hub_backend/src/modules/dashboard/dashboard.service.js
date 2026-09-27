import mongoose from 'mongoose';
import { isAdmin, isObjectId, toId } from '../../lib/access.js';
import { ApiError } from '../../lib/ApiError.js';
import { DASHBOARD_LIMITS } from '../../lib/constants.js';
import { DEFAULT_TIME_ZONE, currentMonth, isValidTimeZone, startOfDay, weekRange } from '../../lib/dates.js';
import { Family, Task } from '../../models/index.js';
import { getMemberMap, memberOf } from '../../services/memberDirectory.js';
import { serializeFamily, serializeMember, sortMembers } from '../../services/serializers.js';
import { listActiveGoals } from '../ledger/goals.service.js';
import { getMonthSummary } from '../ledger/ledger.service.js';
import { listLatestNotices } from '../notices/notices.service.js';
import { activeAlertsForFamily } from '../sos/sos.service.js';
import { serializeTasks } from '../tasks/tasks.serializer.js';
import { taskListMatch, taskListPipeline } from '../tasks/tasks.query.js';

/**
 * `GET /dashboard` (docs/03-API_CONTRACT.md §11): everything the home screen needs in one request.
 *
 *   family         Family (`inviteCode` only for admins), `memberCount` from the member map
 *   me             the caller's Member
 *   members        every member in contract order (admins first, oldest → youngest) with
 *                  `pendingTasks`, `overdueTasks`, `completedThisWeek` — one aggregation for all
 *   myTasks        the caller's pending tasks, `dueDate` asc (no due date last), max 5
 *   goals          active goals, newest first, max 3
 *   latestNotices  max 3, pinned first, then newest first
 *   activeSos      active alerts of the family (lazy expiry is persisted first)
 *   monthSummary   `/ledger/summary` of the current month in the family time zone —
 *                  family scope for admins, personal scope for members
 *
 * Counters are per **assignee** and use the family time zone (`lib/dates.js`, same rules as
 * `GET /tasks?due=`):
 *   pendingTasks       status `pending`
 *   overdueTasks       pending with a due date before the start of today (a task due today is not
 *                      overdue yet; pending tasks without a due date never are)
 *   completedThisWeek  status `done`, `completedAt` within the current week
 *                      [Monday 00:00, next Monday 00:00)
 *
 * Queries: family + member map first (the time zone, currency and names are needed by the rest),
 * then the six independent reads in parallel. The family's own data only: every query is scoped by
 * the caller's `familyId`, so nothing of another family can appear.
 *
 * `actor` is `req.user` (`{ id, familyId, memberId, role }`) so the service stays HTTP-agnostic; the
 * role deciding admin-only data (invite code, family-wide money) is re-read from the member map.
 */

const PENDING = 'pending';
const DONE = 'done';

const oid = (id) => new mongoose.Types.ObjectId(toId(id));

/** A valid injected clock, else the server time (never a RangeError → 500 for internal callers). */
function clockOf(value) {
  return value instanceof Date && !Number.isNaN(value.getTime()) ? value : new Date();
}

/** Family IANA zone, UTC when the stored one is missing / unknown to this runtime. */
function zoneOf(family) {
  return isValidTimeZone(family?.timezone) ? family.timezone : DEFAULT_TIME_ZONE;
}

/**
 * Task counters of every assignee of a family in **one** aggregation.
 *
 * @param {string} familyId
 * @param {{ timeZone?: string, now?: Date }} [opts] `timeZone` invalid → UTC; `now` invalid → server time
 * @returns {Promise<Map<string, { pendingTasks: number, overdueTasks: number, completedThisWeek: number }>>}
 *   keyed by assignee member id; assignees without matching tasks are absent (→ zeros)
 */
export async function memberTaskStats(familyId, { timeZone = DEFAULT_TIME_ZONE, now: at } = {}) {
  const stats = new Map();
  if (!isObjectId(familyId)) return stats;
  const now = clockOf(at);
  const todayStart = startOfDay(now, timeZone);
  // Half-open [Monday 00:00, next Monday 00:00): a `completedAt` after this week (clock skew
  // between API instances, imported data, an injected `now`) is not "this week" either.
  const { start: weekStart, end: weekEnd } = weekRange(now, timeZone);
  const isPending = { $eq: ['$status', PENDING] };
  const rows = await Task.aggregate([
    // Pending branch: {familyId, status, dueDate} index. Done branch: only this week's completions
    // pass (tight once Task has a {familyId, status, completedAt} index — see docs/progress/b-dashboard.md).
    {
      $match: {
        familyId: oid(familyId),
        $or: [{ status: PENDING }, { status: DONE, completedAt: { $gte: weekStart, $lt: weekEnd } }],
      },
    },
    {
      $group: {
        _id: '$assigneeId',
        pendingTasks: { $sum: { $cond: [isPending, 1, 0] } },
        overdueTasks: {
          $sum: {
            // `$type` guard: in aggregation expressions null sorts before every date.
            $cond: [{ $and: [isPending, { $eq: [{ $type: '$dueDate' }, 'date'] }, { $lt: ['$dueDate', todayStart] }] }, 1, 0],
          },
        },
        // Only done tasks completed within this week passed the `$match`.
        completedThisWeek: { $sum: { $cond: [{ $eq: ['$status', DONE] }, 1, 0] } },
      },
    },
  ]).exec();
  for (const row of rows) {
    stats.set(toId(row._id), {
      pendingTasks: row.pendingTasks,
      overdueTasks: row.overdueTasks,
      completedThisWeek: row.completedThisWeek,
    });
  }
  return stats;
}

const NO_STATS = Object.freeze({ pendingTasks: 0, overdueTasks: 0, completedThisWeek: 0 });

/** The caller's pending tasks in contract order (`dueDate` asc, no due date last), max `limit`. */
async function pendingTasksOf(familyId, memberId, limit) {
  const match = taskListMatch({ familyId, assigneeId: memberId, status: PENDING });
  // `$limit` after the sort stages: MongoDB moves it before the trailing `$project` and coalesces
  // it with the `$sort` (top-k sort), so only `limit` documents are materialised.
  return Task.aggregate([...taskListPipeline(match), { $limit: limit }]).exec();
}

/**
 * `GET /dashboard` payload (contract §11).
 *
 * @param {{ familyId: string, memberId: string }} actor `req.user`
 * @param {{ now?: Date }} [opts] `now` is injectable for tests (week / day / month boundaries);
 *   anything but a valid Date means "server time"
 * @throws {ApiError} 403 NO_FAMILY when the family or the caller's member row vanished meanwhile
 */
export async function getDashboard(actor, { now: at } = {}) {
  // One clock for every section (day / week / month / SOS expiry).
  const now = clockOf(at);
  const familyId = actor?.familyId;
  if (!isObjectId(familyId) || !isObjectId(actor?.memberId)) throw ApiError.noFamily();

  const [family, members] = await Promise.all([Family.findById(familyId).lean(), getMemberMap(familyId)]);
  const meDoc = memberOf(members, actor.memberId);
  // Removed from the family (or the family deleted) between requireAuth and here.
  if (!family || !meDoc) throw ApiError.noFamily();

  // Role from the member row loaded here (not the token-time `actor.role`): a demotion racing this
  // request can then never show the invite code or family-wide money, and `me.role` always agrees.
  const admin = isAdmin({ user: { role: meDoc.role } });
  const timeZone = zoneOf(family);

  const [stats, myTasks, goals, latestNotices, activeSos, monthSummary] = await Promise.all([
    memberTaskStats(familyId, { timeZone, now }),
    pendingTasksOf(familyId, actor.memberId, DASHBOARD_LIMITS.MY_TASKS),
    listActiveGoals(familyId, { limit: DASHBOARD_LIMITS.GOALS }),
    listLatestNotices(familyId, { limit: DASHBOARD_LIMITS.NOTICES, members }),
    activeAlertsForFamily(familyId, { members, now }),
    getMonthSummary({
      familyId,
      memberId: admin ? null : actor.memberId,
      month: currentMonth(timeZone, now),
      timeZone,
      currency: family.currency,
    }),
  ]);

  return {
    family: serializeFamily(family, { isAdmin: admin, memberCount: members.size }),
    me: serializeMember(meDoc),
    members: sortMembers([...members.values()]).map((member) => ({
      member: serializeMember(member),
      ...(stats.get(toId(member._id)) ?? NO_STATS),
    })),
    myTasks: serializeTasks(myTasks, members),
    goals,
    latestNotices,
    activeSos,
    monthSummary,
  };
}
