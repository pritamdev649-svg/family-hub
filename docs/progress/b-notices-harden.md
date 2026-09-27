# Progress · b-notices-harden (security and robustness review of the backend notice board)

Files owned (same as b-notices): `family_hub_backend/src/modules/notices/**`,
`family_hub_backend/src/i18n/locales/en/notices.json`, `family_hub_backend/tests/notices.test.js`.
Details of every finding: `docs/progress/b-notices.md` → "Hardening review".

## Done
- [x] Attacked the module from these angles:
  - authorization;
  - cross-family access by id;
  - NoSQL operators in the body and the query;
  - mass assignment;
  - invalid ids;
  - oversized payloads;
  - Unicode (emoji, RTL, invisible text, control characters, lone surrogates);
  - numeric and pagination edge cases;
  - members who left or moved to another family;
  - concurrent PATCH / DELETE;
  - push audience and language;
  - contract envelope and error codes.
- [x] H-01 Title and body limits are counted in UTF-16 code units. Before, emoji-heavy text passed zod
      and failed in Mongoose with a raw message that echoed the input.
- [x] H-02 Titles or bodies made only of invisible characters are rejected.
- [x] H-03 Control characters are cleaned up: titles become one line; bodies keep line breaks and tabs.
- [x] H-04 Text is made well-formed UTF-16, so the response always equals the stored notice.
- [x] H-05 `imageUrl` with a `user@` part or an explicit port is rejected. Accepted URLs are stored in
      canonical form.
- [x] H-06 The `imageUrl` length is checked after canonicalisation.
- [x] H-07 Per-account limit on `POST /notices` (10 per minute, then `429 TOO_MANY_REQUESTS`) against
      push flooding.
- [x] H-08 `listLatestNotices` returns `[]` for a malformed family id (no CastError) and caps the limit at 100.
- [x] The push tests no longer hard-code English for `hi` devices, so they survive the translations.
- [x] Tests: 41 → 63 (22 new in the `hardening:` suites). The 9 tests for H-01 to H-08 were run against
      the original code and failed there; the other 13 guard behaviour that was already correct.
- [x] Verified:
  - `node scripts/check-syntax.js`: all OK.
  - `node --test tests/notices.test.js`: 63/63, three runs in a row.
  - `npm test`: 645/645.

## Pending / handoffs
- [ ] b-core: move the text helpers into `src/lib/text.js`, and update the two imports in
      `notices.schemas.js` and `notices.service.js`. The helpers are `toSingleLine`, `toMultiLine` and
      `hasVisibleText` (now imported from `tasks.schemas.js`) and `pushTitle` (from `tasks.service.js`).
- [ ] b-core: add the "no user info / no port + canonical `href`" rule to the shared `cloudinaryUrl` in
      `lib/validate.js`, so `me.avatarUrl` and family member avatars get it too. Notices could then drop
      their local wrapper.
- [ ] Docs owner: contract §9 could mention `429 TOO_MANY_REQUESTS` on `POST /notices` (10 per minute
      per account). Also: title is single-line, text must contain a visible character, and `imageUrl` is
      stored in canonical form.
- [ ] f-notices: show the localized `TOO_MANY_REQUESTS` error on post. Optionally mirror H-02, H-03 and
      H-05 in `notices_mock_handlers.dart`, which still accepts `https://x@res.cloudinary.com/…`,
      zero-width titles and multi-line titles.
- [ ] Still open from b-notices: translations of `notices.json`, the Cloudinary asset clean-up (GAP-02)
      and the dashboard's use of `listLatestNotices`.

## Known issues
- Two identical POSTs (a double submit) still create two notices, because the contract has no
  idempotency key. The app guards against it.
- The rate limiter is in-memory, per instance. It needs a shared store (for example Redis) when the API
  runs on more than one instance.
- The model index `{familyId, pinned, createdAt}` lacks the `_id` tie-breaker used by `NOTICE_SORT`. This
  is fine for family-sized boards; b-models could add `_id: -1` to it.
