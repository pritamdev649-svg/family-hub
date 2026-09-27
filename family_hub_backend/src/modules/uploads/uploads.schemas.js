import { z } from 'zod';
import { UPLOAD_FOLDERS } from '../../lib/constants.js';

/**
 * Validation for `/uploads` (docs/03-API_CONTRACT.md §12).
 *
 * `POST /uploads/signature` body: `{ folder: "avatars" | "notices" }`.
 *   - `folder` is the exact contract value (case-sensitive, no trimming): it becomes part of the
 *     signed Cloudinary folder `familyhub/<familyId>/<folder>`, so paths such as `../x`,
 *     `familyhub/<otherFamilyId>/avatars` or `avatars/` are rejected with 422 `details.folder`.
 *   - Unknown keys (e.g. `familyId`, `public_id`) are stripped: the family always comes from the
 *     access token, never from the body.
 */

/** 422 `details.folder` text (also used by the service's own guard). */
export const FOLDER_CHOICES = `Must be one of: ${UPLOAD_FOLDERS.join(', ')}`;

export const signatureBody = z.object({
  folder: z.enum(UPLOAD_FOLDERS, {
    error: (issue) => (issue.input === undefined || issue.input === null ? `Folder is required. ${FOLDER_CHOICES}` : FOLDER_CHOICES),
  }),
});
