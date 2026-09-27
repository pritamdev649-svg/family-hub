import { findInFamily, isAdmin, isObjectId, sameId, toId } from '../../lib/access.js';
import { ApiError } from '../../lib/ApiError.js';
import { DASHBOARD_LIMITS, MAX_PAGE_LIMIT, PUSH_ROUTES, PUSH_TYPE } from '../../lib/constants.js';
import { paginate } from '../../lib/pagination.js';
import { Notice } from '../../models/index.js';
import { getMemberMap, nameOf } from '../../services/memberDirectory.js';
import { sendToMembers } from '../../services/push.js';
import { pushTitle } from '../tasks/tasks.service.js';
import { serializeNotice, serializeNotices } from './notices.serializer.js';

/**
 * Family notice board (docs/03-API_CONTRACT.md §9; roles: docs/02-ARCHITECTURE.md §11.2).
 *
 *   list            any member of the family; pinned first, then newest first (paginated)
 *   create          any member; `pinned` is honoured for admins only (silently ignored for members)
 *   update / delete the notice's author or an admin; changing `pinned` needs an admin
 *
 * Check order inside a write: 404 (unknown id / another family's notice — never leaks existence) →
 * 403 (not author nor admin) → 403 (a member changing `pinned`). Nothing is written on an error.
 *
 * Push (fire-and-forget, contract §13): `notice` → every other member of the family with an account,
 * route `/notices`, only on create. The text carries the author's name and a shortened title — never
 * the notice body (lock screens are visible to others, docs/08-COMPLIANCE.md §3 row 20).
 *
 * `actor` is `req.user` (`{ id, name, familyId, memberId, role }`) so the service stays HTTP-agnostic.
 */

/** Contract order "pinned first, then createdAt desc"; `_id` desc breaks ties so pages never overlap. */
export const NOTICE_SORT = Object.freeze({ pinned: -1, createdAt: -1, _id: -1 });

const EDITABLE_TEXT_FIELDS = Object.freeze(['title', 'body', 'imageUrl']);

const asCtx = (actor) => ({ user: actor });

// ---------------------------------------------------------------- helpers

function canEdit(actor, notice) {
  return isAdmin(asCtx(actor)) || sameId(notice.authorId, actor.memberId);
}

function forbiddenEdit() {
  return ApiError.forbidden('Only an admin or the author can change this notice', {
    messageKey: 'notices.errors.editNotAllowed',
  });
}

function forbiddenPin() {
  return ApiError.forbidden('Only an admin can pin or unpin notices', {
    messageKey: 'notices.errors.pinAdminOnly',
  });
}

/** true when at least one other member of the family has an account (a possible push recipient). */
function hasOtherAccountHolders(members, actor) {
  for (const member of members.values()) {
    if (member.userId && !sameId(member._id, actor.memberId)) return true;
  }
  return false;
}

/** Fire-and-forget `notice` push to every other member of the family. */
function notifyFamily(actor, members, notice) {
  if (!hasOtherAccountHolders(members, actor)) return;
  const id = toId(notice);
  void sendToMembers({
    familyId: actor.familyId,
    excludeMemberIds: [actor.memberId],
    type: PUSH_TYPE.NOTICE,
    id,
    route: PUSH_ROUTES.notices(),
    titleKey: notice.pinned ? 'notices.push.new.titlePinned' : 'notices.push.new.title',
    bodyKey: 'notices.push.new.body',
    vars: {
      name: nameOf(members, actor.memberId) ?? actor.name ?? '',
      title: pushTitle(notice.title),
    },
  });
}

// ---------------------------------------------------------------- queries

/** `GET /notices` — paginated, pinned first then newest first. */
export async function listNotices(actor, { page, limit } = {}) {
  const [result, members] = await Promise.all([
    paginate(Notice, { familyId: actor.familyId }, { page, limit, sort: NOTICE_SORT, lean: true }),
    getMemberMap(actor.familyId),
  ]);
  return { ...result, items: serializeNotices(result.items, members) };
}

/**
 * The newest notices of a family in board order (pinned first) — for the dashboard's `latestNotices`.
 * Pass the request's member map when you already have one to save a query.
 *
 * Defensive for callers outside HTTP validation: a missing / malformed family id or a limit below 1
 * returns `[]` (never a CastError → 500), and the limit is capped at MAX_PAGE_LIMIT (100).
 *
 * @param {string} familyId
 * @param {{ limit?: number, members?: Map<string, object> }} [opts]
 * @returns {Promise<object[]>} serialized Notices
 */
export async function listLatestNotices(familyId, { limit = DASHBOARD_LIMITS.NOTICES, members } = {}) {
  const max = Math.min(Math.floor(Number(limit)), MAX_PAGE_LIMIT);
  if (!isObjectId(familyId) || !(max >= 1)) return [];
  const [notices, map] = await Promise.all([
    Notice.find({ familyId }).sort(NOTICE_SORT).limit(max).lean(),
    members ?? getMemberMap(familyId),
  ]);
  return serializeNotices(notices, map);
}

// ---------------------------------------------------------------- writes

/** `POST /notices` → created Notice (201). */
export async function createNotice(actor, { title, body, imageUrl, pinned }) {
  const members = await getMemberMap(actor.familyId);
  const notice = await Notice.create({
    familyId: actor.familyId,
    title,
    body,
    imageUrl: imageUrl ?? null,
    pinned: isAdmin(asCtx(actor)) && pinned === true,
    authorId: actor.memberId,
  });
  notifyFamily(actor, members, notice);
  return serializeNotice(notice, members);
}

/**
 * `PATCH /notices/:id` — only keys present in `body` that differ from the stored value are written
 * (`imageUrl: null` removes the image). Sending the current `pinned` value is allowed for anyone who
 * may edit; changing it needs an admin. A request that changes nothing returns the notice untouched
 * (no write, `updatedAt` kept).
 */
export async function updateNotice(actor, id, body) {
  const [notice, members] = await Promise.all([
    findInFamily(Notice, id, actor.familyId, { lean: true }),
    getMemberMap(actor.familyId),
  ]);
  if (!canEdit(actor, notice)) throw forbiddenEdit();

  const set = {};
  for (const field of EDITABLE_TEXT_FIELDS) {
    if (body[field] !== undefined && body[field] !== (notice[field] ?? null)) set[field] = body[field];
  }
  if (body.pinned !== undefined && body.pinned !== Boolean(notice.pinned)) {
    if (!isAdmin(asCtx(actor))) throw forbiddenPin();
    set.pinned = body.pinned;
  }
  if (!Object.keys(set).length) return serializeNotice(notice, members);

  const updated = await Notice.findOneAndUpdate(
    { _id: notice._id, familyId: actor.familyId },
    { $set: set },
    { returnDocument: 'after', runValidators: true },
  ).lean();
  if (!updated) throw ApiError.notFound(); // deleted concurrently
  return serializeNotice(updated, members);
}

/** `DELETE /notices/:id` — author or admin → `null`. A repeat (or a concurrent loser) gets 404. */
export async function deleteNotice(actor, id) {
  const notice = await findInFamily(Notice, id, actor.familyId, { lean: true, select: '_id authorId' });
  if (!canEdit(actor, notice)) throw forbiddenEdit();
  const { deletedCount } = await Notice.deleteOne({ _id: notice._id, familyId: actor.familyId });
  if (!deletedCount) throw ApiError.notFound();
  return null;
}
