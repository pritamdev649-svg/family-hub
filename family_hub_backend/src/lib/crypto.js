import crypto from 'node:crypto';
import { env } from '../config/env.js';
import { INVITE_CODE_ALPHABET, INVITE_CODE_LENGTH } from './constants.js';

/** sha256 hex — used to store refresh tokens and OTPs hashed. */
export function sha256(value) {
  return crypto.createHash('sha256').update(String(value)).digest('hex');
}

export function randomToken(bytes = 48) {
  return crypto.randomBytes(bytes).toString('base64url');
}

/** Cryptographically random numeric code, e.g. 6-digit OTP. */
export function randomDigits(length = 6) {
  let out = '';
  for (let i = 0; i < length; i++) out += crypto.randomInt(0, 10).toString();
  return out;
}

/** 8-char invite code without ambiguous characters (0/O/1/I) — `INVITE_CODE_ALPHABET`. */
export function randomInviteCode(length = INVITE_CODE_LENGTH) {
  let out = '';
  for (let i = 0; i < length; i++) out += INVITE_CODE_ALPHABET[crypto.randomInt(0, INVITE_CODE_ALPHABET.length)];
  return out;
}

/** Constant-time string comparison. */
export function safeEqual(a, b) {
  const ab = Buffer.from(String(a));
  const bb = Buffer.from(String(b));
  if (ab.length !== bb.length) return false;
  return crypto.timingSafeEqual(ab, bb);
}

// ---------- Field-level encryption (AES-256-GCM) for sensitive health data ----------

let cachedKey;
function key() {
  if (cachedKey) return cachedKey;
  if (env.FIELD_ENCRYPTION_KEY) {
    const k = Buffer.from(env.FIELD_ENCRYPTION_KEY, 'base64');
    if (k.length !== 32) throw new Error('FIELD_ENCRYPTION_KEY must be 32 bytes (base64)');
    cachedKey = k;
  } else {
    // Dev/test only (env.js refuses to start in production without a key).
    cachedKey = crypto.createHash('sha256').update(`dev-field-key:${env.JWT_ACCESS_SECRET}`).digest();
  }
  return cachedKey;
}

const PREFIX = 'enc:v1:';
const CIPHER = 'aes-256-gcm';
const IV_BYTES = 12;
const TAG_BYTES = 16;

/** Encrypts any JSON-serialisable value -> string `enc:v1:<iv>.<tag>.<cipher>` (base64url). */
export function encryptField(value) {
  if (value === null || value === undefined) return value;
  const iv = crypto.randomBytes(IV_BYTES);
  const cipher = crypto.createCipheriv(CIPHER, key(), iv, { authTagLength: TAG_BYTES });
  const plaintext = Buffer.from(JSON.stringify(value), 'utf8');
  const enc = Buffer.concat([cipher.update(plaintext), cipher.final()]);
  const tag = cipher.getAuthTag();
  return `${PREFIX}${iv.toString('base64url')}.${tag.toString('base64url')}.${enc.toString('base64url')}`;
}

/**
 * Reverses encryptField. Non-encrypted input is returned unchanged.
 * @throws {Error} when the value is corrupted or was encrypted with another key (GCM
 *   authentication fails) — never silently returns wrong/empty data.
 */
export function decryptField(stored) {
  if (typeof stored !== 'string' || !stored.startsWith(PREFIX)) return stored;
  const parts = stored.slice(PREFIX.length).split('.');
  if (parts.length !== 3 || parts.some((p) => !p)) throw new Error('Encrypted field is malformed');
  const [ivB, tagB, encB] = parts;
  const decipher = crypto.createDecipheriv(CIPHER, key(), Buffer.from(ivB, 'base64url'), { authTagLength: TAG_BYTES });
  decipher.setAuthTag(Buffer.from(tagB, 'base64url'));
  const dec = Buffer.concat([decipher.update(Buffer.from(encB, 'base64url')), decipher.final()]);
  return JSON.parse(dec.toString('utf8'));
}
