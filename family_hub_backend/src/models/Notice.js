import mongoose from 'mongoose';
import { LIMITS } from './enums.js';
import { applyToJson, defineModel, optionalString, requiredRef, requiredString, schemaOptions } from './schemaUtils.js';

/**
 * Notice board (contract §9). `authorName` / `authorAvatarUrl` are resolved at read time.
 * Only admins may set `pinned` (enforced by the notices service).
 */
const noticeSchema = new mongoose.Schema(
  {
    familyId: requiredRef('Family'),
    title: requiredString(LIMITS.NOTICE_TITLE_MAX),
    body: requiredString(LIMITS.NOTICE_BODY_MAX),
    /** Cloudinary secure_url (host validated by zod at the API edge). */
    imageUrl: optionalString(LIMITS.URL_MAX),
    pinned: { type: Boolean, default: false },
    /** Member id of the author. */
    authorId: requiredRef('Member'),
  },
  schemaOptions('notices'),
);

// "pinned first, then createdAt desc".
noticeSchema.index({ familyId: 1, pinned: -1, createdAt: -1 });

applyToJson(noticeSchema);

export const Notice = defineModel('Notice', noticeSchema);
export default Notice;
