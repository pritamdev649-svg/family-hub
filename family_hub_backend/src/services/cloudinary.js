import { v2 as cloudinary } from 'cloudinary';
import { env } from '../config/env.js';
import { toId } from '../lib/access.js';
import { ApiError } from '../lib/ApiError.js';
import { UPLOAD_FOLDERS, UPLOAD_ROOT_FOLDER } from '../lib/constants.js';
import { isCloudinaryHostUrl } from '../lib/validate.js';

/**
 * Signed direct uploads to Cloudinary (docs/03-API_CONTRACT.md §12). The API secret never
 * leaves the server: the app receives a signature for `{ folder, timestamp }` and uploads
 * the file straight to Cloudinary.
 *
 * Not configured → `503 SERVICE_UNAVAILABLE` (tests use fixed fake credentials so the
 * endpoint stays testable).
 */

const TEST_CREDENTIALS = Object.freeze({ cloudName: 'demo', apiKey: '1234', apiSecret: 'test-secret' });

export function isCloudinaryConfigured() {
  return Boolean(env.CLOUDINARY_CLOUD_NAME && env.CLOUDINARY_API_KEY && env.CLOUDINARY_API_SECRET);
}

function credentials() {
  if (isCloudinaryConfigured()) {
    return {
      cloudName: env.CLOUDINARY_CLOUD_NAME,
      apiKey: env.CLOUDINARY_API_KEY,
      apiSecret: env.CLOUDINARY_API_SECRET,
    };
  }
  if (env.isTest) return TEST_CREDENTIALS;
  return null;
}

/** `familyhub/<familyId>/<folder>` */
export function familyFolder(familyId, folder) {
  return `${UPLOAD_ROOT_FOLDER}/${toId(familyId)}/${folder}`;
}

/**
 * Signs an upload for the caller's family.
 * @param {{ familyId: string, folder: 'avatars'|'notices' }} opts
 * @returns {{ cloudName: string, apiKey: string, timestamp: number, signature: string, folder: string }}
 */
export function signUpload({ familyId, folder }) {
  if (!UPLOAD_FOLDERS.includes(folder)) {
    throw ApiError.validation({ folder: `Must be one of: ${UPLOAD_FOLDERS.join(', ')}` });
  }
  if (!familyId) throw ApiError.noFamily();
  const creds = credentials();
  if (!creds) throw ApiError.serviceUnavailable('Image uploads are not configured');

  const timestamp = Math.floor(Date.now() / 1000);
  const fullFolder = familyFolder(familyId, folder);
  const signature = cloudinary.utils.api_sign_request({ folder: fullFolder, timestamp }, creds.apiSecret);
  return { cloudName: creds.cloudName, apiKey: creds.apiKey, timestamp, signature, folder: fullFolder };
}

/** true for an https URL on res.cloudinary.com (same rule as the zod `cloudinaryUrl` block). */
export const isCloudinaryUrl = isCloudinaryHostUrl;

/**
 * Stricter check: the URL points into this family's upload folder
 * (`/<cloudName>/image/upload/…/familyhub/<familyId>/…`). Use it when an image must belong
 * to the caller's family.
 */
export function isFamilyAssetUrl(url, familyId) {
  if (!isCloudinaryUrl(url) || !familyId) return false;
  const { pathname } = new URL(url);
  const cloudName = credentials()?.cloudName;
  if (cloudName && !pathname.startsWith(`/${cloudName}/`)) return false;
  return pathname.includes(`/${UPLOAD_ROOT_FOLDER}/${toId(familyId)}/`);
}
