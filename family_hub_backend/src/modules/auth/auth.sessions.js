import { ApiError } from '../../lib/ApiError.js';
import { sha256 } from '../../lib/crypto.js';
import { RefreshToken } from '../../models/index.js';
import { rotateRefreshToken } from '../../services/tokens.js';

/**
 * Session (refresh-token) lifecycle on top of services/tokens.js.
 *
 * Sessions are ended by **deleting** refresh-token rows, never by flagging them revoked:
 * `rotateRefreshToken` treats every flagged token as a stolen, re-used one and then revokes
 * all of the user's sessions. A device replaying a token that was logged out or wiped by a
 * password reset must get a plain `401 INVALID_REFRESH_TOKEN` instead of signing the user
 * out everywhere.
 */

/** Rotations followed from a logged-out token before treating the chain as stolen. */
const MAX_CHAIN_HOPS = 50;

/** Ends every session of a user (password reset / change, stolen logout chain). */
export async function endAllSessions(userId) {
  await RefreshToken.deleteMany({ userId });
}

/**
 * Logout: ends the session of one device. Deletes the presented token and every token that
 * was rotated from it — a refresh whose response the app never received, or a copy an
 * attacker kept rotating — so no descendant of a logged-out token stays usable. Only the
 * caller's own tokens are touched. A chain longer than MAX_CHAIN_HOPS means someone else has
 * been refreshing this session for a long time → every session of the user is ended.
 * @returns {Promise<number>} deleted tokens
 */
export async function endDeviceSession(rawToken, userId) {
  if (typeof rawToken !== 'string' || !rawToken) return 0;
  let hash = sha256(rawToken);
  let deleted = 0;
  for (let hop = 0; hash; hop += 1) {
    if (hop > MAX_CHAIN_HOPS) {
      await endAllSessions(userId);
      break;
    }
    const row = await RefreshToken.findOneAndDelete({ tokenHash: hash, userId }).select('replacedByHash').lean();
    if (!row) break;
    deleted += 1;
    hash = row.replacedByHash;
  }
  return deleted;
}

/**
 * `POST /auth/refresh`: rotation + reuse detection (services/tokens.js), plus a check that the
 * sessions were not ended while the rotation ran. A password reset / logout that deletes the
 * old row between rotateRefreshToken's lookup and its insert of the new row would otherwise
 * leave a fresh token behind — an attacker refreshing a stolen token in a loop would survive
 * the reset. When the old row is gone afterwards, the new one is deleted and the call fails.
 */
export async function refreshSession(rawToken, meta) {
  const tokens = await rotateRefreshToken(rawToken, meta);
  if (!(await RefreshToken.exists({ tokenHash: sha256(rawToken) }))) {
    await RefreshToken.deleteOne({ tokenHash: sha256(tokens.refreshToken) });
    throw ApiError.invalidRefreshToken();
  }
  return tokens;
}
