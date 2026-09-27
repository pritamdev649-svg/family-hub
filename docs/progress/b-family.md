# b-family: backend "family" module (progress)

Owner: b-family. Scope: `family_hub_backend/src/modules/family/**`, `src/i18n/locales/en/family.json`,
`tests/family.test.js`. Contract: docs/03-API_CONTRACT.md §6 (all but the emergency card), plus GAP-05 of
docs/08-COMPLIANCE.md.

## Built
- [x] `family.routes.js` replaces the placeholder. `requireAuth` covers every route. Order inside a route:
      401, then 403 (`NO_FAMILY`, or `FORBIDDEN` on admin-only routes), then 400 (malformed id), then 422 (body),
      then the service (404, 403, 422, 409).
- [x] `family.controller.js`: HTTP only (`ok` / `created`).
- [x] `family.schemas.js`: strict zod bodies built from the shared blocks. Names use auth's `displayName` (the same
      rules as register). It also defines `familyTimeZone` / `normalizeFamilyTimeZone`, based on
      `Intl.supportedValuesOf('timeZone')`, and `SELF_EDITABLE_FIELDS`.
- [x] `family.rules.js`: `loadFamily` (a family deleted in the meantime → `403 NO_FAMILY`), `needsGuardianConsent`,
      `assertGuardianConsent`, `guardianConsentError`, `memberEmailExistsError`, `isDuplicateKeyOn` and
      `sendMemberInvitation` (never throws).
- [x] `family.service.js`:
  - `POST /family` → `201 { user, family, member }`. Reuses `createFamilyForUser` from auth.onboarding: unique invite
    code, admin "Head of Family", `409 ALREADY_IN_FAMILY`. A stale membership counts as no family.
  - `POST /family/join` → `{ user, family, member }`. Reuses `joinFamilyForUser`:
    - codes are case-insensitive, and spaces and dashes are ignored;
    - it links the profile an admin pre-added with the same e-mail, keeping its name, role, designation and consent;
    - errors: `409 ALREADY_IN_FAMILY`, `400 INVALID_INVITE_CODE`, `409 MEMBER_EMAIL_EXISTS` (that profile already has
      an account), and `422 GUARDIAN_CONSENT_REQUIRED` (a pre-added minor without consent);
    - it sends the **`member_joined` push to the admins**.
  - `GET /family` → `{ family }`. `inviteCode` is shown to admins only; `memberCount` is computed.
  - `PATCH /family` (admin) → `{ family }`. Only changed fields are written; `{}` changes nothing. Country and
    currency are checked against lib/countries.js. The time zone must be in `Intl.supportedValuesOf`, or an alias ICU
    resolves to a listed zone (`Asia/Kolkata`), or UTC.
    - **GAP-05:** if a country change would leave members below the new consent age without guardian consent, the
      answer is `422 GUARDIAN_CONSENT_REQUIRED` with `details.memberIds`, `details.consentAge` and
      `details.country`, and nothing is changed.
  - `POST /family/invite-code` (admin) → `{ family }` with a new code; the old code stops working at once. A
    duplicate-key collision gets a new code (up to 8 tries, then 500).
- [x] `members.service.js`:
  - `GET /family/members` → `Member[]` in contract order: admins first, then oldest to youngest, unknown date of
    birth last. The `lastLocation` privacy rule applies (shared serializer).
  - `POST /family/members` (admin) → `201 Member`. The new member is a managed profile (`hasAccount: false`).
    - `role` defaults to `member`.
    - Rules: `GUARDIAN_CONSENT_REQUIRED` via `consentAge(country)`, with the age counted in the family time zone;
      `MEMBER_EMAIL_EXISTS` (case-insensitive, family-scoped).
    - Consent is recorded with `guardianConsentAt` and `guardianConsentById` (the admin's member id).
    - An e-mail address triggers the invitation e-mail `family.invite` with the invite code, in the **family
      creator's locale** (else the inviting admin's).
    - It also accepts an optional Cloudinary `avatarUrl`.
  - `GET /family/members/:id` → `Member`. Another family's member → 404; malformed id → 400.
  - `PATCH /family/members/:id` → `Member`.
    - An admin can change everything, including `role` and `guardianConsent`.
    - A non-admin can change only themselves (else 403). On their own profile they can change only `name, phone,
      avatarUrl, gender, dateOfBirth`; any other key → 403 with the denied keys in `details`.
    - Renaming yourself also renames the account.
    - Demoting uses the race-safe `claimAdminExit` → `409 LAST_ADMIN`.
    - The e-mail of a member **with an account** is their sign-in address. Changing it → 422 (the same value in any
      letter case is a no-op).
    - Giving a managed profile a new e-mail sends the invitation. A taken address → 409.
    - **GAP-05:** a change of date of birth, or withdrawing consent, must not leave a minor without consent → 422
      with `details.memberIds`.
  - `DELETE /family/members/:id` (admin) → `null`. It uses `removeMemberGuarded`, the shared cascade that is
    race-safe for LAST_ADMIN:
    - the user is unlinked and signed out everywhere, and their devices are removed;
    - their pending tasks and their emergency card are deleted;
    - their active SOS is resolved (with the `sos_resolved` push);
    - ledger entries stay;
    - `ownerId` moves to another admin if needed.

    An admin removing **themselves** = leaving the family (`removeSelfFromFamily`): the same LAST_ADMIN rule applies,
    they stay signed in, and the last member removing themselves deletes the family.
- [x] Join rate limit: 20 attempts per 15 min **per account** (`family-join` limiter, then 429 with
      `retryAfterSeconds`). It is on top of the global per-IP limiter and skipped in tests unless
      `RATE_LIMIT_IN_TEST=true`.
- [x] `src/i18n/locales/en/family.json` contains:
  - `email.invite.subject|text`;
  - `errors.guardianConsentRequired`, `errors.countryConsentRequired`, `errors.selfEditLimited` and
    `errors.accountEmailLocked`.
- [x] `tests/family.test.js`: 53 tests. They cover:
  - 401 on every route, the NO_FAMILY and FORBIDDEN matrix, and family isolation (404);
  - POST /family: create, 409, validation, time-zone aliases and rejections, stale and removed memberships;
  - join: normalised codes, the `member_joined` push, linking, `MEMBER_EMAIL_EXISTS`, `ALREADY_IN_FAMILY`, unknown
    and replaced codes, format checks, the age gate;
  - GET /family and PATCH /family, including GAP-05;
  - invite-code rotation and collision retry;
  - member list order and location privacy;
  - add member: shape, defaults, invitation locale, e-mail uniqueness, consent age including the local-birthday
    boundary, validation;
  - get member;
  - patch member: all fields, clearing fields, consent record, promote and demote, LAST_ADMIN (including a
    managed-profile admin), concurrent demotions, self-limited edits, account e-mail lock, invitation on a new e-mail,
    GAP-05, validation;
  - delete member: the full cascade, rejoining, managed profiles and other admins, removing yourself (LAST_ADMIN,
    ownership transfer, family dissolved), 404 and 400;
  - translations;
  - the envelope shape in every assertion.

## Verification
- `cd family_hub_backend && node scripts/check-syntax.js`: 113 JS files and 7 JSON files, all OK.
- `node --test tests/family.test.js`: 53/53 pass (about 18 s).
- `node --test --test-concurrency=1 "tests/**/*.test.js"`: 750/750 pass.
- Join limiter checked once with `RATE_LIMIT_IN_TEST=true` using a throw-away script: 20 × 409, then 429 with
  `Retry-After: 900`. Another account keeps its own budget.

## Pending / handoffs
- [ ] Translations of `family.json` into the other 14 locales (translation agents; same keys).
- [ ] b-core: move the family time-zone rule into the shared `timeZone` block. Today `POST /auth/register` still
      accepts `+05:30` and `Etc/GMT+5`, which `/family` rejects.
- [ ] b-core: add a shared `birthDate` block. auth, me and family each define the same date-of-birth rule.
- [ ] b-core: merge auth's `displayName` with me's `profileName`.
- [ ] docs owner (03-API_CONTRACT.md §6): document the additions listed under "Decisions".
- [ ] f-family (Flutter):
  - Handle `422 GUARDIAN_CONSENT_REQUIRED` on `PATCH /family` using `details.memberIds`.
  - Optionally send `avatarUrl` in `POST /family/members` instead of the follow-up PATCH.
  - Mock parity: GAP-05 checks, 422 for unknown keys, the account e-mail lock, and the invitation when an e-mail is
    set by PATCH.
- [ ] b-auth (optional): export `isDuplicateKeyOn` from auth.onboarding.js so family.rules.js can drop its copy.

## Decisions / known issues
- **Strict bodies.** Unknown keys give 422 (`locationSharing`, `userId`, `inviteCode`, `ownerId` …). Location sharing
  can only be changed by the member themselves through `PATCH /me`.
- **Non-admin self-edit of a disallowed field → 403 FORBIDDEN**, not 422. This matches the Flutter mock and repository.
- **GAP-05 is enforced** on a `PATCH /family` country change and on member date-of-birth changes or consent
  withdrawal. It is checked only when those fields change, so older data never blocks unrelated edits.
- **Invitation language:** the family creator's (owner's) locale, as the contract says. The fallback is the inviting
  admin's locale.
- **Invitation on PATCH:** also sent when a managed profile gets a new e-mail. There is no per-family e-mail rate
  limit, so an admin could re-send invitations by changing addresses (known issue).
- **Time zones:**
  - Node's `Intl.supportedValuesOf('timeZone')` lists ICU canonical names only. It lacks `Asia/Kolkata` and `UTC`,
    so aliases that ICU resolves to a listed zone are accepted as sent, and UTC aliases are stored as `UTC`.
  - Numeric offsets and `Etc/GMT±N` are rejected.
  - Listed zones are stored in their canonical spelling. An alias typed in the wrong case (`asia/kolkata`) is stored
    as sent, because ICU cannot give the alias's spelling. The app only sends exact names.
  - All 75 zones the app offers (`timezones.dart`) are accepted.
- **POST /family has no age gate.** The User model stores no date of birth, so a previously removed minor who creates
  their own family is not caught (`assertMaySelfRegister` gets `null`).
- **DELETE of yourself = leaving the family.** Sessions are kept, as with `POST /me/leave-family`. The app does not
  offer it.
- **The join limiter is in memory** (one instance). It counts all join attempts, not only failed ones.

## Hardening review (b-family-harden)

Adversarial review of this module. The baseline was 53/53 green. Each issue below was reproduced with a throw-away
probe (not in the project), then fixed and pinned by a test in the "family hardening" block of `tests/family.test.js`.
A mutation run confirmed that every one of those tests fails when its fix is removed.

### Issues found and fixed
- **H1 Race: withdrawing guardian consent vs. a date-of-birth change.** Two admins at once could leave a minor without
  consent. The probe hit this 10 times out of 10. Fix: `PATCH /family/members/:id` now writes with a conditional filter
  that pins the stored `dateOfBirth` and `guardianConsent` the check was based on. If either changed in the meantime,
  the service re-reads the profile and checks again (3 attempts, then `409 CONFLICT`).
- **H2 Race: changing a managed profile's e-mail while its account links.** The account e-mail lock was read-then-act.
  Fix: an e-mail change writes only while `userId` is still null. Otherwise it re-checks and answers `422` (sign-in
  e-mail).
- **H3 Race (GAP-05): a country change vs. adding a member or changing a date of birth.** Fix: `PATCH /family`
  re-scans the members after its write and undoes the change (only while the family still holds the values it wrote),
  answering `422 GUARDIAN_CONSENT_REQUIRED` with `details.memberIds`. `POST /family/members` and member date-of-birth or
  consent changes re-read the family after their write. If the country or time zone changed and the member now needs
  consent, the new row is deleted or the edit is undone, and the answer is `422`. Because each side reads after it
  writes, at least one of two racing requests always sees the other.
- **H4 A removed member could rejoin at once with the invite code they already knew.** Fix: `DELETE
  /family/members/:id` gives the family a new invite code when the removed member had an account. The rotation is shared
  with `POST /family/invite-code` through `rotateInviteCode` in family.rules.js. Removing a managed profile, or an admin
  removing themselves (leaving), keeps the code.
- **H5 Profile takeover through an unverified e-mail.** Members can read every e-mail address in the member list. Anyone
  holding the invite code could open an account with a pre-added profile's address (including an admin profile) and
  `POST /family/join` would link it. The probe got `role: admin` this way. Fix: an account with an unverified address is
  not linked (`403 FORBIDDEN`, `family.errors.verifyEmailToLink`). It can still join as a new member when no profile
  matches. The same hole is still open on `POST /auth/register` (join mode); see handoffs.
- **H6 Unlimited invitation e-mails.** An admin could send invitations to any address without limit; the probe sent 60
  in one go. Fix, in-memory like the other limiters:
  - per family: 20 invitations per hour. The budget is reserved atomically before the write, so parallel bursts are
    capped too. When it is used up, the answer is `429 TOO_MANY_REQUESTS` with `details.retryAfterSeconds` and nothing
    is written.
  - per recipient address, across all families: 3 per 24 hours. Further invitations are skipped silently, so a sender
    learns nothing about other families. Addresses are kept only as sha256 hashes in memory.
- **H7 Unbounded family size.** The probe added 213 profiles, and every family request loads the whole member list.
  Fix: at most `MAX_FAMILY_MEMBERS = 100` members. Over the limit the answer is `409 CONFLICT`, with `details.limit` and
  the message `family.errors.memberLimitReached`. The limit is also enforced after the write: under concurrent adds,
  the members written first (smaller ids) keep their place.
- **H8 Text edge cases.**
  - Lone UTF-16 surrogates in names and designations were accepted, and MongoDB stored them as U+FFFD, so the saved text
    differed from the response. They are now rejected with 422.
  - Designations are now stored in NFC.
  - A designation made only of invisible characters (zero-width space, Hangul filler, Braille blank …) counts as blank
    and is stored as `null`.

### Attacks checked and already handled (now pinned by tests)
- Operator objects (`{"$ne": null}`) in any body field or id → 422 / 400.
- `__proto__` and `constructor` keys → 422 (strict bodies).
- Array bodies → 422.
- Upper-case or space-padded ids are accepted; malformed ids → 400.
- Concurrent `POST /family` and `POST /family/join` by one account → exactly one succeeds; the rest get 409 and nothing
  is orphaned.
- Concurrent adds with the same e-mail → one 201, the rest 409.
- Checked in the probe:
  - huge bodies → 413;
  - dates: far past or future, extended years, numbers → 422;
  - `guardianConsent: 1` → 422;
  - numeric time-zone offsets → 422.

### Decisions
- Rotating the code on removal makes pending invitation e-mails to other profiles stale; the admin shares the new code.
  Nothing is re-sent automatically. The app already refreshes `DataScope.family` after a removal, so the new code shows.
- The code is rotated after the cascade, so a failed removal changes nothing. This leaves a window of a few
  milliseconds in which the removed person could still use the old code.
- A time-zone-only change does not re-check consent. It can move a member's age by at most one day around a birthday,
  and that corrects itself.
- The limits are per API instance (in memory) and reset on restart, like express-rate-limit's memory store.

### Handoffs from the review
- [ ] b-auth: `POST /auth/register` (join mode) still links a pre-added profile to an **unverified** account, which is
      the same takeover as H5. Options: link only after `verify-email`, or refuse to link at register time.
- [ ] b-auth: in `joinFamilyForUser`, add `email: user.email` to the link filter (a profile whose e-mail an admin just
      changed must not be linked).
- [ ] b-auth: apply `MAX_FAMILY_MEMBERS` (exported from family.rules.js) to joins.
- [ ] b-auth / b-core: add the well-formed check (`String.prototype.isWellFormed`) to the shared `displayName`,
      `personName` and free-text blocks, so every module rejects lone surrogates. family.schemas.js can then drop its
      local refine.
- [ ] docs owner (03-API_CONTRACT.md §6): document H4 (code rotation), H5 (403 on /family/join), H6 (429 plus the silent
      per-recipient cap), H7 (409 CONFLICT, `details.limit`), the `409 CONFLICT` for a member that keeps changing during
      a PATCH, and the H8 text rules.
- [ ] f-family: mock parity for H4–H8. Optionally, a hint after removing a member ("the invite code was changed").
- [ ] Translation agents: new keys `family.errors.memberLimitReached` and `family.errors.verifyEmailToLink`.
