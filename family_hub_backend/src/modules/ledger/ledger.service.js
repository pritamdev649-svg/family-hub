import mongoose from 'mongoose';
import { findInFamily, isAdmin, isObjectId, sameId, toId } from '../../lib/access.js';
import { ApiError } from '../../lib/ApiError.js';
import { LEDGER_TYPES, SAVINGS_CATEGORY, isLedgerCategoryFor } from '../../lib/constants.js';
import {
  DEFAULT_TIME_ZONE,
  currentMonth,
  isMonthString,
  isValidTimeZone,
  monthRange,
  zonedParts,
  zonedTimeToUtc,
} from '../../lib/dates.js';
import { fromMinor, toMinor } from '../../lib/money.js';
import { paginate } from '../../lib/pagination.js';
import { Family, Goal, LedgerEntry } from '../../models/index.js';
import { getMemberMap, memberOf } from '../../services/memberDirectory.js';
import { notifyGoalAchieved, reconcileGoalStatus, subtractFromGoal } from './goals.balance.js';
import {
  ValidationIssues,
  canModifyEntry,
  canSeeEntry,
  familySettings,
  resolveBusinessDate,
  resolveEntryDate,
  visibilityFilter,
} from './ledger.common.js';
import { categoryMessage } from './ledger.schemas.js';
import { serializeEntries, serializeEntry } from './ledger.serializer.js';

/**
 * Shared family ledger (docs/03-API_CONTRACT.md §8, `/ledger/*`).
 *
 *   list      any member; admins see every entry, members the entries they own (`memberId`) or
 *             created (`createdById`). Filters `month` (family time zone), `type`, `memberId`, `goalId`;
 *             sorted `date` desc (then newest first); paginated.
 *   create    any member; a member may only record for themselves (`403`), an admin for any member of
 *             the family (`422 details.memberId` otherwise — never 404, that would leak other families' ids).
 *   update    admin or creator (entries the caller cannot see → 404). The amount of a goal-linked entry
 *             is locked (`422 details.amount`; delete & contribute again), and so are its type/category
 *             (a contribution is always `expense/savings`, which keeps goals and the ledger consistent).
 *             An entry whose goal no longer exists (e.g. a goal deletion interrupted between its two
 *             steps) is unlinked on its next edit and then edited like any other entry.
 *   delete    admin or creator. A goal-linked entry takes its amount back off the goal (never below 0)
 *             and reopens an achieved goal that drops below its target.
 *   summary   admin → family scope, member → personal scope (entries whose `memberId` is theirs).
 *   rebaseBusinessDates  keeps entry / goal dates on their calendar day when the family time zone
 *             changes (for `PATCH /family`).
 *
 * Check order inside a write: 404 (not in family / not visible) → 403 (role) → 422 (business rules).
 * `actor` is `req.user` (`{ id, name, familyId, memberId, role }`), so the service stays HTTP-agnostic.
 */

const ENTRY_SORT = Object.freeze({ date: -1, createdAt: -1, _id: -1 });
const SUMMARY_SCOPES = Object.freeze({ FAMILY: 'family', PERSONAL: 'personal' });

const asCtx = (actor) => ({ user: actor });
const oid = (id) => new mongoose.Types.ObjectId(toId(id));

function memberNotInFamily(issues) {
  issues.add('memberId', 'Member must belong to your family', 'ledger.errors.memberNotInFamily');
}

function memberSelfOnly() {
  return ApiError.forbidden('Members can only record money for themselves', {
    messageKey: 'ledger.errors.memberSelfOnly',
  });
}

/** Entry of the caller's family that the caller may see (404 otherwise). */
async function findVisibleEntry(actor, id) {
  const entry = await findInFamily(LedgerEntry, id, actor.familyId);
  if (!canSeeEntry(actor, entry)) throw ApiError.notFound();
  return entry;
}

/** Visible entry the caller may change (403 unless admin or creator). */
async function findModifiableEntry(actor, id) {
  const entry = await findVisibleEntry(actor, id);
  if (!canModifyEntry(actor, entry)) throw ApiError.forbidden();
  return entry;
}

// ---------------------------------------------------------------- entries

/** `GET /ledger/entries` → `{ items, page, limit, total }` (serialized). */
export async function listEntries(actor, { month, type, memberId, goalId, page, limit }) {
  const filter = { familyId: actor.familyId, ...visibilityFilter(actor) };
  if (type) filter.type = type;
  if (memberId) filter.memberId = memberId;
  if (goalId) filter.goalId = goalId;
  if (month) {
    const { timeZone } = await familySettings(actor.familyId);
    const { start, end } = monthRange(month, timeZone);
    filter.date = { $gte: start, $lt: end };
  }
  const [result, members] = await Promise.all([
    paginate(LedgerEntry, filter, { page, limit, sort: ENTRY_SORT, lean: true }),
    getMemberMap(actor.familyId),
  ]);
  return { ...result, items: serializeEntries(result.items, members) };
}

/** `POST /ledger/entries` → LedgerEntry. */
export async function createEntry(actor, body) {
  const [members, settings] = await Promise.all([getMemberMap(actor.familyId), familySettings(actor.familyId)]);
  const issues = new ValidationIssues();

  let ownerId = actor.memberId;
  if (body.memberId && !sameId(body.memberId, actor.memberId)) {
    if (!isAdmin(asCtx(actor))) throw memberSelfOnly();
    if (memberOf(members, body.memberId)) ownerId = body.memberId;
    else memberNotInFamily(issues);
  }
  const date = resolveEntryDate(body.date, 'date', { timeZone: settings.timeZone, issues });
  issues.throwIfAny();

  const owner = memberOf(members, ownerId);
  if (!owner) throw ApiError.noFamily(); // the caller's own member row vanished mid-request
  const entry = await LedgerEntry.create({
    familyId: actor.familyId,
    type: body.type,
    amountMinor: toMinor(body.amount),
    category: body.category,
    note: body.note ?? null,
    date,
    memberId: owner._id,
    memberName: owner.name,
    createdById: actor.memberId,
    goalId: null,
  });
  return serializeEntry(entry, members);
}

/** `PATCH /ledger/entries/:id` → LedgerEntry. Only the keys present in `body` are considered. */
export async function updateEntry(actor, id, body) {
  const entry = await findModifiableEntry(actor, id);
  const members = await getMemberMap(actor.familyId);
  const issues = new ValidationIssues();
  const set = {};

  // Owner: a member may only (re)assign an entry to themselves.
  if (body.memberId !== undefined && !sameId(body.memberId, entry.memberId)) {
    if (!isAdmin(asCtx(actor)) && !sameId(body.memberId, actor.memberId)) throw memberSelfOnly();
    const owner = memberOf(members, body.memberId);
    if (owner) {
      set.memberId = owner._id;
      set.memberName = owner.name;
    } else {
      memberNotInFamily(issues);
    }
  }

  const nextType = body.type ?? entry.type;
  const nextCategory = body.category ?? entry.category;
  let goalLinked = Boolean(entry.goalId);
  if (goalLinked && !(await Goal.exists({ _id: entry.goalId, familyId: actor.familyId }))) {
    set.goalId = null; // dangling link: deleting a goal detaches its entries anyway
    goalLinked = false;
  }
  if (goalLinked) {
    if (body.amount !== undefined && toMinor(body.amount) !== entry.amountMinor) {
      issues.add(
        'amount',
        'The amount of a goal contribution cannot be changed. Delete it and contribute again.',
        'ledger.errors.goalAmountLocked',
      );
    }
    if (nextType !== entry.type) {
      issues.add('type', 'A goal contribution is always an expense', 'ledger.errors.goalEntryLocked');
    }
    if (nextCategory !== entry.category) {
      issues.add('category', `A goal contribution always uses the "${SAVINGS_CATEGORY}" category`, 'ledger.errors.goalEntryLocked');
    }
  } else if (body.amount !== undefined) {
    set.amountMinor = toMinor(body.amount);
  }
  if (!issues.has('type') && !issues.has('category') && !isLedgerCategoryFor(nextType, nextCategory)) {
    issues.add('category', categoryMessage(nextType, nextCategory), 'ledger.errors.categoryForType');
  }
  if (nextType !== entry.type || nextCategory !== entry.category) {
    // Both keys together so the model's update validator checks the pair (models/LedgerEntry.js).
    set.type = nextType;
    set.category = nextCategory;
  }

  if (body.note !== undefined) set.note = body.note;
  if (body.date !== undefined) {
    const { timeZone } = await familySettings(actor.familyId);
    const date = resolveEntryDate(body.date, 'date', { timeZone, issues });
    if (date) set.date = date;
  }
  issues.throwIfAny();

  if (!Object.keys(set).length) return serializeEntry(entry, members);
  const updated = await LedgerEntry.findOneAndUpdate(
    { _id: entry._id, familyId: actor.familyId },
    { $set: set },
    { returnDocument: 'after', runValidators: true },
  );
  if (!updated) throw ApiError.notFound(); // deleted meanwhile
  return serializeEntry(updated, members);
}

/**
 * `DELETE /ledger/entries/:id` → null. Only the request that actually deleted the entry adjusts its
 * goal, so a double delete can never subtract twice.
 */
export async function deleteEntry(actor, id) {
  const entry = await findModifiableEntry(actor, id);
  const deleted = await LedgerEntry.findOneAndDelete({ _id: entry._id, familyId: actor.familyId });
  if (!deleted) throw ApiError.notFound();
  if (deleted.goalId) {
    const goal = await subtractFromGoal({
      goalId: deleted.goalId,
      familyId: actor.familyId,
      amountMinor: deleted.amountMinor,
    });
    if (goal) {
      // Whoever wins the `active → achieved` transition announces it: here that is possible when a
      // concurrent contribution's `$inc` landed before this reconcile ran.
      const { goal: reconciled, notify } = await reconcileGoalStatus({ goalId: goal._id, familyId: actor.familyId });
      if (notify) notifyGoalAchieved(reconciled);
    }
  }
  return null;
}

// ---------------------------------------------------------------- summary

/**
 * Income / expense totals of one month (contract `/ledger/summary` shape). Also used by the dashboard.
 *
 * @param {object} p
 * @param {string} p.familyId
 * @param {string|null} [p.memberId]  null → family scope; a member id → that member's personal scope
 * @param {string} [p.month]          `YYYY-MM`; default: current month in `timeZone`
 * @param {string} [p.timeZone]       family IANA zone (loaded from the family when omitted)
 * @param {string} [p.currency]       family currency (loaded from the family when omitted)
 * @returns {Promise<{ month: string, currency: string, scope: 'family'|'personal', income: number,
 *   expense: number, net: number, byCategory: { type: string, category: string, amount: number }[] }>}
 *   `byCategory` is sorted by amount desc, then type (income first) and category.
 */
export async function getMonthSummary({ familyId, memberId = null, month, timeZone, currency } = {}) {
  if (!isObjectId(familyId)) throw ApiError.noFamily();
  if (memberId && !isObjectId(memberId)) throw ApiError.notFound();
  // Callers other than the validated route (dashboard) get a 422, not a RangeError → 500.
  if (month && !isMonthString(month)) throw ApiError.validation({ month: 'Expected YYYY-MM' });
  let zone = timeZone;
  let money = currency;
  if (!isValidTimeZone(zone) || !money) {
    const family = await Family.findById(familyId).select('timezone currency').lean();
    if (!isValidTimeZone(zone)) zone = isValidTimeZone(family?.timezone) ? family.timezone : DEFAULT_TIME_ZONE;
    money ||= family?.currency ?? null;
  }
  const key = month || currentMonth(zone);
  const { start, end } = monthRange(key, zone);

  const match = { familyId: oid(familyId), date: { $gte: start, $lt: end } };
  if (memberId) match.memberId = oid(memberId);
  const rows = await LedgerEntry.aggregate([
    { $match: match },
    { $group: { _id: { type: '$type', category: '$category' }, amountMinor: { $sum: '$amountMinor' } } },
  ]).exec();

  const totals = { income: 0, expense: 0 };
  for (const row of rows) {
    if (row._id.type in totals) totals[row._id.type] += row.amountMinor;
  }
  const typeRank = (type) => LEDGER_TYPES.indexOf(type);
  const byCategory = rows
    .filter((row) => row.amountMinor !== 0)
    .sort(
      (a, b) =>
        b.amountMinor - a.amountMinor ||
        typeRank(a._id.type) - typeRank(b._id.type) ||
        String(a._id.category).localeCompare(String(b._id.category)),
    )
    .map((row) => ({ type: row._id.type, category: row._id.category, amount: fromMinor(row.amountMinor) }));

  return {
    month: key,
    currency: money,
    scope: memberId ? SUMMARY_SCOPES.PERSONAL : SUMMARY_SCOPES.FAMILY,
    income: fromMinor(totals.income),
    expense: fromMinor(totals.expense),
    net: fromMinor(totals.income - totals.expense),
    byCategory,
  };
}

/** `GET /ledger/summary` — admin → family scope, member → personal scope. */
export async function getSummary(actor, { month } = {}) {
  const { timeZone, currency } = await familySettings(actor.familyId);
  return getMonthSummary({
    familyId: actor.familyId,
    memberId: isAdmin(asCtx(actor)) ? null : actor.memberId,
    month: month ?? undefined,
    timeZone,
    currency,
  });
}

// ---------------------------------------------------------------- family time-zone change

const REBASE_BATCH = 500;

/** Moves `field` of every document matching `filter` with `move(date)`; returns how many changed. */
async function rebaseField(Model, filter, field, move) {
  let ops = [];
  let changed = 0;
  const flush = async () => {
    if (!ops.length) return;
    const res = await Model.bulkWrite(ops, { ordered: false });
    changed += res.modifiedCount ?? 0;
    ops = [];
  };
  for await (const doc of Model.find(filter).select(field).lean().cursor()) {
    const current = doc[field];
    const next = move(current);
    if (next.getTime() !== new Date(current).getTime()) {
      // Conditional on the old value: an entry re-dated meanwhile (already in the new zone) is left alone.
      ops.push({ updateOne: { filter: { _id: doc._id, [field]: current }, update: { $set: { [field]: next } } } });
    }
    if (ops.length >= REBASE_BATCH) await flush();
  }
  await flush();
  return changed;
}

/**
 * Keeps business dates on the same calendar day when a family's time zone changes. Ledger `date` and
 * goal `targetDate` are stored as family-local midnight, so after e.g. `Asia/Kolkata` → `America/New_York`
 * every 1 April entry (2025-03-31T18:30Z) would count for March and show as 31 March. Each date is read
 * as a day in `fromTimeZone` (nearest midnight) and moved to midnight of that day in `toTimeZone`.
 *
 * Call it once from the family service right after the new `timezone` is saved, with the previous zone
 * as `fromTimeZone`. Invalid zones fall back to UTC (like everywhere else); same zones → no-op.
 *
 * @param {{ familyId: string, fromTimeZone: string, toTimeZone: string }} p
 * @returns {Promise<{ entries: number, goals: number }>} documents changed
 */
export async function rebaseBusinessDates({ familyId, fromTimeZone, toTimeZone } = {}) {
  if (!isObjectId(familyId)) throw ApiError.noFamily();
  const from = isValidTimeZone(fromTimeZone) ? fromTimeZone : DEFAULT_TIME_ZONE;
  const to = isValidTimeZone(toTimeZone) ? toTimeZone : DEFAULT_TIME_ZONE;
  if (from === to) return { entries: 0, goals: 0 };
  const move = (date) => {
    const day = zonedParts(resolveBusinessDate(new Date(date), from), from);
    return zonedTimeToUtc({ year: day.year, month: day.month, day: day.day }, to);
  };
  const family = oid(familyId);
  const entries = await rebaseField(LedgerEntry, { familyId: family }, 'date', move);
  const goals = await rebaseField(Goal, { familyId: family, targetDate: { $ne: null } }, 'targetDate', move);
  return { entries, goals };
}
