import mongoose from 'mongoose';
import { ApiError } from '../lib/ApiError.js';
import { hasTranslation, pickLocale, t } from '../lib/i18n.js';
import { logger } from '../lib/logger.js';
import { zodIssuesToDetails } from '../lib/validate.js';

/**
 * 404 for unknown routes and the global error handler (docs/03-API_CONTRACT.md §1).
 * Every error leaves as `{ success: false, error: { code, message, details? } }` with a
 * message localized from `Accept-Language` (`req.locale`).
 */

export function notFoundHandler(req, _res, next) {
  next(ApiError.notFound('Route not found'));
}

/**
 * Duplicate-key (E11000) → contract code, derived from the collection + key.
 * Anything not listed becomes the generic `CONFLICT`. A service can set `err.conflictCode`
 * on a rethrown error to force a code.
 */
const DUPLICATE_KEY_CODES = [
  { collection: /^users$/, field: 'email', code: 'EMAIL_TAKEN' },
  { collection: /^members$/, field: 'email', code: 'MEMBER_EMAIL_EXISTS' },
  { collection: /^members$/, field: 'userId', code: 'ALREADY_IN_FAMILY' },
];

function duplicateKeyError(err) {
  const fields = Object.keys(err.keyPattern ?? err.keyValue ?? {});
  const collection = /collection: [^.\s]+\.(\S+)/.exec(String(err.message ?? ''))?.[1] ?? '';
  const match = DUPLICATE_KEY_CODES.find(
    (rule) => rule.collection.test(collection) && fields.includes(rule.field),
  );
  const code = err.conflictCode ?? match?.code ?? 'CONFLICT';
  // Only field *names* are exposed — never the duplicated values (may be personal data).
  const relevant = fields.filter((f) => f !== 'familyId');
  const details = relevant.length ? Object.fromEntries(relevant.map((f) => [f, 'Already exists'])) : undefined;
  return new ApiError(409, code, 'Duplicate value', { details });
}

function isDuplicateKey(err) {
  return (
    err?.code === 11000 ||
    err?.code === 11001 ||
    err?.cause?.code === 11000 ||
    (Array.isArray(err?.writeErrors) && err.writeErrors.some((w) => w?.code === 11000 || w?.err?.code === 11000))
  );
}

/** Maps any thrown value to an ApiError (or null for "unexpected → 500"). */
export function toApiError(err) {
  if (err instanceof ApiError) return err;
  if (!err || typeof err !== 'object') return null;

  if (err.name === 'ZodError' && Array.isArray(err.issues)) {
    return ApiError.validation(zodIssuesToDetails(err.issues));
  }
  if (err instanceof mongoose.Error.CastError) {
    return ApiError.badRequest('Invalid value', { details: err.path ? { [err.path]: 'Invalid value' } : undefined });
  }
  if (err instanceof mongoose.Error.ValidationError) {
    const details = {};
    for (const [path, e] of Object.entries(err.errors ?? {})) {
      details[path] = e?.kind === 'ObjectId' || e?.name === 'CastError' ? 'Invalid value' : (e?.message ?? 'Invalid value');
    }
    return ApiError.validation(details);
  }
  if (isDuplicateKey(err)) {
    const source = err.code === 11000 || err.code === 11001 ? err : (err.cause ?? err.writeErrors?.[0]?.err ?? err);
    if (err.conflictCode) source.conflictCode = err.conflictCode;
    return duplicateKeyError(source);
  }

  // body-parser / http-errors (express.json)
  switch (err.type) {
    case 'entity.parse.failed':
      return ApiError.badRequest('Malformed JSON body');
    case 'entity.too.large':
      return new ApiError(413, 'PAYLOAD_TOO_LARGE', 'Request body too large');
    case 'encoding.unsupported':
    case 'charset.unsupported':
      return new ApiError(415, 'BAD_REQUEST', 'Unsupported content encoding');
    case 'request.aborted':
    case 'request.size.invalid':
    case 'stream.encoding.set':
    case 'stream.not.readable':
      return ApiError.badRequest('Invalid request body');
    default:
      break;
  }
  if (err instanceof SyntaxError && (err.status === 400 || 'body' in err)) {
    return ApiError.badRequest('Malformed JSON body');
  }
  const status = Number(err.status ?? err.statusCode);
  if (status === 413) return new ApiError(413, 'PAYLOAD_TOO_LARGE', 'Request body too large');
  if (Number.isInteger(status) && status >= 400 && status < 500 && err.expose !== false) {
    return new ApiError(status, status === 404 ? 'NOT_FOUND' : 'BAD_REQUEST', 'Bad request');
  }
  return null;
}

/** Localized message: explicit messageKey → common.errors.<CODE> → English message. */
export function localizeError(apiError, locale) {
  const candidates = [];
  if (apiError.messageKey) {
    // Accept legacy keys without namespace ("errors.X" → "common.errors.X").
    candidates.push(apiError.messageKey.startsWith('errors.') ? `common.${apiError.messageKey}` : apiError.messageKey);
  }
  candidates.push(`common.errors.${apiError.code}`);
  for (const key of candidates) {
    if (hasTranslation(key, locale)) return t(locale, key, apiError.vars);
  }
  return apiError.message || apiError.code;
}

// eslint-disable-next-line no-unused-vars
export function errorHandler(err, req, res, next) {
  if (res.headersSent) return next(err);

  let apiError = toApiError(err);
  if (!apiError) {
    logger.error(`Unhandled error on ${req.method} ${req.originalUrl?.split('?')[0]}:`, err?.stack ?? err);
    apiError = ApiError.internal();
  } else if (apiError.status >= 500) {
    logger.error(`${apiError.code} on ${req.method} ${req.originalUrl?.split('?')[0]}:`, err?.stack ?? err);
  }

  const body = {
    success: false,
    error: { code: apiError.code, message: localizeError(apiError, req.locale ?? pickLocale(req.get?.('accept-language'))) },
  };
  if (apiError.details && typeof apiError.details === 'object' && Object.keys(apiError.details).length) {
    body.error.details = apiError.details;
  }
  const retryAfter = apiError.details?.retryAfterSeconds;
  if (apiError.status === 429 && retryAfter) res.setHeader('Retry-After', String(retryAfter));
  res.status(apiError.status).json(body);
}
