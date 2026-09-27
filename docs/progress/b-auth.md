# b-auth: backend auth module (progress)

Owner: b-auth. Scope: `family_hub_backend/src/modules/auth/**`, `src/i18n/locales/en/auth.json`, `tests/auth.test.js`.
Contract: docs/03-API_CONTRACT.md §4 (tasks AUTH-01 … AUTH-10).

## Built
- [x] `auth.routes.js`: all 10 endpoints under `/auth`. `authLimiter` is on register, login, forgot-password and
      reset-password. `/refresh` has its own limiter (60/min/IP) because every device refreshes every 15 min and
      many devices can share one carrier-NAT address. `requireAuth` protects logout, verify-email,
      resend-verification, change-password and me.
- [x] `auth.controller.js`: HTTP only. It reads `req.valid`, passes `{ locale, meta: { ip, userAgent } }` and answers
      with `ok` / `created`.
- [x] `auth.schemas.js`: zod bodies built from the shared blocks (`email`, `password`, `personName`, `locale`,
      `countryCode`, `currencyCode`, `timeZone`, `inviteCode`, `isoDate`, `nullableField`).
      - `consentAccepted` must be `true`.
      - New passwords must be 72 UTF-8 bytes or less (bcrypt ignores the rest).
      - The date of birth cannot be in the future or before 1900.
      - The OTP must be 6 digits. Spaces and dashes are ignored.
      - The new password must differ from the current one.
      - The field that belongs to the other mode (`inviteCode` on create, `family` on join) is ignored.
- [x] AUTH-01 register:
  - **create**: Family with a unique invite code (it retries on a duplicate key) and an admin Member called
    "Head of Family".
  - **join**: a new `member`, **or a link** to a member that an admin pre-added with the same e-mail and no account.
    The link keeps the name, role, designation and consent of that profile, and fills in a missing date of birth.
  - 409 `EMAIL_TAKEN`, 400 `INVALID_INVITE_CODE`, and 409 `MEMBER_EMAIL_EXISTS` when the profile with that e-mail
    already has an account.
  - Checks that need no writes run first. If a later step fails, the account, family and member are rolled back.
    The code does not depend on transactions.
  - `consentAcceptedAt` is stored. The locale comes from the body, else Accept-Language, else `en`.
  - The verification OTP e-mail is sent in the user's locale.
  - On join, the family admins get a `member_joined` push (`auth.push.memberJoined.*`, route `/members/:id`).
- [x] Age gate (docs/08-COMPLIANCE.md GAP-01): a person younger than `consentAge(country)` gets
      `422 GUARDIAN_CONSENT_REQUIRED` (`details.consentAge`, localized `auth.errors.guardianConsentRequired`).
      This applies to both modes. The exception is a link to a pre-added profile that has `guardianConsent: true`.
- [x] AUTH-02 login:
  - A wrong password or an unknown e-mail gives the same 401 `INVALID_CREDENTIALS`. Both cost the same bcrypt work.
  - Lockout: 5 failures within 15 min (the window starts at the first failure) lock the account for 15 min. The 5th
    failure already answers `429` with `details.retryAfterSeconds` and a `Retry-After` header. While the lock lasts,
    even the correct password gets 429.
  - Unknown e-mails are locked the same way through a bounded in-memory map, so the lockout does not reveal whether
    an account exists.
  - A successful login clears the counters, sets `lastLoginAt` and upgrades a hash with a lower cost.
  - A stale membership is reported as `familyId: null`.
- [x] AUTH-03 refresh: `rotateRefreshToken` (rotation and reuse detection in services/tokens.js).
- [x] AUTH-04 logout: revokes the caller's refresh token and deletes the caller's `deviceToken`. It never touches
      another user's token or device. It is idempotent and returns `data: null`.
- [x] AUTH-05 verify-email and resend-verification:
  - OTP: 6 digits from `randomDigits`, valid 10 min.
  - It is stored as a sha256 hash that is tied to the e-mail and purpose and peppered with a server secret. It is
    single use.
  - Every check counts atomically. 5 wrong codes give `INVALID_OTP`; after that, or when the code expired or was
    never requested, the answer is `OTP_EXPIRED`.
  - Resend has a 60 s cooldown, enforced atomically by the unique `{email, purpose}` upsert → `429` with
    `retryAfterSeconds`.
  - verify-email is idempotent once the e-mail is verified.
- [x] AUTH-06 forgot-password and reset-password:
  - forgot-password always answers `{ sent: true }`.
  - Unknown e-mails get a **decoy** code row that is never sent, so reset-password gives exactly the same answers
    for known and unknown addresses (INVALID_OTP ×5, then OTP_EXPIRED).
  - Inside the cooldown nothing is re-sent.
  - A successful reset sets the password, clears the lockout, marks the e-mail verified and ends **all** sessions.
- [x] AUTH-07 change-password:
  - It checks the current password. A wrong one gives 401 `INVALID_CREDENTIALS` and counts towards the lockout.
  - It ends all sessions and issues a fresh pair for the calling device: `{ changed: true, tokens }`.
- [x] AUTH-08 me: `{ user, member|null, family|null }`. Only admins get `inviteCode`. `memberCount` is computed.
- [x] `auth.onboarding.js`: reusable parts.
  - `createFamilyForUser`, `joinFamilyForUser`, `planJoin`, `findFamilyByInviteCode`,
    `createFamilyWithUniqueCode`, `assertMaySelfRegister`, `notifyMemberJoined`.
  - `findMembership`, `serializeAccount`, `serializeSession`, `loadSession`.
  - These are written so that `POST /family` and `POST /family/join` can reuse them.
- [x] `auth.otp.js` (`issueOtp`, `consumeOtp`, `discardOtp`) and `auth.passwords.js` (bcrypt cost 12 / 10 in tests,
      constant-work `verifyPassword`, lockout helpers).
- [x] AUTH-09 `src/i18n/locales/en/auth.json`:
  - `email.verifyEmail|resetPassword.subject|text` (templates `auth.verifyEmail` and `auth.resetPassword`).
  - `push.memberJoined.title|body`.
  - `errors.guardianConsentRequired`.
- [x] AUTH-10 `tests/auth.test.js`: 88 tests. They cover:
  - Envelope and shapes, and that no secrets appear in responses.
  - Both register modes, linking, the cross-family link guard, consent, the age gate, duplicate e-mail, and
    invite-code retry.
  - Full validation matrix.
  - Lockout: known and unknown e-mails, the 15-min window, reset on success.
  - Refresh rotation, reuse and expiry.
  - Logout scoping.
  - OTP expiry, attempts, cooldown, single use and legacy rows.
  - Reset: no enumeration, revokes sessions, decoy safety.
  - Change password.
  - me for admin, member, no family and family isolation.
  - Translations.

## Verified
- `cd family_hub_backend && node scripts/check-syntax.js`: 66 JS files and 2 JSON files, all OK.
- `node --test tests/auth.test.js`: 88/88 pass (about 10 s).
- `node --test --test-concurrency=1 "tests/**/*.test.js"`: the whole suite passed (189/189) before the last 2 auth
  tests were added.

## Pending / not in scope
- [ ] Translations of `auth.json` for the other 14 locales (translation agents; same keys).
- [ ] The contract (§4) does not yet document the deviations below (docs owner, handoff).
- [ ] The Flutter app must store the `tokens` returned by change-password (handoff).
- [ ] Rate limiters are skipped in tests (`RATE_LIMIT_IN_TEST`), so the limiter wiring is not covered by tests.

## Decisions / known issues
- **Sessions are ended by deleting rows.** Reset and change-password delete the user's refresh-token rows instead
  of flagging them revoked. `services/tokens.js` treats *any* revoked token as reuse and then revokes everything.
  With flagged rows, a stale device refreshing after a reset would also kill the session the user just opened.
  Deleted rows give a plain `401 INVALID_REFRESH_TOKEN`. A test covers this.
- **change-password returns tokens.** It returns `{ changed: true, tokens }`, a superset of the contract. The old
  refresh tokens are gone, so a client that ignores `tokens` is signed out at its next refresh.
- **resend-verification when already verified** returns `{ sent: false, retryAfterSeconds: 0 }` and sends no mail.
- **The 5th failed login answers 429**, not 401, so the app can show the lockout time at once.
- **change-password and login share one lockout counter.** Wrong current passwords count too, which protects
  against a stolen access token.
- **reset-password also marks the e-mail verified**, because the code proved access to the inbox.
- **Unknown-e-mail lockout counters live in memory.** They are per API instance and hold at most 10k entries. With
  several instances, an attacker gets up to 5 tries per instance.
- **Unverified users can reach the API.** That is by contract; the app gates the UI. A person who knows the invite
  code and a pre-added member's e-mail could register with that e-mail and link to the profile before verifying it.
  Mitigation idea: link only after `verify-email`, or require verification for family endpoints. Needs a product
  decision.
- **Unknown body keys are stripped, not rejected.**
- **Validation `details` messages are English.** This is the shared convention from b-core. The top-level
  `message` is localized.

---

## Hardening review (b-auth-harden, 2026-09-27)

An adversarial review of this module: probe first, then fix. Every finding has a regression test in the
`hardening:` suites at the end of `tests/auth.test.js`. The suite now has **126 tests**, up from 88.
Where this section disagrees with the sections above, this section wins (the 60 s cooldown and the
`logout` wording changed).

### Fixed
- [x] **Lockout bypass with parallel requests (high).** 12 parallel wrong logins tested 8+ passwords
      where 5 should be the limit. The correct password could also get in during the burst. The
      attempt is now reserved atomically *before* bcrypt runs (`reserveLoginAttempt` /
      `checkPasswordWithLockout` in `auth.passwords.js`). Result: exactly 4 × 401, then 429.
      Change-password shares the same counter.
- [x] **Unknown-e-mail lockout could be erased by in-flight requests.** This showed up as a difference
      from real accounts, which leaks whether an e-mail exists. The unknown-e-mail check now uses the
      same reservation logic (`reservePhantomAttempt` / `failPhantomAttempt`). Known and unknown
      e-mails give the same answers under a parallel burst.
- [x] **OTP brute force through unlimited re-issue (high).** "5 wrong guesses, new code after 60 s"
      allowed about 7,200 reset-code guesses per day per address. That is roughly a 0.7 % chance per
      day to take over an account through `reset-password`. The resend cooldown is now
      `max(60 s, wrong guesses on the current code × 3 min)`, which caps guessing at 5 per 15 min, the
      same rate as the login lockout. A code that was never mistyped keeps the plain 60 s. Issuing a
      code uses an optimistic, race-safe update: 3 parallel resends send exactly 1 e-mail.
      Decoy rows for unknown e-mails follow the same rule.
- [x] **A refresh loop survived a password reset (high).** An attacker refreshing a stolen token in a
      loop kept a live session after the victim reset the password (reproduced). The cause is a
      reset between `rotateRefreshToken`'s lookup and its insert. `refreshSession`
      (`auth.sessions.js`) now checks after the rotation that the old row still exists. If it is
      gone, the new token is deleted and the call answers 401.
- [x] **Logout replay signed the user out everywhere.** Logout flagged the token as revoked, so any
      later replay of it (for example a background refresh that was still in flight) set off reuse
      detection and ended every device's session. Logout now **deletes** the token.
- [x] **Logout with an already-rotated token left its successor alive.** This happens when the app
      lost a refresh response and then logs out with the old token. Logout now deletes the token and
      every token rotated from it (`endDeviceSession`). A chain longer than 50 hops is treated as
      theft and ends every session.
- [x] **"Password changed" notice e-mail (OWASP ASVS 2.2.3).** Sent after reset-password and
      change-password, in the user's locale, with no code in it. New keys:
      `auth.email.passwordChanged.subject|text`.
- [x] **Names:** control characters (`\n`, NUL, tab), bidi embedding/override/isolate characters
      (the "Trojan Source" spoofing trick seen in pushes and e-mails) and blank-looking names (zero-width
      characters, Hangul filler) were accepted. The new `displayName` schema (`auth.schemas.js`) is used
      for the register name and `family.name`. It is NFC-normalised and rejects those characters. All
      scripts, emoji and ZWJ/ZWNJ sequences, and LRM/RLM stay allowed (tested with Arabic, Devanagari,
      Bengali, Gurmukhi, Tamil, Telugu, Kannada, Malayalam and CJK names, plus emoji families).
- [x] **Passwords are Unicode-normalised (NFKC, NIST 800-63B).** A password registered with
      composed "é" failed to log in when typed as "e" + combining accent (reproduced). Full-width IME
      digits did not count as digits. The rules, the 72-byte bcrypt limit, hashing and comparing all
      use the NFKC form now.
- [x] **One-time codes and invite codes typed with native digits** (Arabic-Indic, Persian,
      Devanagari, Bengali, Gurmukhi, Gujarati, Tamil, Telugu, Kannada, Malayalam, Odia, full-width) got
      422 before. They are now mapped to ASCII (`toAsciiDigits`). The OTP input is capped at 64
      characters.
- [x] **Register ordering:** joining with an e-mail that already has an account answered
      `MEMBER_EMAIL_EXISTS`, and a bogus invite code answered `INVALID_INVITE_CODE`. Both now answer
      `409 EMAIL_TAKEN` ("log in instead"). No new information leaks, because create mode already
      revealed it.
- [x] **Stale membership blocked create/join forever** (onboarding helpers meant for `POST /family` and
      `/family/join`). A user whose `familyId` points to a deleted member row is "no family" for
      `requireAuth`, but `createFamilyForUser` / `joinFamilyForUser` answered `ALREADY_IN_FAMILY`.
      These users are now accepted: the stale id is replaced atomically, and a real membership still
      gets 409.
- [x] **Link race:** if an admin deleted a pre-added profile while someone was being linked to it, the
      answer was a false `409 MEMBER_EMAIL_EXISTS`. The person now joins as a new member, and the age gate
      is re-checked without the deleted profile's guardian consent.

### Probed and found safe (tests added)
- NoSQL operators in every auth body give 422 before any database access. Mass assignment of
  `role`, `familyId`, `memberId`, `emailVerified`, `designation`, `guardianConsent`, `passwordHash` and
  `ownerId`/`inviteCode` is stripped. Raw-JSON `__proto__` / `constructor` do not pollute prototypes.
- Forged, foreign-issuer/audience, `alg: none`, non-ObjectId-`sub` and dangling-user JWTs give 401.
  Expired tokens give `TOKEN_EXPIRED`.
- Wrong JSON types give 422. Malformed JSON gives 400. A 200 kB body gives 413. Over-long
  names, e-mails, passwords, refresh tokens and OTPs give 422.
- Dates: impossible dates, 13th months, date-times without an offset, dates before 1900 and future
  dates are rejected. The consent-age birthday boundary is evaluated in the family time zone, where
  local midnight is sent as UTC.
- Races: two parallel registrations with one e-mail give one 201 and one `EMAIL_TAKEN`, with no
  orphan family or member left. Two people claiming one pre-added profile: one wins and nothing is
  left dangling.
- `member_joined` goes only to this family's admins, in each device's language, falling back to the
  user's locale.

### Still open (need other owners / a product decision) — see handoffs in the b-auth-harden report
- [ ] **Profile takeover before verification (high, product).** Anyone with the invite code and a
      pre-added member's e-mail can register, get linked, and inherit that profile's role (possibly
      **admin**) without ever verifying the e-mail. Proposed fix: `requireFamily` (b-core) answers
      `403 EMAIL_NOT_VERIFIED` for unverified users (a new contract code). The app already forces the
      verify screen, so honest users see no difference.
- [ ] `services/tokens.js` (b-core): claim-failure / revoked-by-logout tokens → revoke-all. See handoff.
- [ ] Access tokens stay valid for up to 15 min after reset, change password or logout (by design of
      the stateless JWT). Closing this needs a `User.sessionsValidAfter` field (b-models) checked
      against `iat` in `requireAuth` (b-core).
- [ ] `me.service.deleteAccount` still uses the post-check pattern (`assertNotLocked` + `verifyPassword`
      + `failPasswordCheck`), so parallel guesses there bypass the lockout. It should switch to
      `checkPasswordWithLockout(user, password)` (b-me). The old helpers are kept so me keeps working.
- [ ] Translations of `auth.email.passwordChanged.*` for the other 14 locales. English is the fallback.
