/**
 * Operational error with a stable `code` from docs/03-API_CONTRACT.md §1.
 *
 * The error middleware turns it into `{ success: false, error: { code, message, details? } }`.
 * `message` is localized from the request's Accept-Language:
 *   1. `messageKey` when given explicitly (e.g. `'tasks.errors.assigneeNotInFamily'`),
 *   2. otherwise `common.errors.<CODE>` (src/i18n/locales/<lang>/common.json),
 *   3. otherwise the English `message` passed to the constructor.
 * `vars` fill `{placeholders}` in the translated text.
 */
export class ApiError extends Error {
  /**
   * @param {number} status HTTP status
   * @param {string} code   contract error code (see ErrorCodes)
   * @param {string} [message] English fallback message
   * @param {{ details?: object, messageKey?: string, vars?: object, cause?: unknown }} [opts]
   */
  constructor(status, code, message, { details, messageKey, vars, cause } = {}) {
    super(message ?? code, cause === undefined ? undefined : { cause });
    this.name = 'ApiError';
    this.status = status;
    this.code = code;
    this.details = details;
    this.messageKey = messageKey ?? `common.errors.${code}`;
    this.vars = vars;
    this.expose = true;
  }

  static isApiError(err) {
    return err instanceof ApiError;
  }

  static badRequest(message = 'Bad request', opts) {
    return new ApiError(400, 'BAD_REQUEST', message, opts);
  }
  /** 422 VALIDATION_ERROR; `details` maps field path → message. */
  static validation(details, message = 'Validation failed', opts = {}) {
    return new ApiError(422, 'VALIDATION_ERROR', message, { ...opts, details });
  }
  static unauthorized(message = 'Authentication required') {
    return new ApiError(401, 'UNAUTHORIZED', message);
  }
  static tokenExpired(message = 'Access token expired') {
    return new ApiError(401, 'TOKEN_EXPIRED', message);
  }
  static invalidCredentials(message = 'Invalid email or password') {
    return new ApiError(401, 'INVALID_CREDENTIALS', message);
  }
  static invalidRefreshToken(message = 'Invalid refresh token') {
    return new ApiError(401, 'INVALID_REFRESH_TOKEN', message);
  }
  static forbidden(message = 'You are not allowed to do this', opts) {
    return new ApiError(403, 'FORBIDDEN', message, opts);
  }
  static noFamily(message = 'You are not part of a family yet') {
    return new ApiError(403, 'NO_FAMILY', message);
  }
  static notFound(message = 'Not found') {
    return new ApiError(404, 'NOT_FOUND', message);
  }
  /** 409 with a specific code, e.g. `ApiError.conflict('EMAIL_TAKEN')`. */
  static conflict(code = 'CONFLICT', message, opts) {
    return new ApiError(409, code, message ?? code, opts);
  }
  static tooManyRequests(retryAfterSeconds, message = 'Too many requests, try again later') {
    const seconds = Math.max(1, Math.ceil(Number(retryAfterSeconds) || 1));
    return new ApiError(429, 'TOO_MANY_REQUESTS', message, {
      details: { retryAfterSeconds: seconds },
      vars: { seconds },
    });
  }
  static internal(message = 'Something went wrong', opts) {
    return new ApiError(500, 'INTERNAL_ERROR', message, opts);
  }
  static serviceUnavailable(message = 'Service temporarily unavailable', opts) {
    return new ApiError(503, 'SERVICE_UNAVAILABLE', message, opts);
  }
}

/**
 * Error codes used across modules. All contract codes (§1) plus three generic ones used by
 * the core middleware: CONFLICT (duplicate key without a more specific code),
 * PAYLOAD_TOO_LARGE (body > 100 kb) and SERVICE_UNAVAILABLE (optional integration not configured).
 */
export const ErrorCodes = Object.freeze({
  BAD_REQUEST: 'BAD_REQUEST',
  INVALID_OTP: 'INVALID_OTP',
  OTP_EXPIRED: 'OTP_EXPIRED',
  INVALID_INVITE_CODE: 'INVALID_INVITE_CODE',
  UNAUTHORIZED: 'UNAUTHORIZED',
  TOKEN_EXPIRED: 'TOKEN_EXPIRED',
  INVALID_CREDENTIALS: 'INVALID_CREDENTIALS',
  INVALID_REFRESH_TOKEN: 'INVALID_REFRESH_TOKEN',
  FORBIDDEN: 'FORBIDDEN',
  NO_FAMILY: 'NO_FAMILY',
  LOCATION_SHARING_DISABLED: 'LOCATION_SHARING_DISABLED',
  NOT_FOUND: 'NOT_FOUND',
  EMAIL_TAKEN: 'EMAIL_TAKEN',
  ALREADY_IN_FAMILY: 'ALREADY_IN_FAMILY',
  MEMBER_EMAIL_EXISTS: 'MEMBER_EMAIL_EXISTS',
  LAST_ADMIN: 'LAST_ADMIN',
  SOS_NOT_ACTIVE: 'SOS_NOT_ACTIVE',
  CONFLICT: 'CONFLICT',
  PAYLOAD_TOO_LARGE: 'PAYLOAD_TOO_LARGE',
  VALIDATION_ERROR: 'VALIDATION_ERROR',
  GUARDIAN_CONSENT_REQUIRED: 'GUARDIAN_CONSENT_REQUIRED',
  TOO_MANY_REQUESTS: 'TOO_MANY_REQUESTS',
  INTERNAL_ERROR: 'INTERNAL_ERROR',
  SERVICE_UNAVAILABLE: 'SERVICE_UNAVAILABLE',
});
