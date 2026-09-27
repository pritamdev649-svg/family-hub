import mongoose from 'mongoose';
import { decryptField, encryptField } from '../lib/crypto.js';
import { BLOOD_GROUPS, EMERGENCY_CARD_ENCRYPTED_FIELDS, EMERGENCY_CARD_LIST_FIELDS, LIMITS } from './enums.js';
import {
  applyToJson,
  defineModel,
  optionalRef,
  optionalString,
  requiredRef,
  requiredString,
  schemaOptions,
} from './schemaUtils.js';

/**
 * Emergency quick-access card, one per member (contract §6 "EmergencyCard").
 *
 * Health data and the policy number are encrypted at rest with AES-256-GCM
 * (src/lib/crypto.js). The `*Enc` paths hold `enc:v1:…` strings and are never serialised.
 * Read/write them through the plaintext virtuals:
 *
 *   card.allergies = ['Peanuts'];          // → allergiesEnc = encryptField([...])
 *   card.allergies                         // → ['Peanuts'] (decrypted), [] when empty
 *   card.toPlainCard()                     // → contract-shaped object
 *   EmergencyCard.emptyCard(memberId)      // → contract "empty card" (updatedAt: null)
 *
 * Virtuals are not available on `.lean()` results; use `decryptField` there.
 * A decryption failure throws (wrong FIELD_ENCRYPTION_KEY) rather than silently
 * returning "no allergies", which would be dangerous in an emergency.
 */

/**
 * plaintext virtual → encrypted path, and the value returned when nothing is stored.
 * Built from `EMERGENCY_CARD_ENCRYPTED_FIELDS` (models/enums.js) so the list used by the
 * API layer and the schema can never drift apart:
 * `{ allergies: { path: 'allergiesEnc', empty: () => [] }, …, notes: { path: 'notesEnc', empty: () => null } }`.
 */
export const ENCRYPTED_CARD_FIELDS = Object.freeze(
  Object.fromEntries(
    EMERGENCY_CARD_ENCRYPTED_FIELDS.map((name) => [
      name,
      Object.freeze({
        path: `${name}Enc`,
        empty: EMERGENCY_CARD_LIST_FIELDS.includes(name) ? () => [] : () => null,
      }),
    ]),
  ),
);

const emergencyContactSchema = new mongoose.Schema(
  {
    name: requiredString(LIMITS.CARD_TEXT_MAX),
    phone: optionalString(LIMITS.PHONE_MAX),
    relation: optionalString(LIMITS.CARD_RELATION_MAX),
  },
  { _id: false, id: false },
);

/** `allergiesEnc`, `medicationsEnc`, … — `enc:v1:…` strings (or null when empty). */
const encryptedPaths = Object.fromEntries(
  Object.values(ENCRYPTED_CARD_FIELDS).map(({ path }) => [path, { type: String, default: null }]),
);

const emergencyCardSchema = new mongoose.Schema(
  {
    familyId: requiredRef('Family'),
    memberId: requiredRef('Member'),
    bloodGroup: { type: String, required: true, enum: BLOOD_GROUPS, default: 'unknown' },
    ...encryptedPaths,
    doctorName: optionalString(LIMITS.CARD_TEXT_MAX),
    doctorPhone: optionalString(LIMITS.PHONE_MAX),
    insuranceProvider: optionalString(LIMITS.CARD_TEXT_MAX),
    emergencyContacts: {
      type: [emergencyContactSchema],
      default: [],
      validate: {
        validator: (v) => !v || v.length <= LIMITS.CARD_CONTACTS_MAX,
        message: `At most ${LIMITS.CARD_CONTACTS_MAX} emergency contacts`,
      },
    },
    /** Member who last saved the card (self or an admin). */
    updatedById: optionalRef('Member'),
  },
  schemaOptions('emergency_cards'),
);

emergencyCardSchema.index({ memberId: 1 }, { unique: true });
emergencyCardSchema.index({ familyId: 1 });

function isBlank(value) {
  if (value === null || value === undefined) return true;
  if (Array.isArray(value)) return value.length === 0;
  return typeof value === 'string' && value.trim() === '';
}

for (const [name, { path, empty }] of Object.entries(ENCRYPTED_CARD_FIELDS)) {
  emergencyCardSchema
    .virtual(name)
    .get(function getDecrypted() {
      const stored = this.get(path);
      return stored === null || stored === undefined ? empty() : decryptField(stored);
    })
    .set(function setEncrypted(value) {
      this.set(path, isBlank(value) ? null : encryptField(typeof value === 'string' ? value.trim() : value));
    });
}

/** Contract-shaped plaintext card (docs/03-API_CONTRACT.md §6). */
emergencyCardSchema.methods.toPlainCard = function toPlainCard() {
  return {
    memberId: String(this.memberId),
    bloodGroup: this.bloodGroup ?? 'unknown',
    allergies: this.allergies,
    medications: this.medications,
    conditions: this.conditions,
    doctorName: this.doctorName ?? null,
    doctorPhone: this.doctorPhone ?? null,
    insuranceProvider: this.insuranceProvider ?? null,
    insurancePolicyNumber: this.insurancePolicyNumber,
    emergencyContacts: (this.emergencyContacts ?? []).map((c) => ({
      name: c.name,
      phone: c.phone ?? null,
      relation: c.relation ?? null,
    })),
    notes: this.notes,
    updatedAt: this.updatedAt ? this.updatedAt.toISOString() : null,
    updatedById: this.updatedById ? String(this.updatedById) : null,
  };
};

/** The card returned when a member has none saved yet (`updatedAt: null`). */
emergencyCardSchema.statics.emptyCard = function emptyCard(memberId) {
  return {
    memberId: String(memberId),
    bloodGroup: 'unknown',
    allergies: [],
    medications: [],
    conditions: [],
    doctorName: null,
    doctorPhone: null,
    insuranceProvider: null,
    insurancePolicyNumber: null,
    emergencyContacts: [],
    notes: null,
    updatedAt: null,
    updatedById: null,
  };
};

// Raw ciphertext never leaves the server; decrypted virtuals are included instead.
applyToJson(emergencyCardSchema, { hide: Object.values(ENCRYPTED_CARD_FIELDS).map((f) => f.path) });

export const EmergencyCard = defineModel('EmergencyCard', emergencyCardSchema);
export default EmergencyCard;
