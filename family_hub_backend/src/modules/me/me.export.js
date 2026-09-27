import { ApiError } from '../../lib/ApiError.js';
import { fromMinor } from '../../lib/money.js';
import { Device, EmergencyCard, Family, LedgerEntry, Notice, RefreshToken, SosAlert, Task, User } from '../../models/index.js';
import { countMembers, getMemberMap, nameOf } from '../../services/memberDirectory.js';
import { idOf, iso, serializeFamily, serializeLocation, serializeMember } from '../../services/serializers.js';
import { findMembership, serializeAccount } from '../auth/auth.onboarding.js';

/**
 * `GET /me/export` — the caller's personal data as one JSON document (right of access /
 * portability: DPDP, GDPR Arts. 15 + 20; docs/08-COMPLIANCE.md row 7).
 *
 * Contents (contract §5): account, member profile, tasks (assigned to / created by / completed
 * by the caller), ledger entries they own or created, notices they authored, their emergency card
 * (decrypted) and their SOS alerts (with location trail). Also included because they are personal
 * data held about the account: push devices (token masked) and sign-in sessions (IP / user agent).
 *
 * Never included: password / token / OTP hashes, encrypted blobs and the family invite code
 * (a join credential — the export file is meant to be shared/saved outside the app).
 * Shapes follow the contract objects; people references are Member ids with resolved names.
 */

export const EXPORT_FORMAT_VERSION = 1;

/** Last characters of a push token — enough to recognise a device, useless to anyone else. */
const TOKEN_SUFFIX_LENGTH = 6;

const orNull = (v) => (v === undefined || v === '' ? null : v);

function exportAccount(user, member) {
  return {
    ...serializeAccount(user, member),
    updatedAt: iso(user.updatedAt),
    lastLoginAt: iso(user.lastLoginAt),
    consentAcceptedAt: iso(user.consentAcceptedAt),
  };
}

function exportMember(member) {
  return {
    ...serializeMember(member),
    // The caller's own stored location is theirs to see, whatever the sharing mode.
    lastLocation: serializeLocation(member.lastLocation),
    guardianConsentAt: iso(member.guardianConsentAt),
  };
}

function exportTask(task, names) {
  return {
    id: idOf(task),
    title: task.title,
    description: orNull(task.description) ?? null,
    assigneeId: idOf(task.assigneeId),
    assigneeName: nameOf(names, task.assigneeId),
    createdById: idOf(task.createdById),
    createdByName: nameOf(names, task.createdById),
    dueDate: iso(task.dueDate),
    category: task.category,
    priority: task.priority,
    status: task.status,
    completedAt: iso(task.completedAt),
    completedById: idOf(task.completedById),
    createdAt: iso(task.createdAt),
    updatedAt: iso(task.updatedAt),
  };
}

function exportLedgerEntry(entry) {
  return {
    id: idOf(entry),
    type: entry.type,
    amount: fromMinor(entry.amountMinor),
    category: entry.category,
    note: orNull(entry.note) ?? null,
    date: iso(entry.date),
    memberId: idOf(entry.memberId),
    memberName: entry.memberName,
    createdById: idOf(entry.createdById),
    goalId: idOf(entry.goalId),
    createdAt: iso(entry.createdAt),
  };
}

function exportNotice(notice, names) {
  return {
    id: idOf(notice),
    title: notice.title,
    body: notice.body,
    imageUrl: orNull(notice.imageUrl) ?? null,
    pinned: Boolean(notice.pinned),
    authorId: idOf(notice.authorId),
    authorName: nameOf(names, notice.authorId),
    createdAt: iso(notice.createdAt),
    updatedAt: iso(notice.updatedAt),
  };
}

/** Lazy SOS expiry (contract §10) without writing: an `active` alert past `expiresAt` is `expired`. */
function sosStatus(alert, now) {
  if (alert.status === 'active' && alert.expiresAt && new Date(alert.expiresAt).getTime() <= now.getTime()) return 'expired';
  return alert.status;
}

function exportSosAlert(alert, names, now) {
  return {
    id: idOf(alert),
    memberId: idOf(alert.memberId),
    memberName: nameOf(names, alert.memberId),
    status: sosStatus(alert, now),
    message: orNull(alert.message) ?? null,
    locationShared: Boolean(alert.locationShared),
    lastLocation: serializeLocation(alert.lastLocation),
    trail: (alert.trail ?? []).map(serializeLocation).filter(Boolean),
    startedAt: iso(alert.startedAt),
    expiresAt: iso(alert.expiresAt),
    resolvedAt: iso(alert.resolvedAt),
    resolvedById: idOf(alert.resolvedById),
    resolution: alert.resolution ?? null,
  };
}

function exportDevice(device) {
  const token = String(device.token ?? '');
  return {
    platform: device.platform,
    locale: device.locale ?? null,
    tokenSuffix: token.slice(-TOKEN_SUFFIX_LENGTH),
    createdAt: iso(device.createdAt),
    lastSeenAt: iso(device.lastSeenAt),
  };
}

function exportSession(row, now) {
  return {
    createdAt: iso(row.createdAt),
    expiresAt: iso(row.expiresAt),
    revokedAt: iso(row.revokedAt),
    active: !row.revokedAt && new Date(row.expiresAt).getTime() > now.getTime(),
    ip: row.ip ?? null,
    userAgent: row.userAgent ?? null,
  };
}

/**
 * Family-scoped personal data of a member. Families are small, so plain finds are fine;
 * an export is rare and must be complete (no pagination).
 */
async function loadFamilyData(member, now) {
  const familyId = member.familyId;
  const memberId = member._id;
  const [names, tasks, entries, notices, alerts, card] = await Promise.all([
    getMemberMap(familyId),
    Task.find({ familyId, $or: [{ assigneeId: memberId }, { createdById: memberId }, { completedById: memberId }] })
      .sort({ createdAt: 1, _id: 1 })
      .lean(),
    LedgerEntry.find({ familyId, $or: [{ memberId }, { createdById: memberId }] })
      .sort({ date: 1, _id: 1 })
      .lean(),
    Notice.find({ familyId, authorId: memberId }).sort({ createdAt: 1, _id: 1 }).lean(),
    SosAlert.find({ familyId, memberId }).sort({ startedAt: 1, _id: 1 }).lean(),
    // Hydrated (not lean): the plaintext virtuals decrypt the health fields.
    EmergencyCard.findOne({ familyId, memberId }),
  ]);
  return {
    emergencyCard: card ? card.toPlainCard() : null,
    tasks: tasks.map((t) => exportTask(t, names)),
    ledgerEntries: entries.map(exportLedgerEntry),
    notices: notices.map((n) => exportNotice(n, names)),
    sosAlerts: alerts.map((a) => exportSosAlert(a, names, now)),
  };
}

/**
 * Builds the export for the signed-in user. Works without a family (account data only).
 * @param {{ id: string }} authUser `req.user`
 */
export async function buildExport(authUser) {
  const now = new Date();
  const user = await User.findById(authUser.id).lean();
  if (!user) throw ApiError.unauthorized();

  const member = await findMembership(user);
  const family = member ? await Family.findById(member.familyId).lean() : null;
  const linked = Boolean(member && family);

  const [devices, sessions, familyData, memberCount] = await Promise.all([
    Device.find({ userId: user._id }).sort({ createdAt: 1, _id: 1 }).lean(),
    RefreshToken.find({ userId: user._id }).sort({ createdAt: 1, _id: 1 }).lean(),
    linked ? loadFamilyData(member, now) : null,
    linked ? countMembers(family._id) : 0,
  ]);

  return {
    formatVersion: EXPORT_FORMAT_VERSION,
    exportedAt: now.toISOString(),
    user: exportAccount(user, linked ? member : null),
    member: linked ? exportMember(member) : null,
    family: linked ? serializeFamily(family, { isAdmin: false, memberCount }) : null,
    currency: linked ? family.currency : null,
    emergencyCard: familyData?.emergencyCard ?? null,
    tasks: familyData?.tasks ?? [],
    ledgerEntries: familyData?.ledgerEntries ?? [],
    notices: familyData?.notices ?? [],
    sosAlerts: familyData?.sosAlerts ?? [],
    devices: devices.map(exportDevice),
    sessions: sessions.map((s) => exportSession(s, now)),
  };
}
