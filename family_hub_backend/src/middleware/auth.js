import { isObjectId } from '../lib/access.js';
import { ApiError } from '../lib/ApiError.js';
import { ROLE } from '../lib/constants.js';
import { isSupportedLocale } from '../lib/i18n.js';
import { Member, User } from '../models/index.js';
import { verifyAccessToken } from '../services/tokens.js';
import { setRequestLocale } from './locale.js';

/**
 * Authentication / authorisation middleware (docs/06-BACKEND_GUIDE.md §3).
 *
 * `requireAuth` sets
 *   req.user   = { id, email, name, locale, emailVerified, familyId, memberId, role }
 *                (ids as strings; familyId/memberId/role null when the user has no family)
 *   req.member = the caller's Member (lean) or null
 * A user whose member row disappeared (removed from the family) is treated as "no family".
 */

function bearerToken(req) {
  const header = req.get('authorization');
  if (!header) return null;
  const [scheme, token, extra] = header.trim().split(/\s+/);
  if (!/^bearer$/i.test(scheme ?? '') || !token || extra) return null;
  return token;
}

export async function requireAuth(req, res, next) {
  const token = bearerToken(req);
  if (!token) throw ApiError.unauthorized();
  const payload = verifyAccessToken(token);
  // A correctly signed token always carries an ObjectId; anything else is not ours.
  if (!isObjectId(payload.sub)) throw ApiError.unauthorized();

  const user = await User.findById(payload.sub)
    .select('_id email name locale emailVerified familyId memberId')
    .lean();
  if (!user) throw ApiError.unauthorized();

  let member = null;
  if (user.familyId && user.memberId) {
    member = await Member.findOne({ _id: user.memberId, familyId: user.familyId, userId: user._id }).lean();
  }

  req.user = {
    id: String(user._id),
    email: user.email,
    name: user.name,
    locale: user.locale,
    emailVerified: Boolean(user.emailVerified),
    familyId: member ? String(user.familyId) : null,
    memberId: member ? String(member._id) : null,
    role: member ? (member.role ?? ROLE.MEMBER) : null,
  };
  req.member = member;

  // No Accept-Language header → answer in the user's saved language.
  if (!req.localeFromHeader && isSupportedLocale(user.locale)) setRequestLocale(req, res, user.locale);
  next();
}

/** 403 NO_FAMILY unless the caller belongs to a family. Use after requireAuth. */
export function requireFamily(req, _res, next) {
  if (!req.user) throw ApiError.unauthorized();
  if (!req.user.familyId) throw ApiError.noFamily();
  next();
}

/** 403 FORBIDDEN unless the caller is a family admin (403 NO_FAMILY without a family). */
export function requireAdmin(req, _res, next) {
  if (!req.user) throw ApiError.unauthorized();
  if (!req.user.familyId) throw ApiError.noFamily();
  if (req.user.role !== ROLE.ADMIN) throw ApiError.forbidden();
  next();
}

/** Convenience chains: `router.use(...familyMember)` / `router.post('/', ...familyAdmin, …)`. */
export const familyMember = Object.freeze([requireAuth, requireFamily]);
export const familyAdmin = Object.freeze([requireAuth, requireAdmin]);
