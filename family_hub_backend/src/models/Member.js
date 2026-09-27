import mongoose from 'mongoose';
import { DEFAULT_LOCATION_SHARING, GENDERS, LIMITS, LOCATION_SHARING, ROLE, ROLES } from './enums.js';
import {
  EMAIL_REGEX,
  applyToJson,
  defineModel,
  emptyToNull,
  locationPointSchema,
  optionalRef,
  optionalString,
  requiredRef,
  requiredString,
  schemaOptions,
} from './schemaUtils.js';

/**
 * A person in a family ("employee"). Contract §2 "Member".
 * - `userId` null → managed profile (young kid / elder without a phone), `hasAccount=false`.
 * - `lastLocation` must only be serialised when `locationSharing === 'always'`
 *   (serializeMember applies that rule).
 */
const memberSchema = new mongoose.Schema(
  {
    familyId: requiredRef('Family'),
    userId: optionalRef('User'),
    name: requiredString(LIMITS.NAME_MAX),
    email: {
      type: String,
      trim: true,
      lowercase: true,
      maxlength: LIMITS.EMAIL_MAX,
      match: [EMAIL_REGEX, 'Invalid email'],
      default: null,
      // '' must become null: the {familyId,email} unique index only covers string values.
      set: emptyToNull,
    },
    phone: optionalString(LIMITS.PHONE_MAX),
    avatarUrl: optionalString(LIMITS.URL_MAX),
    dateOfBirth: { type: Date, default: null },
    gender: { type: String, enum: GENDERS, default: null, set: emptyToNull },
    /** Free-text "company title", e.g. "Head of Family", "Finance Head". */
    designation: optionalString(LIMITS.DESIGNATION_MAX),
    role: { type: String, required: true, enum: ROLES, default: ROLE.MEMBER },
    /** Privacy by default: nothing is shared until the member opts in. */
    locationSharing: { type: String, required: true, enum: LOCATION_SHARING, default: DEFAULT_LOCATION_SHARING },
    lastLocation: { type: locationPointSchema(), default: null },

    // Verifiable guardian consent for members below the country's consent age (DPDP/GDPR).
    guardianConsent: { type: Boolean, default: false },
    guardianConsentAt: { type: Date, default: null },
    /** Admin member who confirmed the guardian consent. */
    guardianConsentById: optionalRef('Member'),
  },
  schemaOptions('members'),
);

// Listing a family's members + counting admins (LAST_ADMIN checks).
memberSchema.index({ familyId: 1, role: 1 });
// E-mail unique within a family, only when an e-mail is set (managed profiles have none).
memberSchema.index(
  { familyId: 1, email: 1 },
  { unique: true, partialFilterExpression: { email: { $type: 'string' } } },
);
// An account is linked to at most one member.
memberSchema.index({ userId: 1 }, { unique: true, partialFilterExpression: { userId: { $type: 'objectId' } } });

/** Contract field `hasAccount`: true when a user account is linked. */
memberSchema.virtual('hasAccount').get(function hasAccount() {
  return Boolean(this.userId);
});

applyToJson(memberSchema);

export const Member = defineModel('Member', memberSchema);
export default Member;
