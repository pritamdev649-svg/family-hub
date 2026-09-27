import { avatarOf, nameOf } from '../../services/memberDirectory.js';
import { idOf, iso } from '../../services/serializers.js';

/**
 * Contract `Notice` shape (docs/03-API_CONTRACT.md §9):
 * `{ id, title, body, imageUrl|null, pinned, authorId, authorName, authorAvatarUrl|null, createdAt, updatedAt }`.
 *
 * Accepts a Mongoose document or a lean object. `authorName` / `authorAvatarUrl` come from the
 * family's member map (`services/memberDirectory.js#getMemberMap`) and are `null` once the author
 * has left the family (notices outlive their author; the app shows a "former member" placeholder).
 *
 * Exported for other modules (e.g. the dashboard's `latestNotices`) so every Notice leaves the API identically.
 *
 * @param {object} notice
 * @param {Map<string, object>} members memberId → member (from getMemberMap)
 */
export function serializeNotice(notice, members) {
  if (!notice) return null;
  return {
    id: idOf(notice),
    title: notice.title,
    body: notice.body,
    imageUrl: notice.imageUrl || null,
    pinned: Boolean(notice.pinned),
    authorId: idOf(notice.authorId),
    authorName: nameOf(members, notice.authorId),
    authorAvatarUrl: avatarOf(members, notice.authorId) || null,
    createdAt: iso(notice.createdAt),
    updatedAt: iso(notice.updatedAt),
  };
}

/** Serializes a list with one shared member map. */
export function serializeNotices(list, members) {
  return (list ?? []).map((notice) => serializeNotice(notice, members));
}
