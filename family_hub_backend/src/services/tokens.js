import jwt from 'jsonwebtoken';
import { env } from '../config/env.js';
import { ApiError } from '../lib/ApiError.js';
import { JWT_AUDIENCE, JWT_ISSUER, REFRESH_TOKEN_BYTES } from '../lib/constants.js';
import { randomToken, sha256 } from '../lib/crypto.js';
import { logger } from '../lib/logger.js';
import { RefreshToken, User } from '../models/index.js';

/**
 * Access + refresh tokens (docs/03-API_CONTRACT.md §2 "Tokens").
 *
 * - Access token: JWT HS256, `sub` = userId, lifetime ACCESS_TOKEN_TTL_SECONDS (15 min).
 * - Refresh token: random 48-byte base64url string, stored only as sha256 hash, valid
 *   REFRESH_TOKEN_TTL_DAYS (30 days), rotated on every refresh. Presenting an already
 *   rotated/revoked token is treated as theft → every refresh token of that user is revoked.
 */

const ALGORITHM = 'HS256';

function userIdOf(user) {
  const id = user?._id ?? user?.id ?? user;
  if (!id) throw new TypeError('user id required');
  return String(id);
}

function refreshExpiry(from = Date.now()) {
  return new Date(from + env.REFRESH_TOKEN_TTL_DAYS * 24 * 60 * 60 * 1000);
}

function cleanMeta({ ip, userAgent } = {}) {
  return {
    ip: typeof ip === 'string' && ip ? ip.slice(0, 64) : null,
    userAgent: typeof userAgent === 'string' && userAgent ? userAgent.slice(0, 256) : null,
  };
}

/** Signs a short-lived access token for a user (doc, lean object or id). */
export function signAccessToken(user) {
  return jwt.sign({}, env.JWT_ACCESS_SECRET, {
    algorithm: ALGORITHM,
    subject: userIdOf(user),
    expiresIn: env.ACCESS_TOKEN_TTL_SECONDS,
    issuer: JWT_ISSUER,
    audience: JWT_AUDIENCE,
  });
}

/**
 * Verifies an access token.
 * @returns {{ sub: string, iat: number, exp: number }}
 * @throws {ApiError} 401 TOKEN_EXPIRED when expired, 401 UNAUTHORIZED otherwise
 */
export function verifyAccessToken(token) {
  if (typeof token !== 'string' || !token) throw ApiError.unauthorized();
  try {
    const payload = jwt.verify(token, env.JWT_ACCESS_SECRET, {
      algorithms: [ALGORITHM],
      issuer: JWT_ISSUER,
      audience: JWT_AUDIENCE,
    });
    if (!payload || typeof payload !== 'object' || typeof payload.sub !== 'string') throw ApiError.unauthorized();
    return payload;
  } catch (err) {
    if (err instanceof ApiError) throw err;
    if (err?.name === 'TokenExpiredError') throw ApiError.tokenExpired();
    throw ApiError.unauthorized();
  }
}

async function createRefreshToken(userId, meta, now = Date.now()) {
  const raw = randomToken(REFRESH_TOKEN_BYTES);
  await RefreshToken.create({
    userId,
    tokenHash: sha256(raw),
    expiresAt: refreshExpiry(now),
    ...cleanMeta(meta),
  });
  return raw;
}

/**
 * Issues a new access + refresh token pair (login, register, password change …).
 * @returns {Promise<{ accessToken: string, refreshToken: string, expiresIn: number }>}
 */
export async function issueTokens(user, meta = {}) {
  const userId = userIdOf(user);
  const refreshToken = await createRefreshToken(userId, meta);
  return { accessToken: signAccessToken(userId), refreshToken, expiresIn: env.ACCESS_TOKEN_TTL_SECONDS };
}

/**
 * Exchanges a refresh token for a new pair (rotation). The old token is revoked atomically,
 * so two concurrent refreshes with the same token cannot both succeed.
 *
 * @throws {ApiError} 401 INVALID_REFRESH_TOKEN when unknown, expired, revoked (→ revokes all
 *                    of the user's tokens) or when the user no longer exists
 * @returns {Promise<{ accessToken: string, refreshToken: string, expiresIn: number }>}
 */
export async function rotateRefreshToken(rawToken, meta = {}) {
  if (typeof rawToken !== 'string' || !rawToken || rawToken.length > 512) throw ApiError.invalidRefreshToken();
  const now = new Date();
  const tokenHash = sha256(rawToken);
  const existing = await RefreshToken.findOne({ tokenHash }).lean();
  if (!existing) throw ApiError.invalidRefreshToken();

  if (existing.revokedAt) {
    await revokeAllUserTokens(existing.userId);
    logger.warn('Refresh token reuse detected; all sessions of the user were revoked');
    throw ApiError.invalidRefreshToken();
  }
  if (existing.expiresAt.getTime() <= now.getTime()) throw ApiError.invalidRefreshToken();

  const user = await User.findById(existing.userId).select('_id').lean();
  if (!user) {
    await RefreshToken.updateOne({ _id: existing._id, revokedAt: null }, { $set: { revokedAt: now } });
    throw ApiError.invalidRefreshToken();
  }

  const newRaw = randomToken(REFRESH_TOKEN_BYTES);
  const newHash = sha256(newRaw);
  // Claim the rotation atomically: only one request can move revokedAt from null.
  const claimed = await RefreshToken.findOneAndUpdate(
    { _id: existing._id, revokedAt: null },
    { $set: { revokedAt: now, replacedByHash: newHash } },
  ).lean();
  if (!claimed) {
    // Lost a race with another refresh using the same token → same as reuse.
    await revokeAllUserTokens(existing.userId);
    throw ApiError.invalidRefreshToken();
  }

  await RefreshToken.create({
    userId: existing.userId,
    tokenHash: newHash,
    expiresAt: refreshExpiry(now.getTime()),
    ...cleanMeta(meta),
  });
  return { accessToken: signAccessToken(existing.userId), refreshToken: newRaw, expiresIn: env.ACCESS_TOKEN_TTL_SECONDS };
}

/**
 * Revokes one refresh token (logout). Idempotent; unknown tokens are ignored.
 * Pass `userId` to only revoke a token that belongs to that user.
 * @returns {Promise<boolean>} true when a token was revoked
 */
export async function revokeRefreshToken(rawToken, { userId } = {}) {
  if (typeof rawToken !== 'string' || !rawToken) return false;
  const filter = { tokenHash: sha256(rawToken), revokedAt: null };
  if (userId) filter.userId = String(userId);
  const res = await RefreshToken.updateOne(filter, { $set: { revokedAt: new Date() } });
  return res.modifiedCount > 0;
}

/** Revokes every active refresh token of a user (password reset, account removal, theft). */
export async function revokeAllUserTokens(userId) {
  if (!userId) return 0;
  const res = await RefreshToken.updateMany(
    { userId: String(userId), revokedAt: null },
    { $set: { revokedAt: new Date() } },
  );
  return res.modifiedCount;
}
