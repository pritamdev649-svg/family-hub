import mongoose from 'mongoose';
import { LIMITS, SOS_DURATION_MS, SOS_RESOLUTIONS, SOS_STATUSES, SOS_TRAIL_MAX } from './enums.js';
import {
  applyToJson,
  defineModel,
  locationPointSchema,
  optionalRef,
  optionalString,
  requiredRef,
  schemaOptions,
} from './schemaUtils.js';

/**
 * SOS alert with a live-location window (contract §10). Alerts family members only —
 * never emergency services.
 *
 * - `expiresAt = startedAt + 15 min` (default below).
 * - Status is computed lazily: an `active` alert past `expiresAt` is persisted/returned as
 *   `expired` — use `SosAlert.expireStale()` before reading and `alert.effectiveStatus()`.
 * - `trail` holds at most 100 points, appended with
 *   `{ $push: { trail: { $each: [point], $slice: -SOS_TRAIL_MAX } } }`. List endpoints should
 *   project it away (`.select('-trail')`); only `GET /sos/:id` returns it.
 * - `locationShared=false` (member's sharing mode is `never`) → no location is ever stored.
 */
const sosAlertSchema = new mongoose.Schema(
  {
    familyId: requiredRef('Family'),
    /** Member who raised the alert. */
    memberId: requiredRef('Member'),
    status: { type: String, required: true, enum: SOS_STATUSES, default: 'active' },
    message: optionalString(LIMITS.SOS_MESSAGE_MAX),
    locationShared: { type: Boolean, default: false },
    lastLocation: { type: locationPointSchema(), default: null },
    trail: {
      type: [locationPointSchema()],
      default: [],
      validate: {
        validator: (v) => !v || v.length <= SOS_TRAIL_MAX,
        message: `trail cannot hold more than ${SOS_TRAIL_MAX} points`,
      },
    },
    /** Server time of the last *stored* location (drives the 3 s throttle). */
    lastLocationAt: { type: Date, default: null },
    startedAt: { type: Date, required: true, default: Date.now },
    expiresAt: {
      type: Date,
      required: true,
      default: function defaultExpiresAt() {
        const start = this.startedAt instanceof Date ? this.startedAt : new Date();
        return new Date(start.getTime() + SOS_DURATION_MS);
      },
    },
    resolvedAt: { type: Date, default: null },
    resolvedById: optionalRef('Member'),
    resolution: { type: String, enum: SOS_RESOLUTIONS, default: null },
  },
  schemaOptions('sos_alerts'),
);

sosAlertSchema.index({ familyId: 1, status: 1 });
sosAlertSchema.index({ memberId: 1, status: 1 });

/** `expired` when still `active` in the DB but past `expiresAt`. */
sosAlertSchema.methods.effectiveStatus = function effectiveStatus(now = new Date()) {
  if (this.status === 'active' && this.expiresAt && this.expiresAt.getTime() <= now.getTime()) return 'expired';
  return this.status;
};

sosAlertSchema.methods.isActive = function isActive(now = new Date()) {
  return this.effectiveStatus(now) === 'active';
};

/**
 * Persists the lazy expiry: marks `active` alerts past `expiresAt` as `expired`.
 * Scope it with a filter, e.g. `SosAlert.expireStale({ familyId })`.
 * @returns {Promise<number>} number of alerts expired
 */
sosAlertSchema.statics.expireStale = async function expireStale(filter = {}, now = new Date()) {
  const res = await this.updateMany(
    { ...filter, status: 'active', expiresAt: { $lte: now } },
    { $set: { status: 'expired' } },
  );
  return res.modifiedCount ?? 0;
};

applyToJson(sosAlertSchema);

export const SosAlert = defineModel('SosAlert', sosAlertSchema);
export default SosAlert;
