import mongoose from 'mongoose';
import { DEVICE_PLATFORMS, LOCALES } from './enums.js';
import { applyToJson, defineModel, emptyToNull, requiredRef, schemaOptions } from './schemaUtils.js';

/**
 * FCM registration tokens (contract §5 `POST /me/devices`, §13).
 * Upserted by token: a token that shows up for another user moves to that user.
 * `locale` (optional) overrides the user's locale for pushes to this device.
 */

/** FCM treats tokens idle for 270 days as stale; we purge them at the same age. */
export const DEVICE_STALE_AFTER_SECONDS = 270 * 24 * 60 * 60;

const deviceSchema = new mongoose.Schema(
  {
    userId: requiredRef('User'),
    token: { type: String, required: true, trim: true, maxlength: 4096 },
    platform: { type: String, required: true, enum: DEVICE_PLATFORMS },
    locale: { type: String, enum: LOCALES, default: null, set: emptyToNull },
    lastSeenAt: { type: Date, default: Date.now },
  },
  schemaOptions('devices'),
);

deviceSchema.index({ token: 1 }, { unique: true });
deviceSchema.index({ userId: 1 });
deviceSchema.index({ lastSeenAt: 1 }, { expireAfterSeconds: DEVICE_STALE_AFTER_SECONDS });

// Every save / single-document update counts as "seen", so an active device is never purged
// by the TTL index even if the caller forgets to bump `lastSeenAt`.
deviceSchema.pre('save', async function touchOnSave() {
  if (!this.isModified('lastSeenAt')) this.lastSeenAt = new Date();
});

async function touchOnUpdate() {
  const update = this.getUpdate() ?? {};
  if (Array.isArray(update)) return; // aggregation-pipeline update: leave untouched
  const explicit = update.lastSeenAt ?? update.$set?.lastSeenAt ?? update.$setOnInsert?.lastSeenAt;
  if (explicit === undefined) this.set('lastSeenAt', new Date());
}
deviceSchema.pre('findOneAndUpdate', touchOnUpdate);
deviceSchema.pre('updateOne', touchOnUpdate);

applyToJson(deviceSchema);

export const Device = defineModel('Device', deviceSchema);
export default Device;
