# b-uploads-harden: Security and robustness review of backend module "uploads" (progress)

Owner: b-uploads-harden · Scope: docs/03-API_CONTRACT.md §12 · Files: `family_hub_backend/src/modules/uploads/**`, `family_hub_backend/tests/uploads.test.js`.
The full list of findings is appended to `docs/progress/b-uploads.md` under "Hardening review".

## Done

- [x] Reviewed routes, controller, service and schemas against the contract, the auth middleware, the rate limiter, the body parser and `services/cloudinary.js`. Probed the running app (scratch script) before writing tests.
- [x] **Fixed:** blank or whitespace Cloudinary cloud name / API key returned a 200 with an unusable `cloudName`. They now get `503 UPLOADS_NOT_CONFIGURED` and an operator log. Cloud name and API key must be plain tokens, so the app's upload URL can't be redirected.
- [x] **Fixed:** an API secret with a trailing newline made every upload fail at Cloudinary. It now gets `503 UPLOADS_NOT_CONFIGURED` and an operator log (read-only guard; harmless once `config/env.js` trims).
- [x] **Hardened:** the service re-checks family and folder, and verifies the signer's answer (exact caller family folder, integer timestamp, hex SHA-1/SHA-256 signature). Anything unexpected becomes `500 INTERNAL_ERROR` and the signature is withheld (never logged). Only the 5 contract fields are copied.
- [x] The signer can be injected (`createSignature(user, body, { sign })`) so these rules are unit-tested in-process.
- [x] DRY: `FOLDER_CHOICES` is exported from `uploads.schemas.js` and reused by the service.
- [x] Tests: 21 → 41, all green, run repeatedly. New coverage:
  - forged and foreign tokens;
  - family re-read on every request (removed mid-session, moved to another family, stale link);
  - about 75 hostile folder values at schema level, with HTTP representatives;
  - prototype pollution and duplicate keys;
  - query-string and form bodies ignored;
  - 99 kb (no echo), 40 000-level nesting, 200 kb (413), gzip bomb (413);
  - concurrent burst (exactly 30 of 35 signed; a fresh token or spoofed IP shares the budget; forged 401s don't consume it);
  - localized 422 / 403 / 429 / 503 (Accept-Language and the user's saved locale);
  - whitespace and padded credentials (child process);
  - no secret in the payload.

## Pending (outside my files, see handoffs)

- [ ] Contract / Cloudinary settings: the signature binds only `folder` + `timestamp`. `resource_type`, formats and size are not signed, so the holder can upload any file type, any number of times, for up to 1 hour.
- [ ] `config/env.js` should trim the `CLOUDINARY_*` values (b-core).
- [ ] `me` / `family` / `notices` image URL fields should use `isFamilyAssetUrl(url, familyId)`. Today any `res.cloudinary.com` URL is accepted, from any account or family folder.
- [ ] `ErrorCodes.UPLOADS_NOT_CONFIGURED` + `common.errors.UPLOADS_NOT_CONFIGURED` (b-core), plus the contract §1 / §12 update (docs owner). Handed off earlier by b-uploads.

## Known issues

- A full `npm test` run had 1 flaky failure out of 697, unrelated to uploads: `tests/core.test.js:153` "forged, foreign, alg=none and non-ObjectId tokens" with `socket hang up` (ECONNRESET). `core.test.js` alone passes 94/94.
- While I was probing, `src/modules/sos/sos.schemas.js` briefly failed to load because it contained raw U+2028/U+2029 characters inside a regex. That broke every test file that boots the app. The sos owner fixed it within minutes; I didn't touch it.
- The in-memory rate-limit store is per instance (unchanged; shared limiter design).
