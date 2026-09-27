import { findInFamily } from '../../lib/access.js';
import { ApiError } from '../../lib/ApiError.js';
import { GOAL_STATUSES, MAX_PAGE_LIMIT, SAVINGS_CATEGORY } from '../../lib/constants.js';
import { toMinor } from '../../lib/money.js';
import { Goal, LedgerEntry } from '../../models/index.js';
import { getMemberMap, memberOf } from '../../services/memberDirectory.js';
import {
  addToGoal,
  clearAchievementForNewTarget,
  goalArchivedError,
  notifyGoalAchieved,
  reconcileGoalStatus,
  subtractFromGoal,
  unarchiveGoal,
} from './goals.balance.js';
import { ValidationIssues, familySettings, resolveEntryDate, resolveTargetDate, todayIn } from './ledger.common.js';
import { serializeEntry, serializeGoal, serializeGoals } from './ledger.serializer.js';

/**
 * Savings goals (docs/03-API_CONTRACT.md §8, `/goals`).
 *
 *   list          any member; `?status=` (default `all`), active first, then achieved, then archived,
 *                 newest first within a status. Plain array (no pagination in the contract).
 *   create        admin → 201 SavingsGoal (`active`, nothing saved).
 *   update        admin. `status: archived` archives; `active` / `achieved` restore an archived goal.
 *                 The real state always follows the saved amount (lowering the target to or below the
 *                 saved amount achieves the goal and sends `goal_achieved`; raising it reopens it).
 *                 `targetDate` must fall within 2000-01-01 … 2100-12-31 (family time zone).
 *   delete        admin; linked ledger entries stay, their `goalId` becomes null.
 *   contribute    any member → 201 `{ goal, entry }`: an `expense/savings` entry owned by the caller,
 *                 atomic `$inc` of the saved amount, `achieved` + `goal_achieved` push to the whole
 *                 family when the target is reached (not again when it is re-reached within 24 h,
 *                 goals.balance.js). Archived goals → 409 VALIDATION_ERROR.
 *
 * `actor` is `req.user` (`{ id, name, familyId, memberId, role }`).
 */

const STATUS_RANK = Object.freeze(Object.fromEntries(GOAL_STATUSES.map((s, i) => [s, i])));
const NEWEST_FIRST = Object.freeze({ createdAt: -1, _id: -1 });

/** active → achieved → archived; newest first within a status (stable for equal dates). */
function sortGoals(goals) {
  return [...goals].sort((a, b) => (STATUS_RANK[a.status] ?? 99) - (STATUS_RANK[b.status] ?? 99));
}

/** `GET /goals` → SavingsGoal[] */
export async function listGoals(actor, { status = 'all' } = {}) {
  const filter = { familyId: actor.familyId };
  if (status !== 'all') filter.status = status;
  const goals = await Goal.find(filter).sort(NEWEST_FIRST).lean();
  return serializeGoals(sortGoals(goals));
}

/**
 * Active goals of a family, newest first (dashboard `goals`, max `limit`).
 * @returns {Promise<object[]>} serialized SavingsGoal list
 */
export async function listActiveGoals(familyId, { limit = 3 } = {}) {
  // Mongo treats limit(0) / a negative limit as "no limit": clamp to 1 … MAX_PAGE_LIMIT.
  const max = Number.isInteger(limit) ? Math.min(Math.max(limit, 1), MAX_PAGE_LIMIT) : 3;
  const goals = await Goal.find({ familyId, status: 'active' }).sort(NEWEST_FIRST).limit(max).lean();
  return serializeGoals(goals);
}

/** `POST /goals` → SavingsGoal */
export async function createGoal(actor, body) {
  const { timeZone } = await familySettings(actor.familyId);
  const issues = new ValidationIssues();
  const targetDate = resolveTargetDate(body.targetDate ?? null, 'targetDate', { timeZone, issues });
  issues.throwIfAny();
  const goal = await Goal.create({
    familyId: actor.familyId,
    title: body.title,
    description: body.description ?? null,
    targetMinor: toMinor(body.targetAmount),
    savedMinor: 0,
    targetDate,
    status: 'active',
    createdById: actor.memberId,
  });
  return serializeGoal(goal);
}

/** `PATCH /goals/:id` → SavingsGoal */
export async function updateGoal(actor, id, body) {
  const goal = await findInFamily(Goal, id, actor.familyId);
  const set = {};
  if (body.title !== undefined) set.title = body.title;
  if (body.description !== undefined) set.description = body.description;
  if (body.targetAmount !== undefined) set.targetMinor = toMinor(body.targetAmount);
  if (body.targetDate !== undefined) {
    const { timeZone } = await familySettings(actor.familyId);
    const issues = new ValidationIssues();
    const targetDate = resolveTargetDate(body.targetDate, 'targetDate', { timeZone, issues });
    issues.throwIfAny();
    set.targetDate = targetDate;
  }
  if (body.status === 'archived' && goal.status !== 'archived') set.status = 'archived';

  const target = { goalId: goal._id, familyId: actor.familyId };
  if (Object.keys(set).length) {
    const res = await Goal.updateOne({ _id: goal._id, familyId: actor.familyId }, { $set: set }, { runValidators: true });
    if (!res.matchedCount) throw ApiError.notFound(); // deleted meanwhile
  }
  if (set.targetMinor !== undefined && set.targetMinor !== goal.targetMinor) {
    await clearAchievementForNewTarget({ ...target, targetMinor: set.targetMinor });
  }
  if (body.status && body.status !== 'archived' && goal.status === 'archived') await unarchiveGoal({ goal });

  const { goal: updated, notify } = await reconcileGoalStatus(target);
  if (!updated) throw ApiError.notFound();
  if (notify) notifyGoalAchieved(updated);
  return serializeGoal(updated);
}

/** `DELETE /goals/:id` → null. Linked entries are kept and detached. */
export async function deleteGoal(actor, id) {
  const goal = await findInFamily(Goal, id, actor.familyId, { lean: true, select: '_id' });
  const deleted = await Goal.findOneAndDelete({ _id: goal._id, familyId: actor.familyId });
  if (!deleted) throw ApiError.notFound();
  await LedgerEntry.updateMany({ familyId: actor.familyId, goalId: deleted._id }, { $set: { goalId: null } });
  return null;
}

/** `POST /goals/:id/contributions` → `{ goal, entry }` */
export async function contribute(actor, id, body) {
  const goal = await findInFamily(Goal, id, actor.familyId, { lean: true });
  if (goal.status === 'archived') throw goalArchivedError();

  const [{ timeZone }, members] = await Promise.all([familySettings(actor.familyId), getMemberMap(actor.familyId)]);
  const issues = new ValidationIssues();
  const date = body.date ? resolveEntryDate(body.date, 'date', { timeZone, issues }) : todayIn(timeZone);
  issues.throwIfAny();
  const me = memberOf(members, actor.memberId);
  if (!me) throw ApiError.noFamily();

  const amountMinor = toMinor(body.amount);
  const target = { goalId: goal._id, familyId: actor.familyId, amountMinor };
  await addToGoal(target); // atomic; re-checks "not archived" and the goal's existence

  let entry;
  try {
    entry = await LedgerEntry.create({
      familyId: actor.familyId,
      type: 'expense',
      amountMinor,
      category: SAVINGS_CATEGORY,
      note: body.note ?? null,
      date,
      memberId: me._id,
      memberName: me.name,
      createdById: me._id,
      goalId: goal._id,
    });
  } catch (err) {
    await subtractFromGoal(target); // compensate: the money was never recorded
    // Other contributions may have landed meanwhile: whoever wins the transition announces it.
    const { goal: reconciled, notify } = await reconcileGoalStatus({ goalId: goal._id, familyId: actor.familyId });
    if (notify) notifyGoalAchieved(reconciled);
    throw err;
  }

  const { goal: updated, notify } = await reconcileGoalStatus({ goalId: goal._id, familyId: actor.familyId });
  if (!updated) {
    // The goal was deleted while contributing: do not leave a contribution to nothing behind.
    await LedgerEntry.deleteOne({ _id: entry._id });
    throw ApiError.notFound();
  }
  if (notify) notifyGoalAchieved(updated);
  return { goal: serializeGoal(updated), entry: serializeEntry(entry, members) };
}
