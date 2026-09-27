import { env } from '../../config/env.js';
import { ApiError, ErrorCodes } from '../../lib/ApiError.js';
import { UPLOAD_FOLDERS } from '../../lib/constants.js';
import { logger } from '../../lib/logger.js';
import { familyFolder, signUpload } from '../../services/cloudinary.js';
import { FOLDER_CHOICES } from './uploads.schemas.js';

/**
 * Business rules of `/uploads` (docs/03-API_CONTRACT.md §12).
 *
 * The API secret never leaves the server: the caller gets a short-lived signature for
 * `{ folder: "familyhub/<familyId>/<folder>", timestamp }` and uploads the file straight to
 * Cloudinary. The family comes from the access token, so a member can only ever sign uploads
 * into their own family's folder.
 */

/**
 * Contract addition: `503 UPLOADS_NOT_CONFIGURED` — Cloudinary credentials are missing on this
 * server. A dedicated code (instead of the generic `SERVICE_UNAVAILABLE`) lets the app show
 * "photo uploads are not available" instead of "try again later": retrying cannot help.
 */
export const UPLOADS_NOT_CONFIGURED = 'UPLOADS_NOT_CONFIGURED';

/** English fallback; the localized text lives at `common.errors.UPLOADS_NOT_CONFIGURED`. */
const NOT_CONFIGURED_MESSAGE = 'Photo uploads are not available on this server yet. Please contact the app administrator.';

/** The only keys ever returned to the client (contract §12). */
const SIGNATURE_FIELDS = Object.freeze(['cloudName', 'apiKey', 'timestamp', 'signature', 'folder']);

/** `503 UPLOADS_NOT_CONFIGURED` (message key `common.errors.UPLOADS_NOT_CONFIGURED`). */
export function uploadsNotConfigured(cause) {
  return new ApiError(503, UPLOADS_NOT_CONFIGURED, NOT_CONFIGURED_MESSAGE, { cause });
}

/**
 * Cloud names and API keys are plain tokens (letters, digits, `_`, `-`). The app builds
 * `https://api.cloudinary.com/v1_1/<cloudName>/image/upload` from the cloud name, so whitespace,
 * `/`, `..` or `?` would send the photo to a broken or different URL.
 */
const CREDENTIAL_TOKEN = /^[A-Za-z0-9_-]{1,128}$/;
/** Hex digest: SHA-1 (40) or SHA-256 (64). */
const SIGNATURE_HEX = /^(?:[a-f0-9]{40}|[a-f0-9]{64})$/;

const isCredentialToken = (value) => typeof value === 'string' && CREDENTIAL_TOKEN.test(value);

/**
 * true when the configured API secret has surrounding whitespace (typically a trailing newline
 * from a secrets file): Cloudinary rejects every signature made with it. Read-only guard until
 * `config/env.js` trims the CLOUDINARY_* values; harmless afterwards.
 */
function secretHasStrayWhitespace() {
  const secret = env.CLOUDINARY_API_SECRET;
  return typeof secret === 'string' && secret.length > 0 && secret !== secret.trim();
}

/** Integer seconds timestamp, hex signature and exactly the caller's family folder. */
function isSignatureFor(signed, expectedFolder) {
  return (
    Number.isSafeInteger(signed.timestamp) &&
    signed.timestamp > 0 &&
    typeof signed.signature === 'string' &&
    SIGNATURE_HEX.test(signed.signature) &&
    signed.folder === expectedFolder
  );
}

/**
 * Signs a direct Cloudinary upload into the caller's family folder.
 *
 * `services/cloudinary.js` decides whether credentials are configured (tests use fixed fake
 * credentials) and reports "not configured" as `503 SERVICE_UNAVAILABLE`; this module turns that
 * into the more specific `503 UPLOADS_NOT_CONFIGURED`.
 *
 * Defence in depth (the signer lives in another module), so the app never receives a payload
 * that cannot work or points somewhere else:
 *   - family and folder are re-checked here before the signer runs;
 *   - a blank / malformed cloud name or API key (e.g. `CLOUDINARY_CLOUD_NAME="  "`) or an API
 *     secret with surrounding whitespace is a deployment mistake → `503 UPLOADS_NOT_CONFIGURED`,
 *     logged for the operator (a signature Cloudinary will reject is worse than a clear 503);
 *   - any other unexpected answer (another family's or folder's path, non-integer timestamp,
 *     non-hex signature) → generic `500 INTERNAL_ERROR`, signature withheld;
 *   - only the five contract fields are copied, so an extra field (e.g. a secret) cannot leak.
 *
 * @param {{ familyId: string|null }} user `req.user` (requireFamily guarantees `familyId`)
 * @param {{ folder: 'avatars'|'notices' }} body validated body
 * @param {{ sign?: typeof signUpload }} [deps] injectable signer (tests)
 * @returns {{ cloudName: string, apiKey: string, timestamp: number, signature: string, folder: string }}
 */
export function createSignature(user, { folder } = {}, { sign = signUpload } = {}) {
  if (!user?.familyId) throw ApiError.noFamily();
  if (!UPLOAD_FOLDERS.includes(folder)) throw ApiError.validation({ folder: FOLDER_CHOICES });
  if (secretHasStrayWhitespace()) {
    logger.error('CLOUDINARY_API_SECRET has leading/trailing whitespace (e.g. a trailing newline); uploads are disabled');
    throw uploadsNotConfigured();
  }

  let signed;
  try {
    signed = sign({ familyId: user.familyId, folder });
  } catch (err) {
    if (ApiError.isApiError(err) && err.code === ErrorCodes.SERVICE_UNAVAILABLE) throw uploadsNotConfigured(err);
    throw err;
  }

  // Never log the payload itself: it may hold a replayable signature.
  if (!signed || typeof signed !== 'object') {
    logger.error('Upload signer returned no payload; signature withheld');
    throw ApiError.internal();
  }
  if (!isCredentialToken(signed.cloudName) || !isCredentialToken(signed.apiKey)) {
    logger.error('CLOUDINARY_CLOUD_NAME / CLOUDINARY_API_KEY is blank or malformed (only letters, digits, "_" and "-" are valid); uploads are disabled');
    throw uploadsNotConfigured();
  }
  if (!isSignatureFor(signed, familyFolder(user.familyId, folder))) {
    logger.error("Upload signer returned a payload that is not a signature for the caller's family folder; signature withheld");
    throw ApiError.internal();
  }
  return Object.fromEntries(SIGNATURE_FIELDS.map((key) => [key, signed[key]]));
}
