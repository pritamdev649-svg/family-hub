import mongoose from 'mongoose';
import { ALL_LEDGER_CATEGORIES, LEDGER_TYPES, LIMITS, isLedgerCategoryFor } from './enums.js';
import {
  applyToJson,
  defineModel,
  minorUnits,
  optionalRef,
  optionalString,
  requiredRef,
  requiredString,
  schemaOptions,
} from './schemaUtils.js';

/**
 * Shared family ledger (contract §8). Amounts are integer minor units (`amountMinor`);
 * the API exposes decimal major units via src/lib/money.js.
 * `memberName` is a snapshot so entries stay readable after the member is deleted.
 */

/**
 * `category` must belong to `type`. On documents `this` is the entry; in update
 * validators (`runValidators: true`) `this` is the Query, so the type is read from the
 * update when present, otherwise any known category is accepted (the service validates
 * type/category together with zod before updating).
 */
function categoryMatchesType(category) {
  if (this instanceof mongoose.Query) {
    const update = this.getUpdate() ?? {};
    const type = update.$set?.type ?? update.type;
    return type ? isLedgerCategoryFor(type, category) : ALL_LEDGER_CATEGORIES.includes(category);
  }
  return isLedgerCategoryFor(this.type, category);
}

const ledgerEntrySchema = new mongoose.Schema(
  {
    familyId: requiredRef('Family'),
    type: { type: String, required: true, enum: LEDGER_TYPES },
    amountMinor: minorUnits({ min: 1 }),
    category: {
      type: String,
      required: true,
      enum: ALL_LEDGER_CATEGORIES,
      validate: { validator: categoryMatchesType, message: 'Category {VALUE} is not valid for this entry type' },
    },
    note: optionalString(LIMITS.LEDGER_NOTE_MAX),
    /** Business date of the entry (family-local midnight, stored in UTC). */
    date: { type: Date, required: true },
    /** Member the money belongs to (defaults to the creator in the service). */
    memberId: requiredRef('Member'),
    memberName: requiredString(LIMITS.NAME_MAX),
    createdById: requiredRef('Member'),
    /** Set for `expense/savings` entries created by a goal contribution. */
    goalId: optionalRef('Goal'),
  },
  schemaOptions('ledger_entries'),
);

ledgerEntrySchema.index({ familyId: 1, date: -1 });
ledgerEntrySchema.index({ familyId: 1, memberId: 1, date: -1 });
ledgerEntrySchema.index({ goalId: 1 });

applyToJson(ledgerEntrySchema);

export const LedgerEntry = defineModel('LedgerEntry', ledgerEntrySchema);
export default LedgerEntry;
