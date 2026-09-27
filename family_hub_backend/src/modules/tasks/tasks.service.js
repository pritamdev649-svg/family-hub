import { findInFamily, isAdmin, sameId, toId } from '../../lib/access.js';
import { ApiError } from '../../lib/ApiError.js';
import { PUSH_ROUTES, PUSH_TYPE } from '../../lib/constants.js';
import { zonedTimeToUtc } from '../../lib/dates.js';
import { paginateAggregate, paginateArray } from '../../lib/pagination.js';
import { Family, Member, Task } from '../../models/index.js';
import { getMemberMap, memberOf, nameOf } from '../../services/memberDirectory.js';
import { sendToMembers } from '../../services/push.js';
import { taskListMatch, taskListPipeline } from './tasks.query.js';
import { isDateOnly } from './tasks.schemas.js';
import { serializeTask, serializeTasks } from './tasks.serializer.js';

/**
 * Family task board (docs/03-API_CONTRACT.md §7; roles: docs/02-ARCHITECTURE.md §11.2).
 *
 *   list / get        any member of the family (other family / unknown id → 404)
 *   create            admin → any member of the family; member → only themselves
 *   update / delete   admin or the task's creator (a member-creator may only re-assign to themselves)
 *   complete / reopen admin or the assignee; idempotent (repeating the call returns the task unchanged)
 *
 * Check order inside a write: 404 (not in the caller's family) → 403 (role) → 422 (assignee) →
 * 403 (member assigning someone else). The assignee must be a member of the caller's family, else
 * `422 VALIDATION_ERROR` with `details.assigneeId` (never 404: that would leak other families' ids).
 *
 * Races (hardening, see docs/progress/b-tasks.md):
 *   - complete / reopen: the permission is checked on a snapshot, so the conditional update also
 *     requires the snapshot's assignee. A task re-assigned in between is re-read and re-checked
 *     (the old assignee now gets 403) instead of being completed by someone it no longer belongs to.
 *   - A write that leaves a task *pending* for an assignee (create, re-assign, reopen) re-checks
 *     afterwards that the assignee is still in the family, and undoes itself with 422 if not
 *     (member removal deletes the member's pending tasks; a write racing with it would otherwise
 *     leave a pending task for a non-member).
 *
 * Pushes (fire-and-forget, contract §13, route `/tasks/<id>`):
 *   - `task_assigned` → the assignee when they are not the actor: on create, and on a PATCH that
 *     moves a *pending* task to someone else (the new assignee must learn about it just the same;
 *     re-assigning a done task, e.g. to fix who did it, asks nothing of anyone → no push).
 *   - `task_completed` → the creator when they are not the completer, only on the pending → done
 *     transition (an idempotent repeat sends nothing).
 *   Managed profiles (no account) and removed members get no push. Texts carry the actor's name and a
 *   short task title only; for `health` tasks the title is left out (lock screens are visible to
 *   others, docs/08-COMPLIANCE.md §3 row 20).
 *
 * `actor` is `req.user` (`{ id, name, familyId, memberId, role }`) so the service stays HTTP-agnostic.
 */

const asCtx = (actor) => ({ user: actor });

/** Longest task title (in user-perceived characters = grapheme clusters) quoted in a push text. */
export const PUSH_TITLE_MAX = 60;
/** Categories whose titles never appear in push texts. */
const PRIVATE_PUSH_CATEGORIES = new Set(['health']);
/** Attempts of a complete / reopen whose conditional update lost a race (see `transition`). */
const TRANSITION_ATTEMPTS = 3;
const PENDING = 'pending';
const DONE = 'done';

const graphemes = new Intl.Segmenter(undefined, { granularity: 'grapheme' });

// ---------------------------------------------------------------- helpers

function canEdit(actor, task) {
  return isAdmin(asCtx(actor)) || sameId(task.createdById, actor.memberId);
}

function canComplete(actor, task) {
  return isAdmin(asCtx(actor)) || sameId(task.assigneeId, actor.memberId);
}

function assigneeError(messageKey, message) {
  return ApiError.validation({ assigneeId: message }, 'Validation failed', { messageKey });
}

const assigneeNotInFamily = () =>
  assigneeError('tasks.errors.assigneeNotInFamily', 'Assignee must be a member of your family');
const assigneeRemoved = () =>
  assigneeError('tasks.errors.assigneeRemoved', 'The assignee is no longer a member of your family');

/** 422 `details.assigneeId` unless `assigneeId` is a member of the family (`members` map). */
function assertAssigneeInFamily(members, assigneeId) {
  if (!memberOf(members, assigneeId)) throw assigneeNotInFamily();
}

/**
 * Re-check after a write that left `task` pending: when its assignee has left the family in the
 * meantime, `undo()` the write and throw `error` (422). Done tasks may outlive their assignee.
 */
async function keepAssigneeOrUndo(actor, task, undo, error) {
  if (task.status !== PENDING) return;
  if (await Member.exists({ _id: task.assigneeId, familyId: actor.familyId })) return;
  await undo();
  throw error;
}

/** 403 unless the actor is an admin or assigns the task to themselves. */
function assertMayAssign(actor, assigneeId) {
  if (!isAdmin(asCtx(actor)) && !sameId(assigneeId, actor.memberId)) {
    throw ApiError.forbidden('Members can only assign tasks to themselves', {
      messageKey: 'tasks.errors.assignSelfOnly',
    });
  }
}

function forbiddenEdit() {
  return ApiError.forbidden('Only an admin or the creator can change this task', {
    messageKey: 'tasks.errors.editNotAllowed',
  });
}

function forbiddenComplete() {
  return ApiError.forbidden('Only the assignee or an admin can complete or reopen this task', {
    messageKey: 'tasks.errors.completeNotAllowed',
  });
}

/** Family time zone for due filters; a missing family (race with deletion) falls back to UTC. */
async function familyTimeZone(familyId) {
  const family = await Family.findById(familyId).select('timezone').lean();
  return family?.timezone;
}

/**
 * A date-only due date (`YYYY-MM-DD`, see tasks.schemas.js) → midnight of that day in the family time
 * zone. Dates, null and undefined pass through unchanged.
 */
async function resolveDueDate(value, familyId) {
  if (!isDateOnly(value)) return value;
  const [year, month, day] = value.split('-').map(Number);
  return zonedTimeToUtc({ year, month, day }, await familyTimeZone(familyId));
}

/**
 * Shortens a title for a push text by **grapheme clusters**, so a cut never splits an emoji ZWJ
 * sequence (👨‍👩‍👧), a flag (🇮🇳) or an Indic conjunct / vowel sign (क्ष, त्रि) — a half cluster shows as a
 * broken glyph or a dotted circle on the lock screen.
 */
export function pushTitle(title) {
  const text = String(title ?? '').trim();
  const clusters = Array.from(graphemes.segment(text), (part) => part.segment);
  if (clusters.length <= PUSH_TITLE_MAX) return text;
  return `${clusters.slice(0, PUSH_TITLE_MAX - 1).join('').trimEnd()}…`;
}

/**
 * Fire-and-forget push to one member about a task. Skipped when the recipient is the actor, has no
 * account (managed profile) or is no longer in the family.
 */
function notifyMember({ actor, members, recipientId, task, type, event }) {
  if (!recipientId || sameId(recipientId, actor.memberId)) return;
  const recipient = memberOf(members, recipientId);
  if (!recipient?.userId) return;
  const id = toId(task);
  const isPrivate = PRIVATE_PUSH_CATEGORIES.has(task.category);
  void sendToMembers({
    familyId: actor.familyId,
    memberIds: [toId(recipientId)],
    type,
    id,
    route: PUSH_ROUTES.task(id),
    titleKey: `tasks.push.${event}.title`,
    bodyKey: `tasks.push.${event}.${isPrivate ? 'bodyPrivate' : 'body'}`,
    vars: {
      name: nameOf(members, actor.memberId) ?? actor.name ?? '',
      ...(isPrivate ? {} : { title: pushTitle(task.title) }),
    },
  });
}

// ---------------------------------------------------------------- queries

/**
 * `GET /tasks` — paginated, contract sort order (see tasks.query.js).
 * An `assigneeId` of another family simply matches nothing.
 */
export async function listTasks(actor, { assigneeId, status = 'all', due, page, limit }) {
  const timeZone = due ? await familyTimeZone(actor.familyId) : undefined;
  const match = taskListMatch({ familyId: actor.familyId, assigneeId, status, due, timeZone });
  if (!match) return paginateArray([], { page, limit });
  const [result, members] = await Promise.all([
    paginateAggregate(Task, taskListPipeline(match), { page, limit }),
    getMemberMap(actor.familyId),
  ]);
  return { ...result, items: serializeTasks(result.items, members) };
}

/** `GET /tasks/:id` */
export async function getTask(actor, id) {
  const [task, members] = await Promise.all([
    findInFamily(Task, id, actor.familyId, { lean: true }),
    getMemberMap(actor.familyId),
  ]);
  return serializeTask(task, members);
}

// ---------------------------------------------------------------- writes

/** `POST /tasks` → created Task. */
export async function createTask(actor, body) {
  const members = await getMemberMap(actor.familyId);
  assertAssigneeInFamily(members, body.assigneeId);
  assertMayAssign(actor, body.assigneeId);

  const task = await Task.create({
    familyId: actor.familyId,
    title: body.title,
    description: body.description ?? null,
    assigneeId: body.assigneeId,
    createdById: actor.memberId,
    dueDate: (await resolveDueDate(body.dueDate, actor.familyId)) ?? null,
    category: body.category,
    priority: body.priority,
  });
  await keepAssigneeOrUndo(actor, task, () => Task.deleteOne({ _id: task._id, familyId: actor.familyId }), assigneeNotInFamily());

  notifyMember({ actor, members, recipientId: task.assigneeId, task, type: PUSH_TYPE.TASK_ASSIGNED, event: 'assigned' });
  return serializeTask(task, members);
}

const EDITABLE_FIELDS = Object.freeze(['title', 'description', 'assigneeId', 'dueDate', 'category', 'priority']);

/**
 * `PATCH /tasks/:id` — only the keys present in `body` change (`null` clears description / dueDate).
 * The assignee rules apply only when the assignee actually changes, so re-sending the current value
 * works even for a done task whose assignee has since been removed. An empty body returns the task.
 */
export async function updateTask(actor, id, body) {
  const [task, members] = await Promise.all([
    findInFamily(Task, id, actor.familyId, { lean: true }),
    getMemberMap(actor.familyId),
  ]);
  if (!canEdit(actor, task)) throw forbiddenEdit();

  const set = {};
  for (const field of EDITABLE_FIELDS) {
    if (body[field] !== undefined) set[field] = body[field];
  }
  const reassigned = set.assigneeId !== undefined && !sameId(set.assigneeId, task.assigneeId);
  if (reassigned) {
    assertAssigneeInFamily(members, set.assigneeId);
    assertMayAssign(actor, set.assigneeId);
  } else {
    delete set.assigneeId;
  }
  if (!Object.keys(set).length) return serializeTask(task, members);
  if (set.dueDate !== undefined) set.dueDate = await resolveDueDate(set.dueDate, actor.familyId);

  const updated = await Task.findOneAndUpdate(
    { _id: task._id, familyId: actor.familyId },
    { $set: set },
    { returnDocument: 'after', runValidators: true },
  ).lean();
  if (!updated) throw ApiError.notFound(); // deleted concurrently

  if (reassigned) {
    // Undo = this PATCH's fields back to their previous values, unless someone changed the task since.
    const previous = Object.fromEntries(Object.keys(set).map((field) => [field, task[field] ?? null]));
    await keepAssigneeOrUndo(
      actor,
      updated,
      () =>
        Task.updateOne(
          { _id: task._id, familyId: actor.familyId, updatedAt: updated.updatedAt },
          { $set: { ...previous, updatedAt: task.updatedAt } },
          { timestamps: false },
        ),
      assigneeNotInFamily(),
    );
    if (updated.status === PENDING) {
      notifyMember({ actor, members, recipientId: updated.assigneeId, task: updated, type: PUSH_TYPE.TASK_ASSIGNED, event: 'assigned' });
    }
  }
  return serializeTask(updated, members);
}

/**
 * Atomic status transition shared by complete / reopen. Returns `{ task, before, members, changed }`
 * (`before` = the snapshot the change was made from); when the task is already in the target state
 * (or a concurrent call won the race) it is returned unchanged.
 *
 * The permission (`canComplete`) and `beforeChange` are evaluated on a snapshot, so the update is
 * conditional on the snapshot's status **and assignee**. If the assignee changed in between, the task
 * is re-read and everything is checked again (a member who is no longer the assignee gets 403).
 */
async function transition(actor, id, { from, set, beforeChange }) {
  const [snapshot, members] = await Promise.all([
    findInFamily(Task, id, actor.familyId, { lean: true }),
    getMemberMap(actor.familyId),
  ]);
  let task = snapshot;
  for (let attempt = 1; ; attempt += 1) {
    if (!canComplete(actor, task)) throw forbiddenComplete();
    if (task.status !== from) return { task, members, changed: false };

    beforeChange?.(task, members);
    const updated = await Task.findOneAndUpdate(
      { _id: task._id, familyId: actor.familyId, status: from, assigneeId: task.assigneeId },
      { $set: set },
      { returnDocument: 'after', runValidators: true },
    ).lean();
    if (updated) return { task: updated, before: task, members, changed: true };
    if (attempt >= TRANSITION_ATTEMPTS) {
      throw ApiError.conflict('CONFLICT', 'The task changed while saving. Please try again.');
    }
    // Lost a race: status or assignee changed (a deleted task → 404). Decide again on fresh data.
    task = await findInFamily(Task, id, actor.familyId, { lean: true });
  }
}

/** `POST /tasks/:id/complete` — idempotent; `task_completed` push to the creator on the first call. */
export async function completeTask(actor, id) {
  const { task, members, changed } = await transition(actor, id, {
    from: PENDING,
    set: { status: DONE, completedAt: new Date(), completedById: actor.memberId },
  });
  if (changed) {
    notifyMember({ actor, members, recipientId: task.createdById, task, type: PUSH_TYPE.TASK_COMPLETED, event: 'completed' });
  }
  return serializeTask(task, members);
}

/**
 * `POST /tasks/:id/reopen` — idempotent. A done task whose assignee has left the family cannot become
 * pending again (removing a member deletes their pending tasks): `422 details.assigneeId`, re-assign first.
 */
export async function reopenTask(actor, id) {
  const { task, before, members, changed } = await transition(actor, id, {
    from: DONE,
    set: { status: PENDING, completedAt: null, completedById: null },
    beforeChange: (current, map) => {
      if (!memberOf(map, current.assigneeId)) throw assigneeRemoved();
    },
  });
  if (changed) {
    await keepAssigneeOrUndo(
      actor,
      task,
      () =>
        Task.updateOne(
          { _id: task._id, familyId: actor.familyId, status: PENDING, updatedAt: task.updatedAt },
          {
            $set: {
              status: DONE,
              completedAt: before.completedAt,
              completedById: before.completedById,
              updatedAt: before.updatedAt,
            },
          },
          { timestamps: false },
        ),
      assigneeRemoved(),
    );
  }
  return serializeTask(task, members);
}

/** `DELETE /tasks/:id` — admin or creator. */
export async function deleteTask(actor, id) {
  const task = await findInFamily(Task, id, actor.familyId, { lean: true, select: '_id createdById' });
  if (!canEdit(actor, task)) throw forbiddenEdit();
  await Task.deleteOne({ _id: task._id, familyId: actor.familyId });
  return null;
}
