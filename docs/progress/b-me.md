# b-me: backend "me" module (progress)

Owner: b-me. Scope: `family_hub_backend/src/modules/me/**`, `family_hub_backend/tests/me.test.js`.
Contract: docs/03-API_CONTRACT.md §5 (tasks SET-01 … SET-07), cascade rules of §6 and docs/04-DATA_MODELS.md §2.

## Built
- [x] `me.routes.js`: all 7 endpoints under `/me`. `requireAuth` covers every route. `requireFamily` is added on
      `PUT /location` and `POST /leave-family`. The order is auth → family → validation, so callers get 401, then
      403 NO_FAMILY, then 422.
- [x] `me.controller.js`: HTTP only. `GET /me/export` also sends `Cache-Control: no-store`.
- [x] `me.schemas.js`: zod bodies built from the shared blocks (`personName`, `nullablePhone`, `nullableCloudinaryUrl`,
      `locale`, `nullableGender`, `isoDate`, `latLng`, `nullableField`).
- [x] SET-01 `PATCH /me` → `{ user, member }`.
  - `name` updates both the account and the member. `locale` updates the account.
  - `phone`, `avatarUrl` (Cloudinary only), `locationSharing`, `gender` and `dateOfBirth` update the member. Sending
    `null` or a blank value clears a field; an absent key leaves it unchanged.
  - The body is **strict**: unknown keys such as `role`, `designation` or `email` get a 422 (`details.body`), the same
    as the Flutter mock.
  - Member fields without a family → `403 NO_FAMILY`. `name` and `locale` alone work without a family
    (the response then has `member: null`).
  - GAP-04: switching `locationSharing` to `never` or `sos_only` clears `lastLocation`.
  - GAP-05: a date of birth below the family country's consent age needs recorded guardian consent, otherwise
    `422 GUARDIAN_CONSENT_REQUIRED`. This reuses `assertMaySelfRegister` from auth.
  - The member is written before the user, so if the caller was removed at the same moment nothing is written.
- [x] SET-02 `PUT /me/location` → `{ recordedAt }`. The write only succeeds while `locationSharing = always`, checked
      in the same atomic update, else `403 LOCATION_SHARING_DISABLED`. Validation is lat −90..90, lng −180..180,
      accuracy ≥ 0, with no coercion (`"12"`, `null` and `true` are rejected).
- [x] SET-03 devices:
  - `POST /me/devices` → `{ registered: true }`. It upserts by token, and a token registered by another account
    moves to the caller.
  - When two first registrations of the same token race, the loser retries after the duplicate-key error.
  - If `locale` is absent, the device locale is stored as `null`, so pushes use the account locale.
  - Each account keeps at most `MAX_DEVICES_PER_USER = 10` devices; the ones seen least recently are pruned.
  - `DELETE /me/devices/:token` → `null`. It only deletes the caller's own token and is idempotent. A token that
    belongs to someone else gets the same answer and is left untouched, so its existence is not revealed.
    A malformed token in the path → 400.
- [x] SET-04 `GET /me/export` (`me.export.js`), `formatVersion: 1`. It contains:
  - `user`, with `consentAcceptedAt`, `lastLoginAt` and `updatedAt` added.
  - `member`, including the caller's own stored `lastLocation` and `guardianConsentAt`.
  - `family`, without the invite code.
  - `currency`.
  - `emergencyCard`, decrypted.
  - `tasks` the caller is assigned to, created or completed.
  - `ledgerEntries` the caller owns or created, as decimal amounts.
  - `notices` the caller wrote.
  - `sosAlerts` with their trails. Expired alerts are reported as `expired` without writing to the database.
  - `devices`, showing only the last 6 characters of each token.
  - `sessions`: IP, user agent and whether each is active.

  It never contains password, token or OTP hashes, `*Enc` blobs, the invite code or full device tokens. It works
  without a family (account data only).
- [x] SET-05 `DELETE /me { password }` → `null`.
  - A wrong password gives `401 INVALID_CREDENTIALS` and counts towards the login lockout (the 5th failure → 429).
    The right password clears the failure streak.
  - If the caller is the only member, the whole family is deleted.
  - If the caller is the last admin and other members exist → `409 LAST_ADMIN`, and nothing is deleted.
  - Otherwise the member cascade runs, then devices, refresh tokens, OTPs (by user id and e-mail) and the user are
    deleted.
- [x] SET-06 `POST /me/leave-family` → `{ user }` (no family). It uses the same LAST_ADMIN rule and the same cascade,
      and the last member leaving deletes the family. The caller **stays signed in**; sessions and devices are kept.
- [x] **`memberCascade.js`**, shared with b-family. Its exports:
  - `removeMemberCascade({ member, family?, actorId?, endSessions = true, now? })`. It:
    1. resolves the member's active SOS alerts (`resolvedById` = the actor, `resolution: null`) and marks stale
       ones `expired`;
    2. deletes the member's **pending** tasks and emergency card;
    3. deletes the member row;
    4. unlinks the user, and with `endSessions` deletes their refresh-token rows and devices;
    5. settles the family: with no members left the family is deleted; if the owner left, `ownerId` moves to the
       longest-standing admin; if a race left no admin who can sign in, the longest-standing member with an
       account is promoted.

    It returns a summary of what it did. It is idempotent and does not use transactions.
  - `assertNotLastAdmin(member, { leaving = true })`. Pass `leaving: false` for a demotion.
  - `removeSelfFromFamily({ member, family?, endSessions = false })`: dissolves the family when the caller is alone,
    otherwise checks LAST_ADMIN and runs the cascade.
  - `deleteFamilyCascade(familyId)`: deletes the family and all its collections, and unlinks its users.
  - `endUserSessions(userId)` and `lastAdminError()`.
- [x] SET-07 `tests/me.test.js`: 59 tests. They cover:
  - 401 on every route.
  - Happy paths for admin and member.
  - Clearing fields.
  - The strict body.
  - Every validation error (422 `details`) and 400 for a bad path parameter.
  - NO_FAMILY, GAP-04 and GAP-05.
  - Location sharing modes.
  - Device upsert, token move, races, the device cap, own-only delete and idempotency.
  - Export scope, decryption and absence of secrets.
  - Account deletion: family deletion, erasure, lockout, all three LAST_ADMIN cases, owner transfer, deleting with
    no family.
  - Leave-family: the cascade, sessions kept, the family deleted when the last member leaves, the old invite code
    rejected afterwards.
  - Concurrent leaves by two admins, and by the last two members.
  - Unit tests of the cascade functions.
  - Envelope shape in every assertion.

## Verified
- `cd family_hub_backend && node scripts/check-syntax.js`: 76 JS files and 2 JSON files, all OK.
- `node --test tests/me.test.js`: 59/59 pass (about 8.5 s). Four runs in a row were all green, including the
  concurrency tests.
- `node --test --test-concurrency=1 "tests/**/*.test.js"`: 295/295 pass (auth, core, emergencyCards, health, me).

## Pending / not in scope
- [ ] Cloudinary avatar deletion on account deletion (GAP-02). The contract has no endpoint for it and it needs the
      Cloudinary destroy API.
- [ ] Export for managed profiles by a guardian (GAP-08, `GET /family/members/:id/export`). `me.export.js` could be
      generalised to take a member if b-family wants it.
- [x] ~~No `sos_resolved` push is sent when the cascade resolves an alert.~~ Done by b-me-harden: the cascade now
      calls b-sos's exported `notifySosResolved` (see the hardening section below).
- [ ] Translations: no new i18n keys were needed. Only `common.errors.*` and `auth.errors.guardianConsentRequired`
      are used.

## Decisions / known issues
- **LAST_ADMIN counts only admins with an account.** A managed profile with `role: admin` cannot sign in, so it does
  not count as "another admin". This is stricter than a plain role count. The same function is offered to b-family
  so that demote, delete and leave agree.
- **Other members that are only managed profiles still trigger LAST_ADMIN** (the contract says "other members
  exist"). The contract only deletes the family when no other members remain, so a lone parent with managed child
  profiles must remove those profiles first. The app should explain this: the `LAST_ADMIN` message says "make someone
  else an admin".
- **SOS alerts closed by the cascade get `resolution: null`.** Nobody confirmed the person is safe, so the API does
  not claim it. The Flutter mock uses `safe`.
- **Sessions are ended by deleting refresh-token rows**, not by flagging them revoked. This matches b-auth: a flagged
  row would trigger reuse detection and kill any later session of the same user.
- **Leave-family keeps sessions and devices.** Pushes are routed through membership, so a user without a family
  receives none. Removal by an admin (`removeMemberCascade` default) ends sessions and removes devices, as contract
  §6 says.
- **`Family.ownerId` moves to the longest-standing remaining admin** when the owner leaves or deletes the account.
- **A family left without an admin through a race is repaired** by promoting its longest-standing member with an
  account (logged as a warning). This can only happen when two removals race past the LAST_ADMIN check, because
  transactions are not used.
- **The export never contains the invite code**, not even for admins. The file is meant to be saved or shared
  outside the app, and the invite code works as a join credential.
- **Device tokens:** printable ASCII without spaces, up to 4096 characters. At most 10 devices per account.
- **The `DELETE /me/devices/:token` answer is always `null`**, never 404, so it is idempotent and does not reveal
  whether a token exists.

## Hardening review (b-me-harden, 2026-09-27)

An adversarial pass over the module. Each issue has a test in the `hardening:` suites at the end of
`tests/me.test.js`. Result: 85 tests (59 → 85), all green.

### Issues found and fixed
- [x] **H1 · Race: two admins leaving together could strand the family.** `assertNotLastAdmin` reads and then acts, so
      two concurrent leaves both passed.
  - Reproduced: admins A and B plus a managed child; both `POST /me/leave-family` → `200, 200`. The family was left
    with only the child profile: no admin and nobody who can sign in, holding a minor's data.
  - Fix: new `claimAdminExit(member, { leaving })`. It runs the plain pre-check, then **claims** the exit with one
    conditional update (`role admin → member`), then checks again. If the check fails, the role is restored and the
    request gets `409 LAST_ADMIN`.
  - Whoever checks second sees the other request's claim, so both can never pass.
  - A 409 from either check is retried up to 3 times with a jittered pause of about 10–150 ms in total, so the
    ordinary case of the last two admins leaving together still ends with both `200` and the family deleted.
  - New `removeMemberGuarded` (the guard plus the cascade, with the role restored if the cascade throws). Both
    `removeSelfFromFamily` and b-family's `DELETE /family/members/:id` should use it.
  - `settleFamily` now samples the family a few times (≤ 150 ms, only when no admin is visible) before promoting
    anyone. An in-flight claim therefore no longer gets a regular member promoted by mistake.
- [x] **H2 · No `sos_resolved` push when the cascade closed an alert.** The family kept seeing an SOS that had ended.
  - The cascade now resolves each active alert with a conditional `findOneAndUpdate`, so an owner's own concurrent
    resolution wins.
  - It then calls `notifySosResolved` from b-sos after the member has been unlinked. The removed member is therefore
    never a recipient and the resolver is excluded.
  - Wording: self-leave uses `body.closed`; an admin removal uses `bodyByOther.closed` with the admin's name.
  - The push is localized per device and user locale.
  - No push for expired or already resolved alerts, or when the family is dissolved.
- [x] **H3 · Invisible and control-character names.** `"\u200B"`, `"a\u0000b"`, `"Amit\nSharma"` and
      `"\u202Enimda"` (shown as "admin") were accepted.
  - `PATCH /me` now uses `profileName`, which is `personName` plus three rules: no `\p{Cc}`; no bidi
    embedding/override/isolate controls (U+202A–E, U+2066–9); at least one visible character.
  - Arabic, Devanagari (with combining marks), CJK, emoji ZWJ sequences, and LRM/RLM inside a name are stored exactly
    as sent.
- [x] **H4 · `PUT /me/location` answered `403 LOCATION_SHARING_DISABLED` to a caller whose membership had just ended.**
      It now answers `403 NO_FAMILY`. The extra lookup only runs on the failure path.
- [x] **H5 · A device registration racing with `DELETE /me` left a push-token row for the deleted account.** That is
      personal data outliving the erasure until the 270-day TTL. `registerDevice` now checks that the user still exists
      after the upsert (else removes the row → 401). `DELETE /me` also sweeps sessions and devices again after the user
      row is gone.
- [x] **H6 · Erasure left the deleted person's precise location in the family's SOS history.** `DELETE /me` now clears
      `trail`, `lastLocation` and `lastLocationAt` of the caller's alerts.
  - The alert summary (who raised it and when, status, message) stays for the family.
  - `POST /me/leave-family` is not an erasure and keeps the history.
  - This is a decision beyond the contract text, based on docs/08-COMPLIANCE.md (erasure, GAP-03).
- [x] **H7 · `DELETE /me` with a 129-character password answered "Password is required".** zod 4 applied the type-level
      `error` to `max`. The message is now "Password is too long".

### Checked and fine (a test now pins each)
- NoSQL operators (`{"$ne":null}`, `{"$gt":""}`, `{"$in":[…]}`) in every body field → 422 with no coercion. Prototype
  keys (`__proto__`, `constructor`) sent as raw JSON → 422 `Unrecognized key`, and `Object.prototype` is untouched.
- Mass assignment on `PATCH /me` (`familyId`, `userId`, `memberId`, `role`, `guardianConsent*`, `hasAccount`,
  `emailVerified`, `lastLocation`, `savedMinor`, `passwordHash`, `id`, `_id`) → 422 and nothing written. On
  `POST /me/devices` an extra `userId` is dropped, so the device always belongs to the caller.
- Payloads over 100 kb → 413 `PAYLOAD_TOO_LARGE`. JSON arrays → 422. JSON scalars, `null` or malformed JSON → 400.
  All use the error envelope.
- Dates of birth:
  - Rejected: year 0000, expanded years, month 13, `2023-02-29`, hour 25, date-times without an offset, `+14:00`
    offsets that land in 1899 UTC, the future, numbers, booleans and arrays.
  - Accepted: leap days.
  - GAP-05 uses the family time zone at the birthday boundary, for IST (ahead of UTC) and Los Angeles (behind UTC). A
    person who turns 18 tomorrow in India is a minor although that local midnight is "today" in UTC. With `days + 1`
    the helper also crosses month ends on the last day of a month.
- Location: rejected are 1e13, -1e13, accuracy 1e13, `"NaN"`, a raw `NaN` token (400), arrays, operators and string
  accuracy. `0.1+0.2`, `-0` and `accuracy: 0` are stored as sent. A client `recordedAt` is ignored; the server time is
  used.
- `DELETE /me/devices/:token` with `%24ne`, JSON-looking, `.*` or NUL-suffixed paths, or 4097-character tokens never
  touches another user's row (400 or `null`).
- Export: removed co-members resolve to `null` names without failing. An admin's export has only the admin's own data.
- The `PATCH /me` response has exactly the contract `User` and `Member` keys. The lockout 429 carries a `Retry-After`
  header that equals `details.retryAfterSeconds`.

### For b-family (shared cascade API, updated)
- `DELETE /family/members/:id`: call `removeMemberGuarded({ member, family, actorId: req.user.memberId })` instead of
  `assertNotLastAdmin` + `removeMemberCascade`. The two can race; `removeMemberGuarded` cannot.
- Demoting an admin in `PATCH /family/members/:id`: `const guard = await claimAdminExit(target, { leaving: false })`
  **is** the demotion (don't write `role` yourself). If a later step of the same PATCH fails, call
  `await guard.release()`.
- `assertNotLastAdmin` stays exported as a read-only pre-check and is documented as not race-safe.

### Known limits (not fixed)
- Without transactions, a crash between the claim and its re-check leaves that admin demoted. At that point another
  admin existed, and `settleFamily` repairs a family without admins on the next removal.
- Under heavy contention a guard can still end in a 409 the client can retry. The tests accept that and assert the
  invariants: never zero admins, and no claim left behind.
- A sign-in whose bcrypt check overlaps the whole deletion can still insert one refresh-token row after the final
  sweep. It is useless (rotation rejects a missing user) and expires via TTL. Closing it needs a user re-check in
  `issueTokens` (b-auth).
- `GET /me/export` is unpaginated by design and loads everything into memory. That is fine for family-sized data.
- `POST /me/devices` moves a token to whoever registers it last (contract). A person who learned someone else's FCM
  token could divert that device's pushes. The API never reveals tokens (the export shows only a 6-character suffix).
