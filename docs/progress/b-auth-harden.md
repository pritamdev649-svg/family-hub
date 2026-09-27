# b-auth-harden: adversarial review of the backend auth module

Owner: b-auth-harden. Scope, the same files as b-auth: `family_hub_backend/src/modules/auth/**`,
`src/i18n/locales/en/auth.json`, `tests/auth.test.js`. The full list of findings and fixes is in
`docs/progress/b-auth.md`, section "Hardening review".

## Method
1. I read the contract (§4), the backend guide and all of `modules/auth`, plus the shared helpers it
   uses (`services/tokens.js`, `middleware/auth.js`, `lib/validate.js`, models).
2. A scratch probe suite attacked the running API with parallel logins, OTP re-issue, logout/refresh
   replay, a refresh loop during a reset, operator injection, mass assignment, Unicode/RTL names and
   passwords, native digits, forged JWTs and huge payloads.
3. For every confirmed issue I wrote a fix and a regression test (`hardening:` suites in
   `tests/auth.test.js`).

## Built / fixed
- [x] Race-safe login lockout: the attempt is reserved before bcrypt runs. Covers login and
      change-password, and unknown e-mails use the same logic.
- [x] Unknown-e-mail ("phantom") lock can no longer be erased by requests still in flight.
- [x] OTP brute-force bound: resend cooldown = max(60 s, wrong guesses × 3 min), and the reissue is
      race-safe.
- [x] New `auth.sessions.js`:
  - `refreshSession` checks after the rotation that the session was not wiped meanwhile, so a refresh
    loop cannot survive a password reset.
  - `endDeviceSession`: logout deletes the token and everything rotated from it.
  - `endAllSessions`: ends every session of the user.
- [x] "Password changed" notice e-mail after reset and change (new en keys).
- [x] `displayName` schema: NFC, no control or bidi-override characters, must contain a visible
      character. Used for the user name and `family.name`.
- [x] Passwords are NFKC-normalised for the rules, the 72-byte limit, hashing and comparing.
- [x] Native and full-width digits are accepted in OTPs and invite codes.
- [x] `EMAIL_TAKEN` takes precedence over the family checks on register.
- [x] Onboarding helpers accept users whose membership is stale, and fall back when a pre-added
      profile is deleted while the link is being made.
- [x] 38 new tests (126 in total), all green and stable over 4 consecutive runs.

## Pending (other owners)
- [ ] Gate family endpoints on `emailVerified` to close the pre-added profile takeover (b-core + docs;
      product decision).
- [ ] `services/tokens.js`: do not revoke-all when the row was deleted or logged out (b-core).
- [ ] Revoke access tokens on reset or logout (`User.sessionsValidAfter`: b-models + b-core).
- [ ] `me.service.deleteAccount` → `checkPasswordWithLockout` (b-me).
- [ ] Shared `personName` / `email` blocks: adopt the `displayName` rules and punycode IDN domains
      (b-core).
- [ ] `auth.email.passwordChanged.*` in the 14 other locales (translation agents).
- [ ] Contract §4 notes for the new behaviour (docs owner).

## Known issues
- Unknown-e-mail lockout counters are still per API instance (in memory, at most 10k entries).
- Login does a few more DB writes for real accounts than for unknown e-mails, which adds about 1 ms
  next to a bcrypt compare of about 250 ms. Accepted.
- Passwords hashed before this change from non-NFKC input would no longer match. Nothing is deployed
  yet, so no migration is needed.
