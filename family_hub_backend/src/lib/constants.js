/**
 * Every enum / tunable used by the API in one place (docs/06-BACKEND_GUIDE.md §2).
 *
 * Persisted enums (roles, categories, statuses, blood groups, locales, …) are owned by
 * `src/models/enums.js` because the Mongoose schemas validate against them; they are
 * re-exported here so modules only ever need `import { … } from '../../lib/constants.js'`.
 * Everything declared below is API-level configuration that is never stored.
 */
export * from '../models/enums.js';

const freeze = (list) => Object.freeze([...list]);

// ---------- Access roles (aliases, handy in services) ----------
export const ADMIN = 'admin';
export const MEMBER = 'member';

// ---------- Pagination (contract §1) ----------
export const DEFAULT_PAGE = 1;
export const DEFAULT_PAGE_LIMIT = 20;
export const MAX_PAGE_LIMIT = 100;

// ---------- Auth ----------
export const OTP_LENGTH = 6;
/** OTP validity (contract §4: 10 min). */
export const OTP_TTL_MS = 10 * 60 * 1000;
export const OTP_MAX_ATTEMPTS = 5;
/** Minimum delay between two OTP e-mails for the same (email, purpose). */
export const OTP_RESEND_COOLDOWN_SECONDS = 60;
/** 5 failed logins for an e-mail within 15 min → 429 TOO_MANY_REQUESTS. */
export const LOGIN_MAX_FAILED_ATTEMPTS = 5;
export const LOGIN_LOCK_WINDOW_MS = 15 * 60 * 1000;
/** Refresh tokens are random 48-byte base64url strings (contract §2 "Tokens"). */
export const REFRESH_TOKEN_BYTES = 48;
export const JWT_ISSUER = 'familyhub-api';
export const JWT_AUDIENCE = 'familyhub-app';
export const BCRYPT_ROUNDS = 12;

// ---------- Rate limits (per IP) ----------
export const RATE_LIMIT_WINDOW_MS = 60 * 1000;
export const GLOBAL_RATE_LIMIT_PER_WINDOW = 300;
export const AUTH_RATE_LIMIT_PER_WINDOW = 20;

// ---------- Request limits ----------
export const JSON_BODY_LIMIT = '100kb';

// ---------- Push notifications (contract §13) ----------
export const PUSH_TYPES = freeze([
  'sos',
  'sos_resolved',
  'task_assigned',
  'task_completed',
  'notice',
  'goal_achieved',
  'member_joined',
]);
export const PUSH_TYPE = Object.freeze({
  SOS: 'sos',
  SOS_RESOLVED: 'sos_resolved',
  TASK_ASSIGNED: 'task_assigned',
  TASK_COMPLETED: 'task_completed',
  NOTICE: 'notice',
  GOAL_ACHIEVED: 'goal_achieved',
  MEMBER_JOINED: 'member_joined',
});
/** Android notification channels created by the app. */
export const PUSH_CHANNELS = Object.freeze({ SOS: 'sos_alerts', GENERAL: 'general' });
/** FCM accepts at most 500 tokens per multicast request. */
export const PUSH_BATCH_SIZE = 500;
/** Deep-link routes understood by the app (contract §13). */
export const PUSH_ROUTES = Object.freeze({
  sosAlert: (id) => `/sos/alert/${id}`,
  task: (id) => `/tasks/${id}`,
  notices: () => '/notices',
  money: () => '/money',
  member: (id) => `/members/${id}`,
});

// ---------- Uploads (contract §12) ----------
export const UPLOAD_FOLDERS = freeze(['avatars', 'notices']);
/** Root Cloudinary folder; files land in `familyhub/<familyId>/<folder>`. */
export const UPLOAD_ROOT_FOLDER = 'familyhub';
export const CLOUDINARY_HOST = 'res.cloudinary.com';

// ---------- Dashboard (contract §11) ----------
export const DASHBOARD_LIMITS = Object.freeze({ MY_TASKS: 5, GOALS: 3, NOTICES: 3 });

// ---------- Emergency card (contract §6) ----------
// EMERGENCY_CARD_ENCRYPTED_FIELDS / EMERGENCY_CARD_LIST_FIELDS live in models/enums.js
// (the EmergencyCard schema is built from them) and are re-exported above.

// ---------- Default family settings ----------
// Defaults offered when a family is created. Not to be confused with
// lib/dates.js#DEFAULT_TIME_ZONE ('UTC'), the fallback for an invalid/missing zone.
export const DEFAULT_COUNTRY = 'IN';
export const DEFAULT_CURRENCY = 'INR';
export const DEFAULT_TIMEZONE = 'Asia/Kolkata';
export const DEFAULT_ADMIN_DESIGNATION = 'Head of Family';
