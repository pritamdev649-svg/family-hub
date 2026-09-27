import { ApiError } from '../../lib/ApiError.js';
import { Device, Family, Member, Otp, SosAlert, User } from '../../models/index.js';
import { iso, serializeMember } from '../../services/serializers.js';
import { assertMaySelfRegister, serializeAccount } from '../auth/auth.onboarding.js';
import { CLEAR_LOCKOUT, assertNotLocked, failPasswordCheck, verifyPassword } from '../auth/auth.passwords.js';
import { endUserSessions, removeSelfFromFamily } from './memberCascade.js';

/**
 * Business rules of `/me/*` (docs/03-API_CONTRACT.md §5). `authUser` is `req.user`,
 * `member` is `req.member` (the caller's lean Member or null) — both set by `requireAuth`.
 */

const ALWAYS = 'always';

/** Keys of `PATCH /me` stored on the Member (all but `name`, which lives on both, and `locale`). */
const MEMBER_ONLY_FIELDS = Object.freeze(['phone', 'avatarUrl', 'locationSharing', 'gender', 'dateOfBirth']);

/** At most this many push devices per account; the least recently seen ones are dropped. */
export const MAX_DEVICES_PER_USER = 10;

export function locationSharingDisabledError() {
  return new ApiError(403, 'LOCATION_SHARING_DISABLED', 'Location sharing is not set to always');
}

const isDuplicateKey = (err) => err?.code === 11000 || err?.cause?.code === 11000;

// ---------------------------------------------------------------- PATCH /me

/**
 * Updates the account (`name`, `locale`) and the caller's member profile (`name`, `phone`,
 * `avatarUrl`, `locationSharing`, `gender`, `dateOfBirth`).
 *
 * - Member fields without a family → `403 NO_FAMILY` (name/locale alone work without one).
 * - Switching `locationSharing` away from `always` clears `lastLocation` (docs/08-COMPLIANCE.md GAP-04).
 * - A date of birth below the family country's consent age needs recorded guardian consent
 *   (GAP-05, same gate as registration) → `422 GUARDIAN_CONSENT_REQUIRED`.
 *
 * @returns {Promise<{ user: object, member: object|null }>}
 */
export async function updateMe(authUser, member, body) {
  const userSet = {};
  if (body.name !== undefined) userSet.name = body.name;
  if (body.locale !== undefined) userSet.locale = body.locale;

  const memberSet = {};
  for (const field of MEMBER_ONLY_FIELDS) if (body[field] !== undefined) memberSet[field] = body[field];
  if (!member && Object.keys(memberSet).length) throw ApiError.noFamily();
  if (member && body.name !== undefined) memberSet.name = body.name;
  if (memberSet.locationSharing && memberSet.locationSharing !== ALWAYS) memberSet.lastLocation = null;

  if (member && memberSet.dateOfBirth && !member.guardianConsent) {
    const family = await Family.findById(member.familyId).select('country timezone').lean();
    if (family) {
      assertMaySelfRegister({ dateOfBirth: memberSet.dateOfBirth, country: family.country, timeZone: family.timezone });
    }
  }

  // Member first: when the caller was removed meanwhile nothing is written at all.
  let updatedMember = member ?? null;
  if (member && Object.keys(memberSet).length) {
    updatedMember = await Member.findOneAndUpdate(
      { _id: member._id, familyId: member.familyId, userId: authUser.id },
      { $set: memberSet },
      { returnDocument: 'after', runValidators: true },
    ).lean();
    if (!updatedMember) throw ApiError.noFamily();
  }

  const user = Object.keys(userSet).length
    ? await User.findByIdAndUpdate(authUser.id, { $set: userSet }, { returnDocument: 'after', runValidators: true }).lean()
    : await User.findById(authUser.id).lean();
  if (!user) throw ApiError.unauthorized();

  return { user: serializeAccount(user, updatedMember), member: updatedMember ? serializeMember(updatedMember) : null };
}

// ---------------------------------------------------------------- PUT /me/location

/**
 * Stores the caller's current location — only while their sharing mode is `always`
 * (checked atomically with the write, so a concurrent switch to `never` always wins).
 * A caller whose membership ended after `requireAuth` ran (left / removed meanwhile) gets
 * `403 NO_FAMILY`, like every later request would, instead of LOCATION_SHARING_DISABLED.
 * @returns {Promise<{ recordedAt: string }>}
 */
export async function updateLocation(authUser, { lat, lng, accuracy }) {
  const recordedAt = new Date();
  const own = { _id: authUser.memberId, familyId: authUser.familyId, userId: authUser.id };
  const updated = await Member.findOneAndUpdate(
    { ...own, locationSharing: ALWAYS },
    { $set: { lastLocation: { lat, lng, accuracy: accuracy ?? null, recordedAt } } },
    { returnDocument: 'after', runValidators: true, projection: { _id: 1 } },
  ).lean();
  if (!updated) {
    if (!(await Member.exists(own))) throw ApiError.noFamily();
    throw locationSharingDisabledError();
  }
  return { recordedAt: iso(recordedAt) };
}

// ---------------------------------------------------------------- devices

/**
 * Upserts an FCM token for the caller. A token already registered by another account moves to
 * the caller (a phone changes hands / another person signs in). Only the newest
 * `MAX_DEVICES_PER_USER` devices of an account are kept.
 *
 * An account deleted while this request was in flight must not keep a device row (a push
 * token is personal data and would outlive the erasure): the row is removed again and the
 * caller gets `401 UNAUTHORIZED`, like every later request of that account.
 * @returns {Promise<{ registered: true }>}
 */
export async function registerDevice(authUser, { token, platform, locale }) {
  const set = { userId: authUser.id, platform, locale: locale ?? null, lastSeenAt: new Date() };
  const upsert = () => Device.updateOne({ token }, { $set: set }, { upsert: true, runValidators: true });
  try {
    await upsert();
  } catch (err) {
    // Two concurrent first registrations of the same token: the loser updates the winner's row.
    if (!isDuplicateKey(err)) throw err;
    await upsert();
  }
  if (!(await User.exists({ _id: authUser.id }))) {
    await Device.deleteMany({ userId: authUser.id });
    throw ApiError.unauthorized();
  }
  await pruneDevices(authUser.id);
  return { registered: true };
}

async function pruneDevices(userId) {
  const stale = await Device.find({ userId })
    .sort({ lastSeenAt: -1, _id: -1 })
    .skip(MAX_DEVICES_PER_USER)
    .select('_id')
    .lean();
  if (stale.length) await Device.deleteMany({ _id: { $in: stale.map((d) => d._id) }, userId });
}

/**
 * Forgets one of the caller's push tokens. Idempotent; a token of another account is left
 * untouched and the answer is the same (existence is never revealed).
 * @returns {Promise<null>}
 */
export async function unregisterDevice(authUser, token) {
  await Device.deleteOne({ token, userId: authUser.id });
  return null;
}

// ---------------------------------------------------------------- leave / delete

/**
 * The caller leaves their family (contract §5): same LAST_ADMIN rule and cascade as an admin
 * removing a member, the last member leaving deletes the family. The caller stays signed in.
 * @returns {Promise<{ user: object }>} the account without a family
 */
export async function leaveFamily(authUser, member) {
  if (!member) throw ApiError.noFamily();
  await removeSelfFromFamily({ member, endSessions: false });
  const user = await User.findById(authUser.id).lean();
  if (!user) throw ApiError.unauthorized();
  return { user: serializeAccount(user, null) };
}

/**
 * Deletes the caller's account after re-checking the password (right to erasure):
 * member + emergency card + pending tasks (cascade), devices, refresh tokens, OTPs and the user.
 * Only member → the whole family is deleted; last admin while others remain → `409 LAST_ADMIN`
 * (nothing is deleted). Wrong passwords count towards the login lockout (401, then 429).
 *
 * The caller's SOS alerts stay in the family's history (who raised an alert and when) but lose
 * their location points (`trail`, `lastLocation`): precise location is the most sensitive data
 * the account leaves behind (docs/08-COMPLIANCE.md, erasure + GAP-03).
 *
 * Sessions and devices are swept once more after the user row is gone, which removes rows a
 * concurrent sign-in or device registration wrote meanwhile (`registerDevice` cleans up after
 * itself when it lands later; a refresh token inserted later is useless — rotation rejects a
 * missing user — and expires by TTL).
 * @returns {Promise<null>}
 */
export async function deleteAccount(authUser, member, { password }) {
  const user = await User.findById(authUser.id).select('_id email passwordHash lockUntil failedLoginCount').lean();
  if (!user) throw ApiError.unauthorized();
  assertNotLocked(user);
  if (!(await verifyPassword(password, user.passwordHash))) await failPasswordCheck(user._id);
  // The right password ends a failure streak (matters when the request then stops at LAST_ADMIN).
  if (user.failedLoginCount) await User.updateOne({ _id: user._id }, { $set: CLEAR_LOCKOUT });

  if (member) {
    await removeSelfFromFamily({ member, endSessions: false });
    await SosAlert.updateMany(
      { familyId: member.familyId, memberId: member._id },
      { $set: { trail: [], lastLocation: null, lastLocationAt: null } },
    );
  }

  await endUserSessions(user._id);
  await Otp.deleteMany({ $or: [{ userId: user._id }, { email: user.email }] });
  await User.deleteOne({ _id: user._id });
  await endUserSessions(user._id);
  return null;
}
