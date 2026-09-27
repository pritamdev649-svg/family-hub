import { ApiError } from '../../lib/ApiError.js';
import { PUSH_ROUTES, PUSH_TYPE } from '../../lib/constants.js';
import { Goal } from '../../models/index.js';
import { sendToMembers } from '../../services/push.js';

/**
 * Race-safe changes to a goal's saved amount and status (docs/03-API_CONTRACT.md §8).
 *
 *   - `savedMinor` only changes through atomic updates: `$inc` for contributions, a clamped
 *     `max(0, saved − amount)` update pipeline when a contribution entry is deleted.
 *   - The status follows the saved amount: `active` → `achieved` when saved ≥ target, `achieved` →
 *     `active` when it drops below (e.g. a contribution was deleted or the target raised).
 *     `archived` goals keep their status. Each transition is a conditional update, so concurrent
 *     requests converge and exactly one of them "wins" the `achieved` transition — only that
 *     request may send the `goal_achieved` push, and every caller of reconcileGoalStatus (contribution,
 *     goal edit, entry deletion, compensation) sends it when `notify` is true, so an achievement is
 *     never lost to a concurrent request that happened to win the transition.
 *   - `achievedAt` = when the goal last reached its **current** target (internal, not in the API).
 *     It is kept when the goal reopens because money was taken back off it, and cleared when an
 *     admin changes the target (a new target is a new achievement, see clearAchievementForNewTarget).
 *   - Push throttle: reaching the same target again within GOAL_ACHIEVED_NOTIFY_COOLDOWN_MS of the
 *     last time does not notify the family again. Without it any member could send a push to the
 *     whole family per contribute → delete-contribution cycle.
 */

/** A goal re-reaching its target within this window of the last time sends no second `goal_achieved`. */
export const GOAL_ACHIEVED_NOTIFY_COOLDOWN_MS = 24 * 60 * 60 * 1000;

/** Largest saved amount a goal can hold (sums must stay exact integers). */
export const MAX_SAVED_MINOR = Number.MAX_SAFE_INTEGER;

/** 409 VALIDATION_ERROR (contract: "409 CONFLICT-style VALIDATION_ERROR") for archived goals. */
export function goalArchivedError() {
  return new ApiError(409, 'VALIDATION_ERROR', 'This goal is archived', {
    details: { goalId: 'This goal is archived' },
    messageKey: 'ledger.errors.goalArchived',
  });
}

/**
 * Adds a contribution to a non-archived goal.
 * @returns {Promise<import('mongoose').Document>} the goal after the increment
 * @throws 404 (missing / other family), 409 (archived), 422 (the saved amount would overflow)
 */
export async function addToGoal({ goalId, familyId, amountMinor }) {
  const goal = await Goal.findOneAndUpdate(
    { _id: goalId, familyId, status: { $ne: 'archived' }, savedMinor: { $lte: MAX_SAVED_MINOR - amountMinor } },
    { $inc: { savedMinor: amountMinor } },
    { returnDocument: 'after' },
  );
  if (goal) return goal;
  const current = await Goal.findOne({ _id: goalId, familyId }).select('status').lean();
  if (!current) throw ApiError.notFound();
  if (current.status === 'archived') throw goalArchivedError();
  throw ApiError.validation({ amount: 'This goal cannot hold a larger amount' }, 'Validation failed', {
    messageKey: 'ledger.errors.goalFull',
  });
}

/**
 * Removes a contribution (never below 0). A missing goal (deleted meanwhile) is ignored.
 * @returns {Promise<import('mongoose').Document|null>}
 */
export function subtractFromGoal({ goalId, familyId, amountMinor }) {
  if (!goalId) return Promise.resolve(null);
  return Goal.findOneAndUpdate(
    { _id: goalId, familyId },
    [{ $set: { savedMinor: { $max: [0, { $subtract: ['$savedMinor', amountMinor] }] }, updatedAt: '$$NOW' } }],
    { returnDocument: 'after', updatePipeline: true },
  );
}

/**
 * Brings `status` in line with the saved amount (archived goals untouched).
 * @returns {Promise<{ goal: import('mongoose').Document|null, achievedNow: boolean, notify: boolean }>}
 *   `goal` is null when the goal no longer exists; `achievedNow` is true only for the request that
 *   moved it from `active` to `achieved`; `notify` additionally requires the push cooldown to have
 *   passed (see the file header) — send `goal_achieved` only when it is true.
 */
export async function reconcileGoalStatus({ goalId, familyId, now = new Date() }) {
  // `returnDocument: 'before'` tells the single winning request when the target was last reached.
  const before = await Goal.findOneAndUpdate(
    { _id: goalId, familyId, status: 'active', $expr: { $gte: ['$savedMinor', '$targetMinor'] } },
    { $set: { status: 'achieved', achievedAt: now } },
    { returnDocument: 'before', projection: { achievedAt: 1 } },
  ).lean();
  const achievedNow = Boolean(before);
  if (!achievedNow) {
    // Reopen; `achievedAt` stays (last time the target was reached → push cooldown).
    await Goal.updateOne(
      { _id: goalId, familyId, status: 'achieved', $expr: { $lt: ['$savedMinor', '$targetMinor'] } },
      { $set: { status: 'active' } },
    );
  }
  const goal = await Goal.findOne({ _id: goalId, familyId });
  const lastReached = before?.achievedAt ? new Date(before.achievedAt).getTime() : null;
  const cooledDown = lastReached === null || now.getTime() - lastReached >= GOAL_ACHIEVED_NOTIFY_COOLDOWN_MS;
  return { goal, achievedNow: achievedNow && Boolean(goal), notify: achievedNow && cooledDown && Boolean(goal) };
}

/**
 * After an admin changed the target: unless the goal is (still) achieved at the new target, forget
 * when the old target was reached, so reaching the new one notifies the family again.
 */
export function clearAchievementForNewTarget({ goalId, familyId, targetMinor }) {
  return Goal.updateOne(
    { _id: goalId, familyId, achievedAt: { $ne: null }, $nor: [{ status: 'achieved', savedMinor: { $gte: targetMinor } }] },
    { $set: { achievedAt: null } },
  );
}

/**
 * Restores an archived goal into the status its saved amount implies (`achieved` keeps its original
 * `achievedAt`; restoring is not a new achievement, so it never triggers the push).
 */
export async function unarchiveGoal({ goal, now = new Date() }) {
  const restoredAchieved = await Goal.updateOne(
    { _id: goal._id, familyId: goal.familyId, status: 'archived', $expr: { $gte: ['$savedMinor', '$targetMinor'] } },
    { $set: { status: 'achieved', achievedAt: goal.achievedAt ?? now } },
  );
  if (restoredAchieved.modifiedCount === 1) return;
  await Goal.updateOne({ _id: goal._id, familyId: goal.familyId, status: 'archived' }, { $set: { status: 'active' } });
}

/** Fire-and-forget `goal_achieved` push to the whole family (contract §8, §13: route `/money`). */
export function notifyGoalAchieved(goal) {
  void sendToMembers({
    familyId: goal.familyId,
    type: PUSH_TYPE.GOAL_ACHIEVED,
    id: goal._id ?? goal.id,
    route: PUSH_ROUTES.money(),
    titleKey: 'ledger.push.goalAchieved.title',
    bodyKey: 'ledger.push.goalAchieved.body',
    vars: { title: goal.title },
  });
}
