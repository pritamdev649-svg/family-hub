import { findInFamily, isAdmin, isObjectId, sameId, toId } from '../../lib/access.js';
import { ApiError } from '../../lib/ApiError.js';
import {
  PUSH_ROUTES,
  PUSH_TYPE,
  SOS_DURATION_MS,
  SOS_MIN_LOCATION_INTERVAL_MS,
  SOS_RESOLUTIONS,
  SOS_TRAIL_MAX,
} from '../../lib/constants.js';
import { logger } from '../../lib/logger.js';
import { paginate } from '../../lib/pagination.js';
import { Member, SosAlert } from '../../models/index.js';
import { getMemberMap, memberOf, nameOf } from '../../services/memberDirectory.js';
import { sendToMembers } from '../../services/push.js';
import { isSosActive, serializeSosAlert, serializeSosAlerts } from './sos.serializer.js';

/**
 * SOS alerts with a live-location window (docs/03-API_CONTRACT.md §10, docs/02-ARCHITECTURE.md §5).
 * FamilyHub alerts **family members only** — it never contacts emergency services.
 *
 *   create        any member; idempotent while the caller has an active alert (→ `created: false`)
 *   active        active alerts of the family (the caller's own included), newest first
 *   history       resolved / expired alerts, newest first, paginated
 *   get           one alert incl. its trail (≤ 100 newest points, oldest first)
 *   location      the alert's owner only; 3 s store throttle; `$push` + `$slice: -100`
 *   resolve       the owner or an admin; idempotent on an already resolved alert
 *
 * Check order inside a write: 404 (not in the caller's family) → 403 FORBIDDEN (role) →
 * 409 SOS_NOT_ACTIVE (resolved / expired) → 403 LOCATION_SHARING_DISABLED (location only).
 *
 * Lazy expiry: every endpoint first persists `active` → `expired` for the family's alerts past
 * `expiresAt` (`SosAlert.expireStale`, one indexed `updateMany`), and every response computes the
 * status again, so an alert that expires between the two is still reported as `expired`.
 *
 * Location privacy (contract §10, docs/02-ARCHITECTURE.md §5.1): the owner's **current**
 * `locationSharing` decides. `never` → an alert is created with `locationShared: false` and no
 * location, and later location updates get `403 LOCATION_SHARING_DISABLED`. `sos_only` / `always` →
 * `locationShared: true`. Location points are timestamped with server time. Reads follow the same
 * rule: while the owner's current mode is `never`, no response shows the locations of their alerts
 * (`sos.serializer.js#locationVisible`, consent withdrawn; nothing is deleted).
 *
 * Pushes (fire-and-forget, route `/sos/alert/<id>`): `sos` (high priority, channel `sos_alerts`) to
 * every other member with an account when an alert is created — never on an idempotent repeat;
 * `sos_resolved` to everyone but the resolver on the active → resolved transition. Push texts carry
 * names only: the free-text `message` may hold health details and lock screens are visible to
 * others (docs/08-COMPLIANCE.md §3 row 20), so it is shown in the app, not in the notification.
 *
 * `actor` is `req.user` (`{ id, name, familyId, memberId, role }`) so the service stays HTTP-agnostic.
 */

const ACTIVE = 'active';
const RESOLVED = 'resolved';
const EXPIRED = 'expired';
const LOCATION_NEVER = 'never';
const HISTORY_STATUSES = Object.freeze([RESOLVED, EXPIRED]);
/** Lists and write responses never carry the trail (contract: only `GET /sos/:id`). */
const WITHOUT_TRAIL = '-trail';
/** Newest first; `_id` keeps the order stable for alerts started in the same millisecond. */
const NEWEST_FIRST = Object.freeze({ startedAt: -1, _id: -1 });
/** Upsert attempts for `POST /sos` when a duplicate key reports a concurrent create. */
const MAX_CREATE_ATTEMPTS = 2;

const asCtx = (actor) => ({ user: actor });

const isDuplicateKey = (err) => err?.code === 11000 || err?.cause?.code === 11000;

// ---------------------------------------------------------------- errors

function notActiveError() {
  return ApiError.conflict('SOS_NOT_ACTIVE', 'This SOS alert is no longer active', {
    messageKey: 'sos.errors.notActive',
  });
}

function locationSharingDisabledError() {
  return new ApiError(403, 'LOCATION_SHARING_DISABLED', 'Location sharing is set to never', {
    messageKey: 'sos.errors.locationSharingDisabled',
  });
}

function notOwnerError() {
  return ApiError.forbidden('Only the member who raised this SOS can share its location', {
    messageKey: 'sos.errors.notOwner',
  });
}

function resolveNotAllowedError() {
  return ApiError.forbidden('Only the member who raised this SOS or an admin can resolve it', {
    messageKey: 'sos.errors.resolveNotAllowed',
  });
}

// ---------------------------------------------------------------- helpers

/**
 * Persists the lazy expiry for a family (`active` + `expiresAt ≤ now` → `expired`).
 * Exported for other readers of SOS data (e.g. the dashboard's `activeSos`).
 * @returns {Promise<number>} number of alerts expired
 */
export function expireStaleAlerts(familyId, now = new Date()) {
  if (!isObjectId(familyId)) return Promise.resolve(0);
  return SosAlert.expireStale({ familyId }, now);
}

/** Filter for alerts that are still active at `now`. */
function activeFilter(familyId, extra = {}, now = new Date()) {
  return { familyId, status: ACTIVE, expiresAt: { $gt: now }, ...extra };
}

function sharingModeOf(member) {
  return member?.locationSharing ?? LOCATION_NEVER;
}

function locationPoint({ lat, lng, accuracy }, recordedAt) {
  return { lat, lng, accuracy: accuracy ?? null, recordedAt };
}

/** The caller's active alert (oldest first when a race left several), without trail. */
function findActiveOf(familyId, memberId, now) {
  return SosAlert.findOne(activeFilter(familyId, { memberId }, now)).sort({ _id: 1 }).select(WITHOUT_TRAIL).lean();
}

function findAlert(familyId, id) {
  return SosAlert.findOne({ _id: id, familyId }).select(WITHOUT_TRAIL).lean();
}

/** Loads an alert of the caller's family (without trail) or 404. */
function loadAlert(actor, id) {
  return findInFamily(SosAlert, id, actor.familyId, { lean: true, select: WITHOUT_TRAIL });
}

/**
 * Upserts the caller's active alert. The server assigns `_id` on insert (Mongoose leaves `_id` out
 * of upserts), so ids follow insert order — `settleCreateRace` relies on that.
 * @returns {Promise<{ alert: object, inserted: boolean }>}
 */
async function upsertActiveAlert({ familyId, memberId, message, locationShared, point, now }) {
  const result = await SosAlert.findOneAndUpdate(
    activeFilter(familyId, { memberId }, now),
    {
      $setOnInsert: {
        message: message ?? null,
        locationShared,
        lastLocation: point,
        trail: point ? [point] : [],
        lastLocationAt: point ? now : null,
        startedAt: now,
        expiresAt: new Date(now.getTime() + SOS_DURATION_MS),
        resolvedAt: null,
        resolvedById: null,
        resolution: null,
        createdAt: now,
        updatedAt: now,
      },
    },
    {
      upsert: true,
      // Several active alerts can only exist after a race; always answer with the oldest.
      sort: { _id: 1 },
      returnDocument: 'after',
      includeResultMetadata: true,
      projection: WITHOUT_TRAIL,
      lean: true,
      runValidators: true,
      // A matched (existing) alert must stay untouched: no automatic `updatedAt` bump.
      timestamps: false,
    },
  );
  return { alert: result.value, inserted: result.lastErrorObject?.updatedExisting === false };
}

/**
 * Without a unique index two concurrent creates can both insert. The oldest active alert (smallest
 * server-assigned `_id`) wins; a newer duplicate deletes itself and reports the winner instead.
 * Also undoes the insert when the caller was removed from the family meanwhile (the removal cascade
 * resolves active alerts, so one landing just after it would otherwise stay active).
 * @returns {Promise<object|null>} the winner when `alert` lost, else null
 */
async function settleCreateRace(alert, { familyId, memberId, now }) {
  const [oldest, stillMember] = await Promise.all([
    findActiveOf(familyId, memberId, now),
    Member.exists({ _id: memberId, familyId }),
  ]);
  if (!stillMember) {
    await SosAlert.deleteOne({ _id: alert._id, familyId });
    throw ApiError.noFamily();
  }
  if (oldest && !sameId(oldest._id, alert._id)) {
    await SosAlert.deleteOne({ _id: alert._id, familyId, memberId });
    return oldest;
  }
  return null;
}

// ---------------------------------------------------------------- pushes

/** `sos` push (high priority) to every other member with an account. */
function notifyAlert({ familyId, alert, ownerName }) {
  const id = toId(alert);
  void sendToMembers({
    familyId,
    excludeMemberIds: [toId(alert.memberId)],
    type: PUSH_TYPE.SOS,
    id,
    route: PUSH_ROUTES.sosAlert(id),
    titleKey: 'sos.push.alert.title',
    bodyKey: alert.locationShared ? 'sos.push.alert.body' : 'sos.push.alert.bodyNoLocation',
    vars: { name: ownerName ?? '' },
    highPriority: true,
  });
}

/**
 * `sos_resolved` push to everyone but the resolver. Exported so other flows that end an alert
 * (e.g. the member-removal cascade, which stores `resolution: null`) can tell the family too.
 *
 * @param {object} p
 * @param {string} p.familyId
 * @param {string} p.alertId
 * @param {string} p.ownerMemberId        member who raised the alert
 * @param {string|null} [p.resolverMemberId] who ended it (excluded from the push)
 * @param {string|null} [p.resolution]    `safe | false_alarm | helped`, or null ("closed")
 * @param {Map<string, object>} [p.members] member map (saves a query when the caller has it)
 */
export async function notifySosResolved({ familyId, alertId, ownerMemberId, resolverMemberId = null, resolution = null, members }) {
  let map = members;
  if (!map) {
    try {
      map = await getMemberMap(familyId);
    } catch (err) {
      // Never throws (callers fire and forget); the push goes out without names.
      logger.error(`sos_resolved push: member lookup failed (${err?.message ?? err})`);
      map = new Map();
    }
  }
  const variant = SOS_RESOLUTIONS.includes(resolution) ? resolution : 'closed';
  const byOwner = !resolverMemberId || sameId(resolverMemberId, ownerMemberId);
  const id = toId(alertId);
  void sendToMembers({
    familyId,
    excludeMemberIds: resolverMemberId ? [toId(resolverMemberId)] : [],
    type: PUSH_TYPE.SOS_RESOLVED,
    id,
    route: PUSH_ROUTES.sosAlert(id),
    titleKey: 'sos.push.resolved.title',
    bodyKey: `sos.push.resolved.${byOwner ? 'body' : 'bodyByOther'}.${variant}`,
    vars: { name: nameOf(map, ownerMemberId) ?? '', resolver: nameOf(map, resolverMemberId) ?? '' },
    // Worried relatives should learn quickly that the emergency is over.
    highPriority: true,
  });
}

// ---------------------------------------------------------------- queries

/**
 * Member map for serializing `alerts`, loaded **after** them: every owner who existed when an alert
 * was read is in the map (a member who joined and raised an SOS between two parallel queries would
 * otherwise show `memberName: null` and, by the fail-closed location rule, no location). Nothing to
 * serialize → no query.
 */
function membersFor(familyId, alerts) {
  return alerts.length ? getMemberMap(familyId) : Promise.resolve(new Map());
}

/**
 * Active alerts of a family, newest first, serialized (`trail: []`). Runs the lazy expiry first.
 * Exported for the dashboard (`activeSos`); pass `members` (full members, see
 * `sos.serializer.js#locationVisible`) when you already loaded the map.
 */
export async function activeAlertsForFamily(familyId, { members, now = new Date() } = {}) {
  if (!isObjectId(familyId)) return [];
  await expireStaleAlerts(familyId, now);
  const alerts = await SosAlert.find(activeFilter(familyId, {}, now)).sort(NEWEST_FIRST).select(WITHOUT_TRAIL).lean();
  const map = members ?? (await membersFor(familyId, alerts));
  return serializeSosAlerts(alerts, map, { now });
}

/** `GET /sos/active`. */
export function listActive(actor) {
  return activeAlertsForFamily(actor.familyId);
}

/** `GET /sos/history` — resolved / expired alerts, newest first. */
export async function listHistory(actor, { page, limit } = {}) {
  const now = new Date();
  await expireStaleAlerts(actor.familyId, now);
  const result = await paginate(
    SosAlert,
    { familyId: actor.familyId, status: { $in: HISTORY_STATUSES } },
    { page, limit, sort: NEWEST_FIRST, projection: WITHOUT_TRAIL, lean: true },
  );
  const members = await membersFor(actor.familyId, result.items);
  return { ...result, items: serializeSosAlerts(result.items, members, { now }) };
}

/** `GET /sos/:id` — includes the trail. */
export async function getAlert(actor, id) {
  const now = new Date();
  await expireStaleAlerts(actor.familyId, now);
  const alert = await findInFamily(SosAlert, id, actor.familyId, { lean: true });
  const members = await getMemberMap(actor.familyId);
  return serializeSosAlert(alert, members, { withTrail: true, now });
}

// ---------------------------------------------------------------- writes

/**
 * `POST /sos`. Returns the caller's already active alert (`created: false` → 200, unchanged, no
 * push) or a new one (`created: true` → 201). The location is dropped when the caller's sharing
 * mode is `never`. The "find active or insert" step is a single upsert.
 * @returns {Promise<{ alert: object, created: boolean }>}
 */
export async function createAlert(actor, { location = null, message = null } = {}) {
  const now = new Date();
  const { familyId, memberId } = actor;
  await expireStaleAlerts(familyId, now);
  const members = await getMemberMap(familyId);
  const me = memberOf(members, memberId);
  // Removed from the family after authentication.
  if (!me) throw ApiError.noFamily();
  const done = (alert, created) => ({ alert: serializeSosAlert(alert, members, { now }), created });

  const locationShared = sharingModeOf(me) !== LOCATION_NEVER;
  const point = locationShared && location ? locationPoint(location, now) : null;

  let upserted;
  for (let attempt = 1; ; attempt += 1) {
    try {
      upserted = await upsertActiveAlert({ familyId, memberId, message, locationShared, point, now });
      break;
    } catch (err) {
      // With a (future) partial unique index on active alerts, a lost race is a duplicate key:
      // answer with the winner, or retry once when the winner already ended meanwhile.
      if (!isDuplicateKey(err) || attempt >= MAX_CREATE_ATTEMPTS) throw err;
      const winner = await findActiveOf(familyId, memberId, now);
      if (winner) return done(winner, false);
    }
  }
  if (!upserted.inserted) return done(upserted.alert, false);

  const winner = await settleCreateRace(upserted.alert, { familyId, memberId, now });
  if (winner) return done(winner, false);

  notifyAlert({ familyId, alert: upserted.alert, ownerName: me.name ?? actor.name });
  return done(upserted.alert, true);
}

/**
 * `POST /sos/:id/location` — owner only. Stored when at least `SOS_MIN_LOCATION_INTERVAL_MS` passed
 * since the last stored point; sooner updates are accepted but not stored (the current alert is
 * returned). The throttle, the active check and the append are one atomic update, so concurrent
 * updates can never store two points within the window or write to an ended alert.
 */
export async function updateLocation(actor, id, { lat, lng, accuracy }) {
  const now = new Date();
  await expireStaleAlerts(actor.familyId, now);
  const alert = await loadAlert(actor, id);
  if (!sameId(alert.memberId, actor.memberId)) throw notOwnerError();
  if (!isSosActive(alert, now)) throw notActiveError();

  const members = await getMemberMap(actor.familyId);
  if (sharingModeOf(memberOf(members, actor.memberId)) === LOCATION_NEVER) throw locationSharingDisabledError();

  const point = locationPoint({ lat, lng, accuracy }, now);
  const throttleEdge = new Date(now.getTime() - SOS_MIN_LOCATION_INTERVAL_MS);
  const updated = await SosAlert.findOneAndUpdate(
    {
      ...activeFilter(actor.familyId, { _id: alert._id, memberId: actor.memberId }, now),
      $or: [{ lastLocationAt: null }, { lastLocationAt: { $lte: throttleEdge } }],
    },
    {
      // Sharing may have been switched from `never` to `sos_only` / `always` during the alert.
      $set: { lastLocation: point, lastLocationAt: now, locationShared: true },
      $push: { trail: { $each: [point], $slice: -SOS_TRAIL_MAX } },
    },
    { returnDocument: 'after', projection: WITHOUT_TRAIL, lean: true, runValidators: true },
  );
  if (updated) return serializeSosAlert(updated, members, { now });

  // Not stored: throttled — or the alert ended / expired in the meantime.
  const current = await findAlert(actor.familyId, alert._id);
  if (!current) throw ApiError.notFound();
  if (!isSosActive(current, now)) throw notActiveError();
  return serializeSosAlert(current, members, { now });
}

/**
 * `POST /sos/:id/resolve` — the owner or an admin. Idempotent: an already resolved alert is
 * returned unchanged (the first resolution wins, no second push). Expired → 409 SOS_NOT_ACTIVE.
 */
export async function resolveAlert(actor, id, { resolution }) {
  const now = new Date();
  await expireStaleAlerts(actor.familyId, now);
  const alert = await loadAlert(actor, id);
  if (!sameId(alert.memberId, actor.memberId) && !isAdmin(asCtx(actor))) throw resolveNotAllowedError();

  const members = await getMemberMap(actor.familyId);
  if (alert.status === RESOLVED) return serializeSosAlert(alert, members, { now });
  if (!isSosActive(alert, now)) throw notActiveError();

  const updated = await SosAlert.findOneAndUpdate(
    activeFilter(actor.familyId, { _id: alert._id }, now),
    { $set: { status: RESOLVED, resolvedAt: now, resolvedById: actor.memberId, resolution } },
    { returnDocument: 'after', projection: WITHOUT_TRAIL, lean: true, runValidators: true },
  );
  if (updated) {
    void notifySosResolved({
      familyId: actor.familyId,
      alertId: updated._id,
      ownerMemberId: updated.memberId,
      resolverMemberId: actor.memberId,
      resolution,
      members,
    });
    return serializeSosAlert(updated, members, { now });
  }

  // Lost a race: resolved by someone else (idempotent) or it expired just now.
  const current = await findAlert(actor.familyId, alert._id);
  if (!current) throw ApiError.notFound();
  if (current.status === RESOLVED) return serializeSosAlert(current, members, { now });
  await SosAlert.expireStale({ familyId: actor.familyId, _id: current._id }, now);
  throw notActiveError();
}
