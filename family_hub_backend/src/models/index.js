/**
 * Barrel for all Mongoose models (docs/04-DATA_MODELS.md).
 *
 *   import { User, Member, Task } from '../models/index.js';
 *   import { TASK_STATUSES, LEDGER_CATEGORIES } from '../models/index.js';
 *
 * Importing this module never touches the database. Every schema applies the shared
 * toJSON options itself — `applyToJson()` → `toJsonPlugin` (see schemaUtils.applyToJson
 * for why it is not registered as a global plugin here).
 */
import { EmergencyCard } from './EmergencyCard.js';
import { Device } from './Device.js';
import { Family } from './Family.js';
import { Goal } from './Goal.js';
import { LedgerEntry } from './LedgerEntry.js';
import { Member } from './Member.js';
import { Notice } from './Notice.js';
import { Otp } from './Otp.js';
import { RefreshToken } from './RefreshToken.js';
import { SosAlert } from './SosAlert.js';
import { Task } from './Task.js';
import { User } from './User.js';

export { User, RefreshToken, Otp, Family, Member, Device, Task, LedgerEntry, Goal, Notice, SosAlert, EmergencyCard };

export { ENCRYPTED_CARD_FIELDS } from './EmergencyCard.js';
export { DEVICE_STALE_AFTER_SECONDS } from './Device.js';
export { OTP_PURGE_GRACE_SECONDS } from './Otp.js';
export * from './enums.js';

/** All models keyed by name, e.g. for seeding, tests and index maintenance. */
export const models = Object.freeze({
  User,
  RefreshToken,
  Otp,
  Family,
  Member,
  Device,
  Task,
  LedgerEntry,
  Goal,
  Notice,
  SosAlert,
  EmergencyCard,
});

/**
 * Waits until every collection and index (unique, partial, TTL) exists. Call it after
 * `mongoose.connect()` in tests/seeds that rely on unique constraints, since index
 * builds triggered by autoIndex run in the background.
 */
export async function initModels() {
  await Promise.all(Object.values(models).map((model) => model.init()));
}

/**
 * Drops indexes that are no longer declared and builds the declared ones
 * (deploy/migration helper — do not call on every boot in production).
 * @returns {Promise<Record<string, string[]>>} dropped index names per model
 */
export async function syncAllIndexes() {
  const dropped = {};
  for (const [name, model] of Object.entries(models)) {
    dropped[name] = await model.syncIndexes();
  }
  return dropped;
}

export default models;
