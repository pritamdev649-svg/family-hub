import mongoose from 'mongoose';
import { randomInviteCode } from '../lib/crypto.js';
import { INVITE_CODE_INPUT_REGEX, INVITE_CODE_LENGTH, LIMITS } from './enums.js';
import { applyToJson, defineModel, isValidTimeZone, requiredRef, requiredString, schemaOptions } from './schemaUtils.js';

/**
 * The "company". Contract §2 "Family". `memberCount` is computed by the service,
 * and `inviteCode` must only be serialised for admins (serializeFamily handles that).
 */
const familySchema = new mongoose.Schema(
  {
    name: requiredString(LIMITS.NAME_MAX),
    /**
     * Stored upper-case; look-ups must upper-case the user input (matching is
     * case-insensitive). Defaults to a random code from ABCDEFGHJKLMNPQRSTUVWXYZ23456789;
     * on the (rare) duplicate-key error the service regenerates and retries. Any 8
     * letters/digits are storable (INVITE_CODE_INPUT_REGEX) so the demo seed code
     * `DEMO2345` works — generated codes never contain 0/O/1/I.
     */
    inviteCode: {
      type: String,
      required: true,
      trim: true,
      uppercase: true,
      minlength: INVITE_CODE_LENGTH,
      maxlength: INVITE_CODE_LENGTH,
      match: [INVITE_CODE_INPUT_REGEX, 'Invalid invite code'],
      default: () => randomInviteCode(INVITE_CODE_LENGTH),
    },
    /** ISO 3166-1 alpha-2 (drives consent age + emergency number). */
    country: {
      type: String,
      required: true,
      trim: true,
      uppercase: true,
      match: [/^[A-Z]{2}$/, 'Invalid country code'],
    },
    /** ISO 4217. */
    currency: {
      type: String,
      required: true,
      trim: true,
      uppercase: true,
      match: [/^[A-Z]{3}$/, 'Invalid currency code'],
    },
    /** IANA time zone, e.g. "Asia/Kolkata" — used for month ranges and "today/this week". */
    timezone: {
      type: String,
      required: true,
      trim: true,
      maxlength: LIMITS.TIMEZONE_MAX,
      validate: { validator: isValidTimeZone, message: 'Invalid time zone' },
    },
    /** User who created the family. */
    ownerId: requiredRef('User'),
  },
  schemaOptions('families'),
);

familySchema.index({ inviteCode: 1 }, { unique: true });

applyToJson(familySchema);

export const Family = defineModel('Family', familySchema);
export default Family;
