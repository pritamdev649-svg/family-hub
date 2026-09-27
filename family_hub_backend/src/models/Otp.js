import mongoose from 'mongoose';
import { LIMITS, OTP_PURPOSES } from './enums.js';
import { EMAIL_REGEX, applyToJson, defineModel, optionalRef, schemaOptions } from './schemaUtils.js';

/**
 * One-time codes for e-mail verification and password reset (contract §4).
 * At most one live code per (email, purpose): re-sending replaces the row (upsert).
 * Only the sha256 hash of the 6-digit code is stored.
 *
 * Rules owned by the auth service: valid 10 min, max 5 attempts, resend cooldown 60 s
 * (`lastSentAt`). The service must always compare `expiresAt` with "now" itself.
 */

/** Rows are purged 1 h after `expiresAt`, so the API can still answer OTP_EXPIRED (not INVALID_OTP) meanwhile. */
export const OTP_PURGE_GRACE_SECONDS = 60 * 60;

const otpSchema = new mongoose.Schema(
  {
    email: {
      type: String,
      required: true,
      trim: true,
      lowercase: true,
      maxlength: LIMITS.EMAIL_MAX,
      match: [EMAIL_REGEX, 'Invalid email'],
    },
    purpose: { type: String, required: true, enum: OTP_PURPOSES },
    codeHash: { type: String, required: true },
    expiresAt: { type: Date, required: true },
    attempts: { type: Number, default: 0, min: 0 },
    lastSentAt: { type: Date, default: Date.now },
    userId: optionalRef('User'),
  },
  schemaOptions('otps'),
);

otpSchema.index({ email: 1, purpose: 1 }, { unique: true });
otpSchema.index({ expiresAt: 1 }, { expireAfterSeconds: OTP_PURGE_GRACE_SECONDS });

otpSchema.methods.isExpired = function isExpired(now = new Date()) {
  return this.expiresAt.getTime() <= now.getTime();
};

applyToJson(otpSchema, { hide: ['codeHash'] });

export const Otp = defineModel('Otp', otpSchema);
export default Otp;
