import { assertFamily, assertSelfOrAdmin, findInFamily, isObjectId } from '../../lib/access.js';
import { ApiError } from '../../lib/ApiError.js';
import { ENCRYPTED_CARD_FIELDS, EmergencyCard, Member } from '../../models/index.js';

/**
 * Emergency cards (docs/03-API_CONTRACT.md §6, `/family/members/:memberId/emergency-card`).
 *
 *   - Read: any member of the family may read any member's card (it is meant for emergencies).
 *   - Write: the member themself or a family admin (managed profiles are therefore admin-only).
 *   - A member id of another family (or unknown) → 404 NOT_FOUND, checked before the permission.
 *   - PUT replaces the whole card: fields missing from the body are reset to their empty value.
 *     The replacement is ONE atomic upsert that `$set`s every stored path. A read-modify-`save()`
 *     would only `$set` the paths that differ from the copy it read, so two racing PUTs could leave
 *     a mix of both, e.g. one request's blood group next to the other's allergies.
 *
 * Encryption at rest is done by the model: the plaintext virtuals `allergies`, `medications`,
 * `conditions`, `insurancePolicyNumber` and `notes` call `lib/crypto.js#encryptField` on set and
 * `decryptField` on get (models/EmergencyCard.js). The upsert's `$set` is taken from an unsaved
 * draft card, so the model's setters, encryption and validators run exactly as on `save()`.
 * A card that cannot be decrypted (wrong FIELD_ENCRYPTION_KEY / corrupted blob) fails loudly
 * with 500 rather than showing "no allergies".
 *
 * `actor` is `req.user` (`{ id, familyId, memberId, role }`), so the service stays HTTP-agnostic.
 */

/** Value stored for each editable field when a PUT body leaves it out (= contract empty card). */
const EMPTY_FIELDS = Object.freeze({
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
});

const EDITABLE_FIELDS = Object.freeze(Object.keys(EMPTY_FIELDS));

/** Stored paths a PUT replaces: editable fields (encrypted ones under their `*Enc` path) + the editor. */
const STORED_PATHS = Object.freeze([
  ...EDITABLE_FIELDS.map((name) => ENCRYPTED_CARD_FIELDS[name]?.path ?? name),
  'updatedById',
]);

/**
 * First PUTs racing on the unique `memberId` index: MongoDB retries such an upsert itself, and we
 * retry once more in case it does not, which then updates the card the winner created.
 */
const MAX_SAVE_ATTEMPTS = 2;

const asCtx = (actor) => ({ user: actor });

function isDuplicateKeyError(err) {
  return err?.code === 11000 || err?.cause?.code === 11000;
}

/** 404 unless `memberId` is a member of `familyId` (another family's id is never distinguishable). */
async function assertMemberInFamily(familyId, memberId) {
  await findInFamily(Member, memberId, familyId, { lean: true, select: '_id' });
}

function findCard(familyId, memberId) {
  return EmergencyCard.findOne({ familyId, memberId });
}

/** Full replacement set of editable fields (missing keys → empty value, arrays copied). */
function replacementFields(input) {
  const fields = {};
  for (const name of EDITABLE_FIELDS) {
    const value = input?.[name];
    const empty = EMPTY_FIELDS[name];
    if (value === undefined || value === null) fields[name] = Array.isArray(empty) ? [] : empty;
    else fields[name] = Array.isArray(value) ? [...value] : value;
  }
  fields.emergencyContacts = fields.emergencyContacts.map((c) => ({
    name: c.name,
    phone: c.phone ?? null,
    relation: c.relation ?? null,
  }));
  return fields;
}

/**
 * `$set` replacing every stored path, built on an unsaved draft card: the virtual setters encrypt
 * the sensitive fields (fresh IV per save), the schema setters / casts run, and `validate()` applies
 * the model backstops. A `ValidationError` becomes 422 in the error middleware.
 */
async function replacementSet(familyId, memberId, fields, updatedById) {
  const draft = new EmergencyCard({ familyId, memberId });
  for (const name of EDITABLE_FIELDS) draft.set(name, fields[name]);
  draft.set('updatedById', updatedById ?? null);
  await draft.validate();
  const stored = draft.toObject({ virtuals: false, getters: false, depopulate: true });
  return Object.fromEntries(STORED_PATHS.map((path) => [path, stored[path] ?? null]));
}

/**
 * Atomically replaces (or creates) the member's card. `updatedAt` is bumped on every call, even
 * when nothing else changed, because a PUT is an explicit save. Returns the hydrated card.
 */
async function writeCard(familyId, memberId, $set) {
  for (let attempt = 1; ; attempt += 1) {
    try {
      return await EmergencyCard.findOneAndUpdate(
        { familyId, memberId },
        { $set },
        { upsert: true, returnDocument: 'after', setDefaultsOnInsert: true },
      );
    } catch (err) {
      if (!isDuplicateKeyError(err) || attempt >= MAX_SAVE_ATTEMPTS) throw err;
    }
  }
}

/**
 * The member's card as plaintext, or the contract's empty card (`updatedAt: null`) when none is saved.
 * No access checks — for callers that already scoped `memberId` to `familyId` (e.g. `/me/export`).
 */
export async function plainCardFor(familyId, memberId) {
  if (!isObjectId(familyId) || !isObjectId(memberId)) throw ApiError.notFound();
  const card = await findCard(familyId, memberId);
  return card ? card.toPlainCard() : EmergencyCard.emptyCard(memberId);
}

/** GET — any member of the family. */
export async function getCard(actor, memberId) {
  assertFamily(asCtx(actor));
  const [, card] = await Promise.all([
    assertMemberInFamily(actor.familyId, memberId),
    findCard(actor.familyId, memberId),
  ]);
  return card ? card.toPlainCard() : EmergencyCard.emptyCard(memberId);
}

/** PUT — the member themself or an admin. Creates the card on first save. */
export async function saveCard(actor, memberId, input) {
  const ctx = asCtx(actor);
  assertFamily(ctx);
  await assertMemberInFamily(actor.familyId, memberId);
  assertSelfOrAdmin(ctx, memberId);

  const $set = await replacementSet(actor.familyId, memberId, replacementFields(input), actor.memberId);
  const card = await writeCard(actor.familyId, memberId, $set);

  // The member may have been removed while we were saving; the removal cascade deletes the card,
  // but a write landing just after it would leave orphaned health data behind. Undo it and 404.
  if (!(await Member.exists({ _id: memberId, familyId: actor.familyId }))) {
    await EmergencyCard.deleteOne({ _id: card._id });
    throw ApiError.notFound();
  }
  return card.toPlainCard();
}

/**
 * Deletes a member's card (member removal / account deletion cascades). Returns the number deleted.
 * Safe to call when no card exists.
 */
export async function deleteCardForMember(familyId, memberId) {
  if (!isObjectId(familyId) || !isObjectId(memberId)) return 0;
  const { deletedCount } = await EmergencyCard.deleteOne({ familyId, memberId });
  return deletedCount ?? 0;
}
