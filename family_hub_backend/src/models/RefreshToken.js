import mongoose from 'mongoose';
import { applyToJson, defineModel, requiredRef, schemaOptions, truncate } from './schemaUtils.js';

/**
 * Opaque refresh tokens, stored as sha256 hashes only (contract §2 "Tokens").
 * Rotated on every refresh: the old row gets `revokedAt` + `replacedByHash`.
 * Revoked rows are kept until `expiresAt` so that reuse of a rotated token can be
 * detected (→ revoke all of the user's tokens). MongoDB's TTL monitor then deletes them.
 */
const refreshTokenSchema = new mongoose.Schema(
  {
    userId: requiredRef('User'),
    tokenHash: { type: String, required: true },
    expiresAt: { type: Date, required: true },
    revokedAt: { type: Date, default: null },
    /** Hash of the token that replaced this one during rotation (null if revoked by logout/reset). */
    replacedByHash: { type: String, default: null },
    ip: { type: String, default: null, set: truncate() },
    userAgent: { type: String, default: null, set: truncate() },
  },
  schemaOptions('refresh_tokens'),
);

refreshTokenSchema.index({ tokenHash: 1 }, { unique: true });
refreshTokenSchema.index({ userId: 1 });
refreshTokenSchema.index({ expiresAt: 1 }, { expireAfterSeconds: 0 });

/** Active = not revoked and not expired (the TTL monitor runs only every ~60 s). */
refreshTokenSchema.methods.isActive = function isActive(now = new Date()) {
  return !this.revokedAt && this.expiresAt.getTime() > now.getTime();
};

applyToJson(refreshTokenSchema, { hide: ['tokenHash', 'replacedByHash'] });

export const RefreshToken = defineModel('RefreshToken', refreshTokenSchema);
export default RefreshToken;
