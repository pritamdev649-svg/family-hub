# Progress · b-notices (backend notice board)

Owned files: `family_hub_backend/src/modules/notices/**`, `family_hub_backend/src/i18n/locales/en/notices.json`,
`family_hub_backend/tests/notices.test.js`.

## Built
- [x] NOT-01 `GET /notices?page&limit`: paginated. Pinned notices come first, then newest first.
      The sort is `{ pinned: -1, createdAt: -1, _id: -1 }`, matching the model index. `_id` keeps pages stable
      when two notices have the same `createdAt`. The response is `paged` with `meta { page, limit, total, hasMore }`.
      A page past the end returns `[]`.
- [x] NOT-02 `POST /notices` → `201 Notice`.
  - Any member can post.
  - `pinned` is used only for admins. Members' `pinned` is silently ignored.
  - `imageUrl` must be an https URL on `res.cloudinary.com` (`nullableCloudinaryUrl`). `null` or blank means no image.
  - Unknown keys (`authorId`, `familyId`, `createdAt`, …) are stripped.
  - Push `notice` (fire-and-forget) goes to every other member with an account. Route `/notices`, channel `general`.
    - Keys: `notices.push.new.title` (or `.titlePinned` when an admin pins on creation) and `notices.push.new.body`.
    - Vars: `{ name, title }`. The title is shortened to 60 characters with `…`.
    - The notice **body** is never in the push (docs/08-COMPLIANCE.md row 20).
    - No push is sent when no one else in the family has an account.
- [x] NOT-03 `PATCH /notices/:id` → `Notice`. Allowed for the author or an admin.
  - Only the keys sent are changed. `imageUrl: null` or `''` removes the image. `title` and `body` can never be null.
  - `pinned` rules:
    - Changing it needs an admin: a member gets `403 FORBIDDEN` (`notices.errors.pinAdminOnly`), even on their own
      notice, and nothing is written.
    - Sending the **current** value is allowed, because the app sends full forms.
  - An empty or unchanged PATCH does not write and keeps `updatedAt`.
  - A notice deleted at the same time → 404.
- [x] NOT-03 `DELETE /notices/:id` → `data: null`. Allowed for the author or an admin. A repeat delete, or the loser of
      a concurrent delete, gets `404`.
- [x] Permission and error order: 401 → 403 `NO_FAMILY` → 400 (malformed id) → 422 (field `details`) → 404 (unknown id
      or another family's notice; existence is never revealed) → 403 (`notices.errors.editNotAllowed`).
- [x] `authorName` / `authorAvatarUrl` come from `memberDirectory` (one member query per request). They are `null`
      after the author leaves the family. The notice stays, and only admins can edit or delete it.
- [x] Exports for other modules:
  - `notices.serializer.js`: `serializeNotice(notice, members)`, `serializeNotices(list, members)`.
  - `notices.service.js`: `NOTICE_SORT`, `listLatestNotices(familyId, { limit = DASHBOARD_LIMITS.NOTICES, members? })`.
    This is for the dashboard's `latestNotices`: at most 3, pinned first. Pass `members` to reuse a member map.
- [x] NOT-04 `src/i18n/locales/en/notices.json`: `push.new.title|titlePinned|body`, `errors.editNotAllowed|pinAdminOnly`.
- [x] NOT-05 `tests/notices.test.js`: 41 tests, all green (63 after the hardening review below). They cover:
  - envelope and shape;
  - ordering and pagination (ties, boundaries, invalid page/limit);
  - the permission matrix (author, admin, other member, other family, no family, no token);
  - pin rules;
  - Cloudinary-only images (http, look-alike host, too long, not a URL);
  - title/body limits at 1/100 and 1/2000, plus Devanagari, Arabic and emoji text;
  - forged keys and malformed JSON or ids;
  - authors who left the family;
  - push audience and text: author, managed profiles and other families are excluded, English fallback, no body;
  - no-op PATCH, concurrent deletes, and the dashboard helper.

## Pending / handoffs
- [ ] **Translations**: `notices.json` for `hi bn ta te mr gu kn ml pa ar es fr pt de`. Until then pushes and errors
      fall back to English.
- [ ] **b-dashboard**: use `listLatestNotices(familyId, { members })` (or `serializeNotice`) for `latestNotices`, so
      the shape and order match `/notices`.
- [ ] **Shared helper**: the push title shortening reuses `pushTitle` exported from `modules/tasks/tasks.service.js`.
      It would be cleaner in `src/lib/`, e.g. `lib/text.js#shorten(text, max)`. That is for the b-core / b-tasks owners.
      If it moves, update the one import in `notices.service.js`.
- [ ] **GAP-02 (compliance)**: when a notice is deleted or its image is replaced or removed, the Cloudinary asset is
      not destroyed. `services/cloudinary.js` has no `destroy` helper yet (owner: b-core / uploads).

## Decisions / known issues
- There is no `GET /notices/:id`, because the contract doesn't list one. The app's edit screen pages the board instead
  (see f-notices.md). If one is wanted, update contract §9 first.
- `imageUrl` only needs the `res.cloudinary.com` host (contract §12, same as `me.avatarUrl`). The stricter
  `cloudinary.isFamilyAssetUrl` (family folder) is not enforced, so the app's mock seed image stays valid.
- `pinned: null` or a non-boolean `pinned` → 422. It must be a real JSON boolean.
- Lengths count UTF-16 code units, the same as the Mongoose model and the app's `String.length` validator
  (enforced explicitly since the hardening review: zod 4's `.max()` counts code points, see H-01 below).

## Hardening review (b-notices-harden, 2026-09-27)

Adversarial pass over authz, injection, mass assignment, text/Unicode, URLs, pagination, races, pushes
and payload size. Every finding has a test in the `hardening:` section of `tests/notices.test.js`
(the 9 tests marked *fails before* were run against the original code and failed there).

### Fixed
- **H-01 UTF-16 limits** (*fails before*): zod 4's `.max()` counts code points, the model counts UTF-16
  units. 51 emoji (102 units) passed zod and failed in Mongoose with its raw message, which echoes the
  input ("Path title (😀😀…, length 102) is longer than…"). Title and body now check `value.length` with
  the contract message, on POST and PATCH.
- **H-02 Invisible text** (*fails before*): `"\u200B"` (and other zero-width / format-only text) was a valid
  title or body. Both now need at least one letter, digit, symbol / emoji or punctuation character
  (`hasVisibleText`, same rule as task titles).
- **H-03 Control characters** (*fails before*): NUL, BEL, ESC and line breaks in titles were stored and
  pushed. The title is now one line: every run of control characters becomes one space. The body keeps
  `\n` / `\t`, turns CRLF / CR into LF and drops other controls. Uses `toSingleLine` / `toMultiLine`
  from `tasks.schemas.js`.
- **H-04 Ill-formed UTF-16** (*fails before*): a lone surrogate was echoed in the 201 response, but MongoDB
  stored U+FFFD, so the response differed from the stored notice and every re-send counted as a change.
  Text is now made well-formed first (`toWellFormed`).
- **H-05 imageUrl authority tricks** (*fails before*): `https://evil@res.cloudinary.com/…`,
  `https://u:p@…` and `https://res.cloudinary.com:8443/…` were accepted. They are now 422. Accepted URLs
  are stored in canonical WHATWG form, so `\` becomes `/`, the host is lowercased and spaces become `%20`.
  Any parser that reads the stored URL later then sees the same host. Dart's `Uri` was checked: it
  already agrees with WHATWG on the backslash case, so this was defence in depth, not an exploitable
  difference.
- **H-06 URL length after canonicalisation** (*fails before*): percent-encoding can push a URL shorter than
  1024 characters past the model limit. The 1024 check now runs on the canonical form and gives a clean
  422.
- **H-07 Push flooding** (*fails before*): each post pushes to the whole family, and the only limit was the
  global one (300 requests / min / IP, often shared by a whole home). New per-account limiter on
  `POST /notices`: `NOTICE_POST_RATE_LIMIT_PER_MINUTE = 10`. It runs before validation, so invalid bodies
  count too. Over the limit → `429 TOO_MANY_REQUESTS` + `retryAfterSeconds` + `Retry-After`. Tested in a
  child process with `RATE_LIMIT_IN_TEST=true`, because limiters are off in the normal test process.
- **H-08 `listLatestNotices` bounds** (*fails before*): a malformed family id threw a CastError (a 500 for
  the dashboard), and `limit` had no upper bound. It now returns `[]` for a non-ObjectId and caps `limit`
  at 100.
- Test robustness: the push tests now compare against `t(message.locale, …)` instead of hard-coded
  English, so they keep passing once `hi/notices.json` is translated.

### Verified, no change needed (regression tests added)
- Operator injection in the body (`{ $ne: null }`, arrays, `{ $regex }`, `pinned: { $ne: false }`) → 422
  on POST and PATCH.
- Top-level `$set` / `$unset` / `$rename` / `$where`, plus `familyId`, `authorId`, `_id`, `id`,
  timestamps and `__v`: stripped. A member cannot pin through `$set`. `__proto__` / `constructor`
  payloads have no effect.
- Query injection: `page[$gt]`, `limit[$ne]`, `familyId=<other>` and `authorId[$exists]` never widen
  the family scope.
- Pagination extremes:
  - `page=1e15` and `page=MAX_SAFE_INTEGER` → empty page, no 500.
  - `2^53+1`, `Infinity`, `NaN`, `-0`, a repeated `page` and a blank `limit` → 422.
- A member row deleted while the token is still valid → 403 `NO_FAMILY` on every route. An author who
  moved to another family gets 404 on their old notices, can't list them and no longer gets family A's
  pushes.
- PATCH racing DELETE: the delete succeeds once, every PATCH gets 200 or 404, and the notice never comes
  back (no upsert). Concurrent PATCHes of different fields don't overwrite each other (only changed keys
  are `$set`).
- Push language is chosen per recipient (device locale → account locale → English), never from the
  author's `Accept-Language`. Tested with temporary `hi` / `ar` catalogs.
- Push audience: the author, managed profiles and other families are excluded. The notice body is never
  in the push.
- A 150 kB body → 413 `PAYLOAD_TOO_LARGE`, nothing written or pushed.
- RTL text, bidi marks (LRM / RLM), Devanagari conjuncts and ZWJ emoji are kept exactly as typed.

### Decisions
- Bidi embedding / override characters are kept in notice text, unlike member names (`me.schemas.js`
  rejects them). Notices follow the task-text rule, because legitimate RTL / mixed-direction
  announcements may contain them.
- There is still no family-folder or cloud-name check on `imageUrl`: the app mock accepts any
  `res.cloudinary.com` URL, and so does the contract (§12).
- No server-side de-duplication of double submits: the contract has no idempotency key, and the app
  already guards against double taps and looks up an uncertain POST (f-notices-harden #4, #19).
- The per-account post limit lives in memory, per instance, like every limiter in
  `middleware/rateLimit.js`.
