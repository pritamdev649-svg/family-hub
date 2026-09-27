import { fromMinor } from '../../lib/money.js';
import { Goal } from '../../models/index.js';
import { nameOf } from '../../services/memberDirectory.js';
import { idOf, iso } from '../../services/serializers.js';

/**
 * Contract shapes of docs/03-API_CONTRACT.md §8 (`LedgerEntry`, `SavingsGoal`). Accept Mongoose
 * documents or lean / aggregated objects. Money leaves the API in decimal major units
 * (`lib/money.js#fromMinor`); `amountMinor` / `targetMinor` / `savedMinor` are never exposed.
 *
 * Exported for other modules (dashboard `goals`, `/me/export`) so both objects leave the API identically.
 */

/**
 * @param {object} entry
 * @param {Map<string, object>} [members] memberId → member (services/memberDirectory.js#getMemberMap).
 *   `memberName` is the member's current name when they still exist, else the stored snapshot
 *   (entries outlive removed members).
 */
export function serializeEntry(entry, members) {
  if (!entry) return null;
  return {
    id: idOf(entry),
    type: entry.type,
    amount: fromMinor(entry.amountMinor),
    category: entry.category,
    note: entry.note ?? null,
    date: iso(entry.date),
    memberId: idOf(entry.memberId),
    memberName: nameOf(members, entry.memberId) ?? entry.memberName ?? null,
    createdById: idOf(entry.createdById),
    goalId: idOf(entry.goalId),
    createdAt: iso(entry.createdAt),
  };
}

/** Serializes a list with one shared member map. */
export function serializeEntries(list, members) {
  return (list ?? []).map((entry) => serializeEntry(entry, members));
}

/** `progress` from the model virtual (hydrating lean objects so the formula lives in one place). */
function progressOf(goal) {
  if (typeof goal.progress === 'number') return goal.progress;
  return Goal.hydrate({ targetMinor: goal.targetMinor, savedMinor: goal.savedMinor }).progress;
}

export function serializeGoal(goal) {
  if (!goal) return null;
  return {
    id: idOf(goal),
    title: goal.title,
    description: goal.description ?? null,
    targetAmount: fromMinor(goal.targetMinor),
    savedAmount: fromMinor(goal.savedMinor),
    targetDate: iso(goal.targetDate),
    status: goal.status,
    progress: progressOf(goal),
    createdById: idOf(goal.createdById),
    createdAt: iso(goal.createdAt),
    updatedAt: iso(goal.updatedAt),
  };
}

export function serializeGoals(list) {
  return (list ?? []).map(serializeGoal);
}
