# b-uploads: Backend module "uploads" (progress)

Owner: b-uploads · Scope: docs/03-API_CONTRACT.md §12 · Files: `family_hub_backend/src/modules/uploads/*`, `family_hub_backend/tests/uploads.test.js`

## Built

- [x] `uploads.routes.js`: replaced the placeholder. `POST /uploads/signature` → `requireAuth` → per-user limiter → `requireFamily` → `validate({ body })` → controller.
      Exports `SIGNATURE_RATE_LIMIT_PER_MINUTE = 30`.
  - Order of checks: 401 (no, malformed or expired token) → 429 (30 per minute per **user**) → 403 `NO_FAMILY` → 422 (body) → 503 `UPLOADS_NOT_CONFIGURED`.
  - The limiter comes from the shared `createRateLimiter` and is keyed by `user:<userId>`, not by IP, because family members often share one home IP. It runs right after auth, so invalid bodies also count. It sends the standard 429 envelope with `details.retryAfterSeconds`, plus `Retry-After` and the draft-8 `RateLimit` / `RateLimit-Policy` headers (policy name `"uploads"`).
- [x] `uploads.schemas.js`: `signatureBody = { folder: z.enum(UPLOAD_FOLDERS) }`.
  - The value must match exactly: case-sensitive and not trimmed. Path-like values (`../x`, `avatars/`, `familyhub/<otherFamilyId>/avatars`) are rejected with 422 `details.folder` ("Must be one of: avatars, notices"). A missing or null folder gets "Folder is required. …".
  - Unknown keys (`familyId`, `public_id`, `timestamp`, `signature`, …) are dropped. The family always comes from the token.
- [x] `uploads.service.js`: `createSignature(user, { folder })` wraps `services/cloudinary.signUpload` and returns **only** the 5 contract fields.
  - When Cloudinary is not configured, `signUpload` throws `SERVICE_UNAVAILABLE`. The service turns that into `503 UPLOADS_NOT_CONFIGURED`.
  - Also exports `UPLOADS_NOT_CONFIGURED` and `uploadsNotConfigured(cause)`. The message key is `common.errors.UPLOADS_NOT_CONFIGURED`, with an English fallback text.
- [x] `uploads.controller.js`: sends `200` with `ok()` and `Cache-Control: no-store`, because a signature is an upload credential.
- [x] `tests/uploads.test.js`: 21 tests, all green.
  - Happy paths: admin and member × both folders; another family gets its own folder; extra body keys are ignored; parallel requests; exact payload keys; timestamp window; SHA-1 format; no-store header.
  - Auth: no token, malformed token, wrong scheme, expired token (`TOKEN_EXPIRED`). `NO_FAMILY` comes before validation.
  - Other family: every attempt to target family A's folder is refused with 422, never signed.
  - Validation: 15 invalid folder values, missing folder / no body / text/plain body, array body (`details.body`), primitive JSON and malformed JSON (400).
  - 404 for other methods and paths.
  - Service unit checks.
  - Rate limit: 30 × 200, then 429 with `retryAfterSeconds` and `Retry-After`. Invalid bodies are also refused once limited. Another user on the same IP is not affected.
  - **Real configuration in a child process** (`NODE_ENV=development`, same in-memory DB):
    - Not configured → 503 `UPLOADS_NOT_CONFIGURED` for admins and members, and 401/403/422 still come first.
    - Partly configured (no secret) → 503.
    - Configured → the configured `cloudName`/`apiKey`, and a signature equal to Cloudinary's SHA-1 of `folder=…&timestamp=…` + secret. The secret never appears in the response.

## Contract additions (to be written into docs/03-API_CONTRACT.md — see handoffs)

- `503 UPLOADS_NOT_CONFIGURED`: `POST /uploads/signature` when the server has no Cloudinary credentials (cloud name, API key and API secret are all required). No `Retry-After`: retrying cannot help. The app should say photo uploads are unavailable, not "try again later".
- §12 details:
  - Any family member (admin or member) may sign either folder.
  - `200` response with `Cache-Control: no-store`.
  - `403 NO_FAMILY` without a family.
  - `422 details.folder` for anything except the exact `avatars` / `notices`.
  - `429 TOO_MANY_REQUESTS` after 30 signatures per minute per user.

## Pending

- [ ] `common.errors.UPLOADS_NOT_CONFIGURED` translation. Until b-core adds it to `en/common.json` (and translators add it to the other 14 locales), every language gets the English fallback text from the service.
- [ ] Contract / Flutter updates listed under handoffs.

## Known issues / decisions

- "Other family → 404" has no equivalent here because the endpoint takes no resource id. Family isolation is built in: the folder always comes from `req.user.familyId`, and path-like folders are rejected.
- The upload limits (formats, max size) are not signed. The contract fixes the upload fields at `file, api_key, timestamp, signature, folder`, and the app sends exactly those. Limits belong in the Cloudinary account / upload preset (TASKS UPL-06).
- The rate limit uses the shared in-memory store (one instance only, same as the other limiters).
- `tests/uploads.test.js` sets `RATE_LIMIT_IN_TEST=true` before loading `helpers.js`, so all limiters are live in that file. Each test user stays below 30 signature requests per minute. Only `limited` and `racer` go over, on purpose; `fuzzer` is the tightest (~23). The file registers 8 users (auth limiter: 20 per minute per IP) and sends about 170 requests (global limiter: 300 per minute per IP). If you add tests there, keep within these limits and put long hostile-value lists at the schema level.
- The child-process tests run in an empty temporary working directory, so a developer's `.env` cannot inject real Cloudinary credentials.
- In one full `npm test` run, `tests/core.test.js` › "pagination, response envelope, family scoping and access checks" failed once. It is not related to uploads (it passes on its own: 94/94) and is probably caused by files other agents were editing at the same time.

## Hardening review (b-uploads-harden, 2026-09-27)

An adversarial pass over `POST /uploads/signature`. The test file grew from 21 to **41 tests** (all green, run 4 times in a row). What was attacked, what broke, and what changed:

### Issues found and fixed

1. **Blank or whitespace credentials produced a useless 200.** With `CLOUDINARY_CLOUD_NAME="  "` / `CLOUDINARY_API_KEY=" "`, `isCloudinaryConfigured()` returned true, and the endpoint returned `cloudName: "  "`. The app would then upload to `https://api.cloudinary.com/v1_1/  /image/upload`.
   - Fix: the service checks that `cloudName` and `apiKey` are plain tokens (`[A-Za-z0-9_-]{1,128}`, so no whitespace, `/`, `..` or `?` can change the upload URL). If they aren't, it returns `503 UPLOADS_NOT_CONFIGURED` and logs a message for the operator.
   - Test: child process with blank values, plus 13 unit cases.
2. **An API secret with a trailing newline signed every upload wrongly.** This typically comes from `echo secret | base64` into a Kubernetes secret. Every upload then failed at Cloudinary with "Invalid Signature".
   - Fix: a read-only guard in the service returns `503 UPLOADS_NOT_CONFIGURED` and logs the cause.
   - Test: child process with a padded secret. The test also accepts a correct trimmed-secret signature, so it keeps passing after b-core trims the variables in `config/env.js`.
3. **Nothing checked the signer's answer (defence in depth).** The service blindly returned what `services/cloudinary.signUpload` (another module) produced. It now:
   - re-checks family and folder before signing;
   - returns `500 INTERNAL_ERROR` and withholds the signature (never logging it) when the answer is for any other folder or family, has a non-integer timestamp or a non-hex signature, or is not an object;
   - still copies only the 5 contract fields.
   - The signer can be injected (`createSignature(user, body, { sign })`), so all of this is unit-tested in-process.
4. `FOLDER_CHOICES` is now exported from `uploads.schemas.js` and reused by the service's guard (DRY).

### Attacks tried that held (each has a test now)

- **Auth:** a forged token for a real user gets 401 and does **not** consume that user's 30/min budget, so an attacker can't lock a victim out. Tried: `alg: none`, wrong secret, HS512, wrong issuer/audience, unknown user, 12-character "ObjectId" subject, `{ $ne: null }` as subject, refresh token used as a bearer token, two tokens in one header.
- **Family re-read on every request:** with the same token, a member removed mid-session gets 403 `NO_FAMILY`; after joining family B they get **only** B's folder, even with `familyId: <A>` in the body. A stale link (user points at A, member row is in B) also gets 403.
- **Hostile folder values:** about 75 values are rejected at schema level (look-alike letters such as Cyrillic, dotless ı, full-width and small caps; zero-width, BOM, soft hyphen and bidi controls; NUL/CR/LF/U+2028; case near-misses; `..`, `\`, `%2e%2e%2f`, `?`, `#`, `&`, `,`; other scripts and emoji; 10 000 characters; `0`, `-1`, `1e13`, `0.1+0.2`, NaN, ±Infinity, `-0`, booleans, null, arrays, `{}`; `$ne` / `$in` / `$regex` / `$gt` / `$exists`). Representatives are also sent over HTTP, including raw JSON `1e999`.
- **Mass assignment and prototype pollution:** `__proto__` / `constructor.prototype` keys are stripped and never inherited, and `Object.prototype` stays clean.
- **Duplicate JSON keys:** the last one wins, and it is still validated.
- **Other body sources:** the folder from the query string and form-encoded bodies are ignored.
- **Size limits:** a 99 kb string gets 422 **without echoing the input** (response < 1 kb); 40 000 levels of nesting get 422 (no stack overflow or 500); 200 kb gets 413; a gzip bomb (5 MB inflated from ~5 kb) gets 413, because the limit applies to the inflated size. A 413 happens before authentication, so it never costs a signature.
- **Concurrency:** 35 simultaneous requests yield **exactly 30** signatures and 5 × 429, each with `Retry-After`. A freshly issued token and spoofed `X-Forwarded-For` / `X-Real-IP` share the same per-user budget.
- **Localization:**
  - With `Accept-Language: hi-IN,…`, the 422 message is the localized text and `Content-Language` is `hi`.
  - Without the header, the user's saved locale is used (403 in Arabic).
  - The 429 message is in Spanish.
  - The 503 `UPLOADS_NOT_CONFIGURED` message follows the requested language. It falls back to English until the key is translated.
- **No leaks:** neither the test secret nor any `secret`-like text appears in the 200 payload.

### Still open (outside these files, see the b-uploads-harden report and handoffs)

- [ ] **Signature scope (contract).** The signature binds only `folder` + `timestamp`. `resource_type` is in the URL and not signed, so for up to 1 hour the holder can upload any number of files of any type (image/video/raw/auto) into the family folder. Restricting formats and size needs either Cloudinary account settings (restricted media types; a default signed upload preset with `allowed_formats`) or a contract change that signs `allowed_formats` / `upload_preset` and makes the app send them.
- [ ] `config/env.js` should trim the `CLOUDINARY_*` values (b-core). The guards above then never fire.
- [ ] Image URL fields accept **any** `res.cloudinary.com` URL, from any Cloudinary account or any family's folder. `services/cloudinary.isFamilyAssetUrl(url, familyId)` already exists but no module uses it. This affects `me.schemas.js` avatarUrl, `family.schemas.js` avatarUrl and `notices.schemas.js` imageUrl.
- [ ] `common.errors.UPLOADS_NOT_CONFIGURED` + `ErrorCodes.UPLOADS_NOT_CONFIGURED` (unchanged from above).
