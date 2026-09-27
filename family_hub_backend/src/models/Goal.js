import mongoose from 'mongoose';
import { GOAL_STATUSES, LIMITS } from './enums.js';
import { applyToJson, defineModel, minorUnits, optionalString, requiredRef, requiredString, schemaOptions } from './schemaUtils.js';

/**
 * Savings goal (contract §8 "SavingsGoal"). Money in integer minor units.
 * `savedMinor` changes only through atomic `$inc` (contributions / entry deletion),
 * which bypasses validators — the service clamps it at 0.
 */
const goalSchema = new mongoose.Schema(
  {
    familyId: requiredRef('Family'),
    title: requiredString(LIMITS.GOAL_TITLE_MAX),
    description: optionalString(LIMITS.GOAL_DESCRIPTION_MAX),
    targetMinor: minorUnits({ min: 1 }),
    savedMinor: minorUnits({ min: 0, max: Number.MAX_SAFE_INTEGER, default: 0 }),
    targetDate: { type: Date, default: null },
    status: { type: String, required: true, enum: GOAL_STATUSES, default: 'active' },
    createdById: requiredRef('Member'),
    achievedAt: { type: Date, default: null },
  },
  schemaOptions('goals'),
);

goalSchema.index({ familyId: 1, status: 1 });

/**
 * Fraction saved (contract `progress`, e.g. 0.2083): savedMinor / targetMinor,
 * truncated (not rounded, so 99.996 % never shows as 100 %) to 4 decimals, capped to [0, 1].
 */
goalSchema.virtual('progress').get(function progress() {
  if (!this.targetMinor || this.targetMinor <= 0) return 0;
  const ratio = Math.max(0, (this.savedMinor ?? 0) / this.targetMinor);
  return Math.min(1, Math.floor(ratio * 10000 + 1e-9) / 10000);
});

applyToJson(goalSchema);

export const Goal = defineModel('Goal', goalSchema);
export default Goal;
