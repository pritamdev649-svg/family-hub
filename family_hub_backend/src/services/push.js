import fs from 'node:fs';
import path from 'node:path';
import { cert, getApps, initializeApp } from 'firebase-admin/app';
import { getMessaging } from 'firebase-admin/messaging';
import { env } from '../config/env.js';
import { isObjectId, toId } from '../lib/access.js';
import { DEFAULT_LOCALE, PUSH_BATCH_SIZE, PUSH_CHANNELS, PUSH_TYPE, SOS_DURATION_MS } from '../lib/constants.js';
import { isSupportedLocale, t } from '../lib/i18n.js';
import { logger } from '../lib/logger.js';
import { Device, Member, User } from '../models/index.js';

/**
 * Push notifications through Firebase Cloud Messaging (docs/03-API_CONTRACT.md §13).
 *
 * Credentials: FIREBASE_SERVICE_ACCOUNT_BASE64 (base64 of the service-account JSON) or
 * FIREBASE_SERVICE_ACCOUNT_PATH. Without credentials push is disabled (logged once) and
 * `sendToMembers` only resolves recipients.
 *
 * Tests: nothing is sent to FCM; every `sendToMembers` call is appended to the exported
 * `sentPushes` array **synchronously** (type/id/route/keys/vars), and its resolved recipients
 * (`memberIds`, `messages`) are filled in asynchronously — `await flushPushes()` before
 * asserting on them.
 */

const APP_NAME = 'familyhub-push';
const INVALID_TOKEN_CODES = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
]);

/** Test log of push intents (see file header). */
export const sentPushes = [];
const inFlight = new Set();

let messaging = null;
let initialised = false;

function loadServiceAccount() {
  if (env.FIREBASE_SERVICE_ACCOUNT_BASE64) {
    return JSON.parse(Buffer.from(env.FIREBASE_SERVICE_ACCOUNT_BASE64, 'base64').toString('utf8'));
  }
  if (env.FIREBASE_SERVICE_ACCOUNT_PATH) {
    const file = path.resolve(process.cwd(), env.FIREBASE_SERVICE_ACCOUNT_PATH);
    if (!fs.existsSync(file)) return null;
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  }
  return null;
}

/**
 * Initialises firebase-admin once. Never throws.
 * @returns {boolean} whether push is enabled
 */
export function initPush() {
  if (initialised) return Boolean(messaging);
  initialised = true;
  if (env.isTest) return false;
  try {
    const serviceAccount = loadServiceAccount();
    if (!serviceAccount) {
      logger.warn('Push notifications disabled: no Firebase service account configured');
      return false;
    }
    const app =
      getApps().find((a) => a.name === APP_NAME) ??
      initializeApp({ credential: cert(serviceAccount), projectId: serviceAccount.project_id }, APP_NAME);
    messaging = getMessaging(app);
    logger.info(`Push notifications enabled (project ${serviceAccount.project_id ?? 'unknown'})`);
    return true;
  } catch (err) {
    logger.error(`Push notifications disabled: invalid Firebase credentials (${err.message})`);
    messaging = null;
    return false;
  }
}

export function isPushEnabled() {
  return Boolean(messaging);
}

/** FCM `data` values must be strings; null/undefined entries are dropped. */
function stringifyData(data) {
  const out = {};
  for (const [k, v] of Object.entries(data)) {
    if (v === undefined || v === null) continue;
    out[k] = typeof v === 'string' ? v : typeof v === 'object' ? JSON.stringify(v) : String(v);
  }
  return out;
}

function chunk(list, size) {
  const out = [];
  for (let i = 0; i < list.length; i += size) out.push(list.slice(i, i + size));
  return out;
}

function buildMessage({ tokens, title, body, data, type, highPriority }) {
  const isSos = type === PUSH_TYPE.SOS;
  const urgent = isSos || highPriority;
  const ttlMs = isSos ? SOS_DURATION_MS : undefined;
  return {
    tokens,
    notification: { title, body },
    data,
    android: {
      priority: 'high',
      ...(ttlMs ? { ttl: ttlMs } : {}),
      notification: {
        channelId: isSos ? PUSH_CHANNELS.SOS : PUSH_CHANNELS.GENERAL,
        sound: 'default',
        ...(isSos ? { priority: 'max', defaultVibrateTimings: true } : {}),
      },
    },
    apns: {
      headers: {
        'apns-priority': urgent ? '10' : '5',
        'apns-push-type': 'alert',
        ...(ttlMs ? { 'apns-expiration': String(Math.floor((Date.now() + ttlMs) / 1000)) } : {}),
      },
      payload: {
        aps: {
          sound: 'default',
          ...(isSos ? { 'interruption-level': 'time-sensitive' } : {}),
        },
      },
    },
  };
}

async function resolveRecipients({ familyId, memberIds, excludeMemberIds }) {
  if (!isObjectId(familyId)) return { members: [], users: [], devices: [] };
  const exclude = new Set((excludeMemberIds ?? []).map(toId).filter(Boolean));
  const filter = { familyId, userId: { $ne: null } };
  if (Array.isArray(memberIds)) filter._id = { $in: memberIds.map(toId).filter(isObjectId) };
  const members = (await Member.find(filter).select('_id userId').lean()).filter(
    (m) => !exclude.has(String(m._id)),
  );
  if (!members.length) return { members: [], users: [], devices: [] };
  // Only users still linked to this family receive family notifications.
  const users = await User.find({ _id: { $in: members.map((m) => m.userId) }, familyId })
    .select('_id locale memberId')
    .lean();
  if (!users.length) return { members, users: [], devices: [] };
  const devices = await Device.find({ userId: { $in: users.map((u) => u._id) } })
    .select('token locale userId')
    .lean();
  return { members, users, devices };
}

async function deliver(record, { type, id, route, titleKey, bodyKey, vars, highPriority, familyId, memberIds, excludeMemberIds }) {
  const { members, users, devices } = await resolveRecipients({ familyId, memberIds, excludeMemberIds });
  const userLocale = new Map(users.map((u) => [String(u._id), u.locale]));
  const linkedUsers = new Set(users.map((u) => String(u._id)));
  record.memberIds = members.filter((m) => linkedUsers.has(String(m.userId))).map((m) => String(m._id));

  // Group tokens by locale: device locale → user locale → English.
  const byLocale = new Map();
  for (const d of devices) {
    const locale = [d.locale, userLocale.get(String(d.userId))].find(isSupportedLocale) ?? DEFAULT_LOCALE;
    if (!byLocale.has(locale)) byLocale.set(locale, []);
    byLocale.get(locale).push(d.token);
  }

  const data = stringifyData({ type, id, route });
  const summary = { recipients: record.memberIds.length, devices: devices.length, sent: 0, failed: 0, removed: 0 };
  const invalidTokens = [];

  for (const [locale, tokens] of byLocale) {
    const title = t(locale, titleKey, vars);
    const body = t(locale, bodyKey, vars);
    for (const batch of chunk(tokens, PUSH_BATCH_SIZE)) {
      if (env.isTest) {
        for (const token of batch) record.messages.push({ token, locale, title, body });
        summary.sent += batch.length;
        continue;
      }
      if (!messaging) continue;
      try {
        const res = await messaging.sendEachForMulticast(buildMessage({ tokens: batch, title, body, data, type, highPriority }));
        summary.sent += res.successCount;
        summary.failed += res.failureCount;
        res.responses.forEach((r, i) => {
          if (!r.success && INVALID_TOKEN_CODES.has(r.error?.code)) invalidTokens.push(batch[i]);
        });
      } catch (err) {
        summary.failed += batch.length;
        logger.error(`Push "${type}" batch failed: ${err?.code ?? ''} ${err?.message ?? err}`);
      }
    }
  }

  if (invalidTokens.length) {
    const res = await Device.deleteMany({ token: { $in: invalidTokens } });
    summary.removed = res.deletedCount ?? 0;
  }
  return summary;
}

/**
 * Sends a localized push to family members (per-device locale). Never throws.
 * Call fire-and-forget: `void sendToMembers({...})`.
 *
 * @param {object} p
 * @param {string} p.familyId
 * @param {string[]} [p.memberIds]        default: every member of the family with an account
 * @param {string[]} [p.excludeMemberIds] e.g. the actor
 * @param {string} p.type                 one of PUSH_TYPES
 * @param {string} p.id                   resource id (data.id)
 * @param {string} p.route                app deep link (data.route), e.g. `/tasks/<id>`
 * @param {string} p.titleKey             i18n key, e.g. `tasks.push.assigned.title`
 * @param {string} p.bodyKey              i18n key, e.g. `tasks.push.assigned.body`
 * @param {object} [p.vars]               placeholders for title/body
 * @param {boolean} [p.highPriority]      urgent delivery (always on for `sos`)
 * @returns {Promise<{ recipients: number, devices: number, sent: number, failed: number, removed: number }>}
 */
export function sendToMembers({
  familyId,
  memberIds,
  excludeMemberIds = [],
  type,
  id,
  route,
  titleKey,
  bodyKey,
  vars = {},
  highPriority = false,
} = {}) {
  const empty = { recipients: 0, devices: 0, sent: 0, failed: 0, removed: 0 };
  const record = {
    familyId: toId(familyId),
    type,
    id: toId(id),
    route,
    titleKey,
    bodyKey,
    vars,
    highPriority: Boolean(highPriority || type === PUSH_TYPE.SOS),
    channelId: type === PUSH_TYPE.SOS ? PUSH_CHANNELS.SOS : PUSH_CHANNELS.GENERAL,
    requestedMemberIds: Array.isArray(memberIds) ? memberIds.map(toId) : null,
    excludeMemberIds: (excludeMemberIds ?? []).map(toId),
    memberIds: [],
    messages: [],
    at: new Date(),
  };
  if (env.isTest) sentPushes.push(record);

  if (!familyId || !type || !titleKey || !bodyKey) {
    logger.warn(`sendToMembers called with missing arguments (type=${type})`);
    return Promise.resolve(empty);
  }
  if (!env.isTest && !messaging) return Promise.resolve(empty);

  const promise = deliver(record, {
    type,
    id: record.id,
    route,
    titleKey,
    bodyKey,
    vars,
    highPriority,
    familyId: record.familyId,
    memberIds,
    excludeMemberIds,
  })
    .catch((err) => {
      logger.error(`Push "${type}" failed: ${err?.message ?? err}`);
      return empty;
    })
    .finally(() => inFlight.delete(promise));
  inFlight.add(promise);
  return promise;
}

/** Resolves when every in-flight push has been processed (tests, graceful shutdown). */
export async function flushPushes() {
  while (inFlight.size) await Promise.allSettled([...inFlight]);
}
