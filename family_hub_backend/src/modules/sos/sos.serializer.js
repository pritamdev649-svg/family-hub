import { DEFAULT_LOCATION_SHARING, SOS_TRAIL_MAX } from '../../lib/constants.js';
import { memberOf } from '../../services/memberDirectory.js';
import { idOf, iso, serializeLocation } from '../../services/serializers.js';

/**
 * Contract `SosAlert` shape (docs/03-API_CONTRACT.md §10). Accepts a Mongoose document or a lean
 * object. `memberName` / `memberPhone` / `memberAvatarUrl` come from the family's member map
 * (`services/memberDirectory.js#getMemberMap`) and are `null` when the member no longer exists
 * (alerts of a removed member stay in the history). `lastLocation` / `trail` follow the owner's
 * current sharing mode (`locationVisible`).
 *
 * Exported for other modules (e.g. the dashboard's `activeSos`) so every alert leaves the API identically.
 */

const LOCATION_NEVER = 'never';

const time = (value) => {
  const n = value ? new Date(value).getTime() : Number.NaN;
  return Number.isNaN(n) ? 0 : n;
};

/**
 * Lazy expiry without writing: an `active` alert past `expiresAt` is `expired` (same rule as
 * `SosAlert#effectiveStatus`, but also works on lean objects).
 */
export function sosStatusOf(alert, now = new Date()) {
  if (alert?.status === 'active' && alert.expiresAt && time(alert.expiresAt) <= now.getTime()) return 'expired';
  return alert?.status ?? null;
}

/** true while the alert accepts location updates and can be resolved. */
export function isSosActive(alert, now = new Date()) {
  return sosStatusOf(alert, now) === 'active';
}

/** Stored trail → at most the newest `SOS_TRAIL_MAX` points, oldest first. */
function serializeTrail(trail) {
  return (trail ?? [])
    .map(serializeLocation)
    .filter(Boolean)
    .map((point, index) => ({ point, index }))
    .sort((a, b) => time(a.point.recordedAt) - time(b.point.recordedAt) || a.index - b.index)
    .slice(-SOS_TRAIL_MAX)
    .map(({ point }) => point);
}

/**
 * Whether an alert's location may be shown (docs/02-ARCHITECTURE.md §5.1, docs/08-COMPLIANCE.md
 * "withdrawal of consent"):
 *   - an alert raised with sharing `never` (`locationShared: false`) never exposes a location;
 *   - the owner's **current** mode governs: after switching to `never` (consent withdrawn) the stored
 *     points of their alerts, active or ended, are hidden from everyone. Nothing is deleted, so
 *     switching back to `sos_only` / `always` shows them again (retention is GAP-03);
 *   - an owner who left / was removed (not in the map) shares nothing with the family any more.
 * Fails closed: a member entry without `locationSharing` counts as the default (`never`), so pass full
 * members (`getMemberMap`, or serialized members, both carry it).
 */
function locationVisible(alert, member) {
  return Boolean(alert.locationShared) && (member?.locationSharing ?? DEFAULT_LOCATION_SHARING) !== LOCATION_NEVER;
}

/**
 * @param {object} alert                 SosAlert doc / lean object
 * @param {Map<string, object>} members  memberId → member (from getMemberMap)
 * @param {{ withTrail?: boolean, now?: Date }} [opts] `withTrail` only for `GET /sos/:id`; lists send `trail: []`
 */
export function serializeSosAlert(alert, members, { withTrail = false, now = new Date() } = {}) {
  if (!alert) return null;
  const member = memberOf(members, alert.memberId);
  const shared = locationVisible(alert, member);
  return {
    id: idOf(alert),
    memberId: idOf(alert.memberId),
    memberName: member?.name ?? null,
    memberPhone: member?.phone || null,
    memberAvatarUrl: member?.avatarUrl || null,
    status: sosStatusOf(alert, now),
    message: alert.message || null,
    locationShared: shared,
    lastLocation: shared ? serializeLocation(alert.lastLocation) : null,
    trail: withTrail && shared ? serializeTrail(alert.trail) : [],
    startedAt: iso(alert.startedAt),
    expiresAt: iso(alert.expiresAt),
    resolvedAt: iso(alert.resolvedAt),
    resolvedById: idOf(alert.resolvedById),
    resolution: alert.resolution ?? null,
  };
}

/** Serializes a list with one shared member map (`trail: []`). */
export function serializeSosAlerts(list, members, { now = new Date() } = {}) {
  return (list ?? []).map((alert) => serializeSosAlert(alert, members, { now }));
}
