import mongoose from 'mongoose';
import { DEFAULT_LOCALE, LIMITS, LOCALES } from './enums.js';
import { EMAIL_REGEX, applyToJson, defineModel, optionalRef, requiredString, schemaOptions } from './schemaUtils.js';

/**
 * Account (login identity). A user belongs to at most one family through `familyId` +
 * `memberId`; both are null when the user has not joined a family yet or was removed.
 * Contract: docs/03-API_CONTRACT.md §2 "User".
 */
const userSchema = new mongoose.Schema(
  {
    email: {
      type: String,
      required: true,
      trim: true,
      lowercase: true,
      maxlength: LIMITS.EMAIL_MAX,
      match: [EMAIL_REGEX, 'Invalid email'],
    },
    /** bcrypt hash. Never serialised (hidden by toJSON; serializers must not expose it). */
    passwordHash: { type: String, required: true },
    name: requiredString(LIMITS.NAME_MAX),
    /** Preferred language for push notifications and e-mails. */
    locale: { type: String, enum: LOCALES, default: DEFAULT_LOCALE },
    emailVerified: { type: Boolean, default: false },

    familyId: optionalRef('Family'),
    memberId: optionalRef('Member'),

    // Login lockout: 5 failed attempts within 15 min → 429 (auth service owns the rule).
    failedLoginCount: { type: Number, default: 0, min: 0 },
    /** Start of the current failed-login window (lets the service reset the counter after 15 min). */
    lastFailedLoginAt: { type: Date, default: null },
    lockUntil: { type: Date, default: null },
    lastLoginAt: { type: Date, default: null },

    /** When the user accepted the privacy policy + terms at registration (DPDP/GDPR consent record). */
    consentAcceptedAt: { type: Date, default: null },
  },
  schemaOptions('users'),
);

userSchema.index({ email: 1 }, { unique: true });
userSchema.index({ familyId: 1 });

userSchema.virtual('isLocked').get(function isLocked() {
  return Boolean(this.lockUntil && this.lockUntil.getTime() > Date.now());
});

applyToJson(userSchema, { hide: ['passwordHash', 'failedLoginCount', 'lastFailedLoginAt', 'lockUntil'] });

export const User = defineModel('User', userSchema);
export default User;
