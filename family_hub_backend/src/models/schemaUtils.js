import mongoose from 'mongoose';
import { isValidTimeZone } from '../lib/dates.js';
import { toJsonPlugin } from '../lib/mongoosePlugins.js';
import { LIMITS, MAX_AMOUNT_MINOR } from './enums.js';

const { Schema } = mongoose;

/** Shorthand used by every model. */
export const ObjectId = Schema.Types.ObjectId;

/**
 * Compiles a model once (safe under `node --watch`, test re-imports and hot reload).
 * @template T
 * @param {string} name
 * @param {mongoose.Schema} schema
 * @returns {mongoose.Model<T>}
 */
export function defineModel(name, schema) {
  return mongoose.models[name] || mongoose.model(name, schema);
}

/**
 * toJSON options shared by all models: exposes `id` (string), drops `_id` and `__v`,
 * flattens ObjectIds to hex strings, includes virtuals and removes the secret fields
 * listed in `hide`.
 *
 * The id conventions come from `toJsonPlugin` (src/lib/mongoosePlugins.js), applied here per
 * schema rather than via `mongoose.plugin()` in models/index.js: ES module imports are
 * evaluated before index.js' body runs, so a global plugin registered there would be too
 * late for models that are already compiled.
 *
 * The API serializers (src/services/serializers.js) still decide the exact response
 * shape; this transform is the safe default for anything that is `res.json()`-ed directly.
 */
export function applyToJson(schema, { hide = [], virtuals = true } = {}) {
  const hidden = [...hide];
  schema.set('toJSON', {
    virtuals,
    versionKey: false,
    flattenObjectIds: true,
    transform(_doc, ret) {
      for (const field of hidden) delete ret[field];
      return ret;
    },
  });
  // Composes the id transform (`id` string, no `_id` / `__v`) with the one above.
  schema.plugin(toJsonPlugin);
  return schema;
}

/** Common schema options: timestamps, explicit collection name, strict writes. */
export function schemaOptions(collection, extra = {}) {
  return { collection, timestamps: true, strict: true, id: true, ...extra };
}

// ---------- Setters ----------

/** '' / whitespace-only → null. Critical for partial unique indexes on optional strings. */
export function emptyToNull(value) {
  return typeof value === 'string' && value.trim() === '' ? null : value;
}

/** Truncates (never rejects) metadata strings such as IP addresses and user agents. */
export function truncate(max = LIMITS.META_MAX) {
  return (value) => {
    if (value === undefined || value === null) return value;
    const s = String(value);
    return s.length > max ? s.slice(0, max) : s;
  };
}

// ---------- Validators ----------

/** true when `value` is an IANA time zone understood by this runtime (same check as the zod `timeZone` block). */
export { isValidTimeZone };

/** Minimal e-mail sanity check (zod does the strict validation at the API edge). */
export const EMAIL_REGEX = /^[^\s@]+@[^\s@]+$/;

/**
 * Field definition for money stored as integer minor units.
 * @param {{ min?: number, max?: number, required?: boolean, default?: number }} opts
 */
export function minorUnits({ min = 1, max = MAX_AMOUNT_MINOR, required = true, ...rest } = {}) {
  return {
    type: Number,
    required,
    min,
    max,
    validate: {
      validator: (v) => v === null || v === undefined || Number.isSafeInteger(v),
      message: '{PATH} must be an integer amount in minor units',
    },
    ...rest,
  };
}

/** Optional trimmed string: '' → null, default null, with a max length. */
export function optionalString(maxlength, extra = {}) {
  return { type: String, trim: true, maxlength, default: null, set: emptyToNull, ...extra };
}

/** Required trimmed string with min/max length. */
export function requiredString(maxlength, { minlength = 1, ...extra } = {}) {
  return { type: String, required: true, trim: true, minlength, maxlength, ...extra };
}

/** Optional reference to another collection (default null). */
export function optionalRef(ref, extra = {}) {
  return { type: ObjectId, ref, default: null, ...extra };
}

/** Required reference to another collection. */
export function requiredRef(ref, extra = {}) {
  return { type: ObjectId, ref, required: true, ...extra };
}

// ---------- Shared sub-schemas ----------

/**
 * `{ lat, lng, accuracy, recordedAt }` used by Member.lastLocation and SosAlert
 * lastLocation / trail. A factory so each parent owns its own Schema instance.
 */
export function locationPointSchema() {
  return new Schema(
    {
      lat: { type: Number, required: true, min: -90, max: 90 },
      lng: { type: Number, required: true, min: -180, max: 180 },
      accuracy: { type: Number, min: 0, default: null },
      recordedAt: { type: Date, required: true, default: Date.now },
    },
    { _id: false, id: false },
  );
}
