import { ApiError } from '../../lib/ApiError.js';
import { toId } from '../../lib/access.js';
import { ROLE } from '../../lib/constants.js';
import { Family, Member, User } from '../../models/index.js';
import { countMembers } from '../../services/memberDirectory.js';
import { serializeFamily } from '../../services/serializers.js';
import {
  createFamilyForUser,
  findMembership,
  joinFamilyForUser,
  planJoin,
  serializeSession,
} from '../auth/auth.onboarding.js';
import {
  guardianConsentError,
  loadFamily,
  needsGuardianConsent,
  rotateInviteCode,
  verifyEmailToLinkError,
} from './family.rules.js';

/**
 * The family itself (docs/03-API_CONTRACT.md §6): create, join, read, settings, invite code.
 * Members live in members.service.js.
 *
 * Create and join reuse the onboarding of `POST /auth/register` (auth.onboarding.js), so both
 * entry points apply the same rules: unique invite code, `409 ALREADY_IN_FAMILY` (a stale
 * membership counts as "no family"), linking a member an admin pre-added with the same e-mail,
 * the self-registration age gate and the `member_joined` push to the family's admins.
 *
 * `authUser` is `req.user` (`{ id, name, locale, familyId, memberId, role }`).
 * `inviteCode` is only ever serialised for admins.
 */

/** The caller's account (lean) — the onboarding helpers need the stored familyId/memberId/email. */
async function loadUser(authUser) {
  const user = await User.findById(authUser.id).lean();
  if (!user) throw ApiError.unauthorized();
  return user;
}

async function familyResponse(family, { isAdmin }) {
  const memberCount = await countMembers(family._id);
  return { family: serializeFamily(family, { isAdmin, memberCount }) };
}

// ---------------------------------------------------------------- create / join

/**
 * `POST /family`: an account without a family creates one and becomes its admin
 * ("Head of Family").
 * @returns {Promise<{ user: object, family: object, member: object }>}
 * @throws {ApiError} 409 ALREADY_IN_FAMILY
 */
export async function createFamily(authUser, input) {
  const user = await loadUser(authUser);
  return serializeSession(await createFamilyForUser(user, input));
}

/**
 * `POST /family/join`: an account without a family joins by invite code — as a new `member`, or
 * linked to the profile an admin pre-added with the same e-mail (keeping its name, role,
 * designation and guardian consent). The family's admins get a `member_joined` push.
 *
 * Linking takes over the pre-added profile — possibly an admin one — only because the e-mail
 * addresses match, and every member can read the family's e-mail addresses. So an account whose
 * address is **not verified** is not linked: `403 FORBIDDEN` (verify first, then join). Joining
 * as a new member needs no verification. Checked only for accounts without a family, so the error
 * order of `joinFamilyForUser` (409 ALREADY_IN_FAMILY first) stays the same.
 *
 * @returns {Promise<{ user: object, family: object, member: object }>}
 * @throws {ApiError} 409 ALREADY_IN_FAMILY · 400 INVALID_INVITE_CODE · 409 MEMBER_EMAIL_EXISTS ·
 *   422 GUARDIAN_CONSENT_REQUIRED (pre-added minor profile without consent) · 403 FORBIDDEN
 *   (unverified address would be linked)
 */
export async function joinFamily(authUser, { inviteCode }) {
  const user = await loadUser(authUser);
  if (!user.emailVerified && !(await findMembership(user))) {
    const { existing } = await planJoin({ inviteCode, email: user.email });
    if (existing) throw verifyEmailToLinkError();
  }
  return serializeSession(await joinFamilyForUser(user, inviteCode));
}

// ---------------------------------------------------------------- read / settings

/** `GET /family` → `{ family }`; `inviteCode` only for admins. */
export async function getFamily(authUser) {
  const family = await loadFamily(authUser.familyId);
  return familyResponse(family, { isAdmin: authUser.role === ROLE.ADMIN });
}

/**
 * Members who would need guardian consent under `settings` (GAP-05): known date of birth, below
 * the consent age of the new country, no consent recorded.
 * @returns {Promise<string[]>} member ids
 */
async function membersNeedingConsent(familyId, settings, now = new Date()) {
  const candidates = await Member.find({ familyId, dateOfBirth: { $ne: null }, guardianConsent: { $ne: true } })
    .select('_id dateOfBirth')
    .lean();
  return candidates
    .filter((m) => needsGuardianConsent({ dateOfBirth: m.dateOfBirth, family: settings, now }))
    .map((m) => toId(m._id));
}

/** `422 GUARDIAN_CONSENT_REQUIRED` for a country change (GAP-05), naming the members concerned. */
const countryConsentError = (country, memberIds) =>
  guardianConsentError({ country, field: 'country', memberIds, messageKey: 'family.errors.countryConsentRequired' });

/**
 * `PATCH /family` (admin) → `{ family }`. Only the fields that differ are written.
 *
 * A country change can lower who counts as an adult: when it would leave members below the new
 * country's consent age without recorded guardian consent, nothing is changed and the answer is
 * `422 GUARDIAN_CONSENT_REQUIRED` with `details.memberIds` (docs/08-COMPLIANCE.md GAP-05). The
 * admin confirms consent on those members first (`PATCH /family/members/:id { guardianConsent: true }`).
 *
 * Race-safe: the members are checked again **after** the write. A minor added (or given a date of
 * birth) under the old country at the same moment is found by one of the two requests — that
 * request re-reads the other's write — so the change is undone (only while the family still has
 * the values written here) and answered with the same 422.
 */
export async function updateFamily(authUser, body) {
  const family = await loadFamily(authUser.familyId);
  const set = {};
  for (const field of ['name', 'country', 'currency', 'timezone']) {
    if (body[field] !== undefined && body[field] !== family[field]) set[field] = body[field];
  }
  if (!Object.keys(set).length) return familyResponse(family, { isAdmin: true });

  const settings = { country: set.country ?? family.country, timezone: set.timezone ?? family.timezone };
  if (set.country) {
    const memberIds = await membersNeedingConsent(family._id, settings);
    if (memberIds.length) throw countryConsentError(set.country, memberIds);
  }

  const updated = await Family.findOneAndUpdate(
    { _id: family._id },
    { $set: set },
    { returnDocument: 'after', runValidators: true },
  ).lean();
  if (!updated) throw ApiError.noFamily();

  if (set.country) {
    const memberIds = await membersNeedingConsent(family._id, settings);
    if (memberIds.length) {
      const previous = Object.fromEntries(Object.keys(set).map((field) => [field, family[field]]));
      await Family.updateOne({ _id: family._id, ...set }, { $set: previous });
      throw countryConsentError(set.country, memberIds);
    }
  }
  return familyResponse(updated, { isAdmin: true });
}

// ---------------------------------------------------------------- invite code

/**
 * `POST /family/invite-code` (admin) → `{ family }` with a new code; the old one stops working at
 * once (see `rotateInviteCode`). A code another family already uses (unique index) is regenerated.
 * @param {object} authUser
 * @param {{ generateCode?: () => string }} [opts] `generateCode` for tests
 */
export async function regenerateInviteCode(authUser, { generateCode } = {}) {
  const family = await loadFamily(authUser.familyId);
  const updated = await rotateInviteCode(family._id, { currentCode: family.inviteCode, generateCode });
  return familyResponse(updated, { isAdmin: true });
}
