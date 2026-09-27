import { rateLimit } from 'express-rate-limit';
import { env } from '../config/env.js';
import { ApiError } from '../lib/ApiError.js';
import {
  AUTH_RATE_LIMIT_PER_WINDOW,
  GLOBAL_RATE_LIMIT_PER_WINDOW,
  RATE_LIMIT_WINDOW_MS,
} from '../lib/constants.js';

/**
 * Per-IP rate limiters (in-memory store — fine for a single instance; use a shared store
 * such as Redis when running several API instances). Behind a proxy set TRUST_PROXY so
 * `req.ip` is the client address.
 *
 * Limits are skipped in tests unless RATE_LIMIT_IN_TEST=true. When exceeded the request
 * fails with `429 TOO_MANY_REQUESTS` + `details.retryAfterSeconds` (standard error envelope)
 * and `Retry-After` / `RateLimit*` headers.
 */

const skipInTest = () => env.isTest && !env.RATE_LIMIT_IN_TEST;

function handler(req, _res, next, options) {
  const resetTime = req.rateLimit?.resetTime;
  const retryMs = resetTime instanceof Date ? resetTime.getTime() - Date.now() : options.windowMs;
  next(ApiError.tooManyRequests(Math.ceil(retryMs / 1000)));
}

/**
 * Factory for module-specific limiters (e.g. OTP resend). Keyed by client IP unless a
 * `keyGenerator` is given.
 * @param {{ windowMs?: number, limit: number, skip?: (req) => boolean, keyGenerator?: (req, res) => string, identifier?: string }} opts
 */
export function createRateLimiter({ windowMs = RATE_LIMIT_WINDOW_MS, limit, skip, keyGenerator, identifier } = {}) {
  return rateLimit({
    windowMs,
    limit,
    identifier,
    standardHeaders: 'draft-8',
    legacyHeaders: false,
    skip: (req, res) => skipInTest() || (skip ? skip(req, res) : false),
    ...(keyGenerator ? { keyGenerator } : {}),
    handler,
  });
}

/** 300 requests / minute / IP for the whole API (health checks excluded). */
export const globalLimiter = createRateLimiter({
  limit: GLOBAL_RATE_LIMIT_PER_WINDOW,
  identifier: 'global',
  skip: (req) => req.path === '/api/v1/health',
});

/** 20 requests / minute / IP — mount on unauthenticated auth endpoints (login, register, OTP, reset). */
export const authLimiter = createRateLimiter({
  limit: AUTH_RATE_LIMIT_PER_WINDOW,
  identifier: 'auth',
});
