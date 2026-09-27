import { toId } from '../lib/access.js';
import { DEFAULT_LOCALE, DEFAULT_LOCATION_SHARING, ROLE } from '../lib/constants.js';
import { toIso } from '../lib/dates.js';

/**
 * Response shapes for the shared objects of docs/03-API_CONTRACT.md §2 (User, Family, Member).
 * Accept Mongoose documents or lean objects. Never expose secrets (password/token/OTP hashes,
 * encrypted blobs); `inviteCode` only to admins; `lastLocation` only when sharing is `always`.
 *
 * The small helpers (`idOf`, `iso`, `serializeLocation`) are exported so module serializers
 * (tasks, ledger, notices, sos …) produce ids/dates the same way.
 */

/** Id of a doc / ObjectId / string as a hex string, or null. */
export const idOf = toId;

/** Date → ISO-8601 UTC string, or null. */
export const iso = toIso;

const orNull = (v) => (v === undefined || v === '' ? null : v);

/** `{ lat, lng, accuracy, recordedAt }` or null when no usable point. */
export function serializeLocation(loc) {
  if (!loc || typeof loc.lat !== 'number' || typeof loc.lng !== 'number') return null;
  return {
    lat: loc.lat,
    lng: loc.lng,
    accuracy: typeof loc.accuracy === 'number' ? loc.accuracy : null,
    recordedAt: iso(loc.recordedAt),
  };
}

/**
 * User (account). `role` comes from the user's Member (the User model has no role):
 * pass the member (or a role) when available — e.g. `serializeUser(user, member)`.
 * `req.user`-shaped objects (which carry `role`) also work.
 *
 * @param {object} user
 * @param {object|string|null} [memberOrRole] member doc/lean object, or 'admin'|'member'
 */
export function serializeUser(user, memberOrRole) {
  if (!user) return null;
  const familyId = idOf(user.familyId);
  let role = null;
  if (familyId) {
    if (typeof memberOrRole === 'string') role = memberOrRole;
    else if (memberOrRole && typeof memberOrRole === 'object') role = memberOrRole.role ?? null;
    else if (typeof user.role === 'string') role = user.role;
  }
  return {
    id: idOf(user),
    email: user.email,
    name: user.name,
    emailVerified: Boolean(user.emailVerified),
    locale: user.locale ?? DEFAULT_LOCALE,
    familyId,
    memberId: familyId ? idOf(user.memberId) : null,
    role,
    createdAt: iso(user.createdAt),
  };
}

/**
 * Family. `inviteCode` is only returned to admins (members get null).
 * @param {object} family
 * @param {{ isAdmin?: boolean, memberCount?: number }} [opts]
 */
export function serializeFamily(family, { isAdmin = false, memberCount } = {}) {
  if (!family) return null;
  const count = memberCount ?? family.memberCount;
  return {
    id: idOf(family),
    name: family.name,
    inviteCode: isAdmin ? (family.inviteCode ?? null) : null,
    country: family.country,
    currency: family.currency,
    timezone: family.timezone,
    ownerId: idOf(family.ownerId),
    memberCount: Number.isFinite(count) ? count : 0,
    createdAt: iso(family.createdAt),
  };
}

/** Member. `lastLocation` only when that member's `locationSharing` is `always`. */
export function serializeMember(member) {
  if (!member) return null;
  const locationSharing = member.locationSharing ?? DEFAULT_LOCATION_SHARING;
  const userId = idOf(member.userId);
  return {
    id: idOf(member),
    familyId: idOf(member.familyId),
    userId,
    name: member.name,
    email: orNull(member.email) ?? null,
    phone: orNull(member.phone) ?? null,
    avatarUrl: orNull(member.avatarUrl) ?? null,
    dateOfBirth: iso(member.dateOfBirth),
    gender: orNull(member.gender) ?? null,
    designation: orNull(member.designation) ?? null,
    role: member.role ?? ROLE.MEMBER,
    hasAccount: Boolean(userId),
    locationSharing,
    lastLocation: locationSharing === 'always' ? serializeLocation(member.lastLocation) : null,
    guardianConsent: Boolean(member.guardianConsent),
    createdAt: iso(member.createdAt),
    updatedAt: iso(member.updatedAt),
  };
}

const time = (d) => {
  if (d === null || d === undefined) return null;
  const n = new Date(d).getTime();
  return Number.isNaN(n) ? null : n;
};

/**
 * Contract order for member lists: admins first, then oldest → youngest (null DOB last),
 * ties by creation time then name. Returns a new array.
 */
export function sortMembers(list) {
  return [...(list ?? [])].sort((a, b) => {
    const ra = a.role === ROLE.ADMIN ? 0 : 1;
    const rb = b.role === ROLE.ADMIN ? 0 : 1;
    if (ra !== rb) return ra - rb;
    const da = time(a.dateOfBirth);
    const db = time(b.dateOfBirth);
    if (da !== db) {
      if (da === null) return 1;
      if (db === null) return -1;
      return da - db;
    }
    const ca = time(a.createdAt) ?? 0;
    const cb = time(b.createdAt) ?? 0;
    if (ca !== cb) return ca - cb;
    return String(a.name ?? '').localeCompare(String(b.name ?? ''));
  });
}

/**
 * Serializes a member list in contract order (see sortMembers).
 * @param {object[]} list
 * @param {{ sort?: boolean }} [opts] pass `{ sort: false }` to keep the input order
 */
export function serializeMembers(list, { sort = true } = {}) {
  const items = sort ? sortMembers(list) : [...(list ?? [])];
  return items.map(serializeMember);
}
