# b-family-harden: adversarial review of the backend "family" module

Scope (same as b-family): `family_hub_backend/src/modules/family/**`, `src/i18n/locales/en/family.json` and
`tests/family.test.js`. The details of each finding (H1–H8), the decisions and the handoffs are in
`docs/progress/b-family.md` under "Hardening review (b-family-harden)".

## Done
- [x] Read the contract (§1, §2, §4, §6, §12, §13), the backend guide, docs/08-COMPLIANCE.md (GAP-01, GAP-05), the
      builder's code and tests, and the shared helpers the module uses (onboarding, memberCascade, validate, access,
      serializers, mailer, rate limiter). The baseline was 53/53 green.
- [x] Probed every route with a throw-away script (not committed). It covered:
  - operator injection and prototype keys, mass assignment, array bodies, malformed or upper-case ids;
  - huge bodies, unicode / RTL / emoji and lone surrogates, date and number edge cases, time-zone spellings;
  - concurrent create/join, concurrent adds, consent races, removal and rejoin, unverified linking, invitation spam,
    family size.
- [x] H1: race-safe guardian consent on `PATCH /family/members/:id`. The conditional write pins the stored date of birth
      and consent; if they changed, the profile is re-read and checked again (`409 CONFLICT` after 3 attempts).
- [x] H2: race-safe account e-mail lock. An e-mail change writes only while the profile has no account.
- [x] H3: race-safe GAP-05 across documents. Each side re-checks after its write and undoes it on conflict:
      `PATCH /family` re-scans members, while add member and member DOB/consent edits re-read the family.
- [x] H4: removing a member with an account rotates the invite code. `rotateInviteCode` is shared with
      `POST /family/invite-code`.
- [x] H5: `POST /family/join` links a pre-added profile only to an account with a verified e-mail
      (`403 FORBIDDEN`, `family.errors.verifyEmailToLink`).
- [x] H6: invitation limits.
  - Per family: 20 per hour, reserved atomically; over the limit → `429 TOO_MANY_REQUESTS` before any write.
  - Per recipient address: 3 per 24 hours across families; further invitations are skipped silently.
- [x] H7: at most 100 members per family (`409 CONFLICT`, `details.limit`). The limit is re-checked after the write,
      and the members written first win.
- [x] H8: names and designations reject lone surrogates. Designations are stored in NFC, and an invisible-only
      designation becomes `null`.
- [x] Two new English keys in `family.json`: `errors.memberLimitReached` and `errors.verifyEmailToLink`.
- [x] Tests:
  - 15 new tests in the "family hardening (adversarial review)" block, one per issue plus pins for attacks that were
    already handled;
  - deterministic race tests through `withConcurrentWrite`, which injects the concurrent write between a service's
    check and its write;
  - 3 existing tests updated to the new behaviour: verified linking, and rejoining after removal needs the new code.
- [x] Mutation check: each fix was disabled in turn, and the matching test failed every time.
- [x] Appended the findings, decisions and handoffs to `docs/progress/b-family.md`.

## Pending / handoffs (files I do not own)
- [ ] b-auth: `POST /auth/register` in join mode still links a pre-added profile to an unverified account (the same
      takeover as H5).
- [ ] b-auth: add `email: user.email` to the link filter of `joinFamilyForUser`.
- [ ] b-auth: apply `MAX_FAMILY_MEMBERS` to joins.
- [ ] b-auth / b-core: add the well-formed (lone surrogate) check to the shared `displayName`, `personName` and
      free-text blocks.
- [ ] docs owner (03-API_CONTRACT.md §6): document H4–H8 and the `409 CONFLICT` for a member edited concurrently.
- [ ] f-family: mock parity for H4–H8 (new invite code after a removal, 403 for unverified linking, 429 invitation
      budget, 409 family size, designation rules).
- [ ] Translation agents: `family.errors.memberLimitReached` and `family.errors.verifyEmailToLink` in the 14 other
      locales.

## Known issues
- The invitation limits are kept in memory, per API instance, and reset on restart (like the other limiters).
- A removed member could still use the old code during the few milliseconds between the removal cascade and the code
  rotation.
- Rotating the code makes other pending invitation e-mails stale; the admin shares the new code.
- A time-zone-only change of the family does not re-check guardian consent. The age can move by at most one day around
  a birthday, and that corrects itself.
- Unchanged from b-family: a time-zone alias typed in the wrong case (`asia/kolkata`) is stored as typed.

## Verification
- `node scripts/check-syntax.js` → all OK (117 JS files, 7 JSON files).
- `node --test tests/family.test.js` → 68/68 pass.
- Mutation run (throw-away script): each of the 12 fixes was disabled in turn → at least one hardening test failed
  each time; the files were restored and diff-checked afterwards.
- `node --test --test-concurrency=1 "tests/**/*.test.js"` → 812 tests: 810 pass, 0 fail, 2 `todo` (in other
  modules), about 137 s.
