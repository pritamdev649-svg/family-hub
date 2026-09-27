# b-me-harden: adversarial review of the backend "me" module

Scope (same as b-me): `family_hub_backend/src/modules/me/**` and `family_hub_backend/tests/me.test.js`.
The details of each finding are in `docs/progress/b-me.md` → "Hardening review".

## Done
- [x] Read the contract (§1, §2, §5, §6, §10, §13), the backend guide, docs/08-COMPLIANCE.md and the builder's code
      and tests. The baseline was 59/59 green.
- [x] Probed every route with a throw-away script (not committed). It covered operator injection, prototype keys,
      mass assignment, unicode/control/RTL names, huge and malformed bodies, numeric and date edge cases, stale
      sessions, account-deletion races and concurrent LAST_ADMIN.
- [x] H1: race-safe LAST_ADMIN. `claimAdminExit` claims with a conditional update, re-checks and retries on
      contention. `removeMemberGuarded` is the guarded cascade. `settleFamily` samples before its repair.
- [x] H2: the cascade sends the `sos_resolved` push through b-sos's `notifySosResolved`. SOS alerts are closed
      with a conditional update, so an owner's concurrent resolution wins.
- [x] H3: `profileName` rejects invisible, control and bidi-override names; scripts, emoji and RTL text are kept
      exactly as sent.
- [x] H4: `PUT /me/location` answers `403 NO_FAMILY` when the membership ended after authentication.
- [x] H5: no device row survives an account deletion that races with `POST /me/devices`, and `DELETE /me` sweeps
      sessions and devices a second time.
- [x] H6: `DELETE /me` erases the location points of the caller's SOS alerts; leaving the family keeps them.
- [x] H7: `DELETE /me` with a too-long password gets the message "Password is too long".
- [x] 26 new tests: one per issue, plus pins for the attacks that were already handled correctly. One existing
      race test was changed to assert invariants.
- [x] Appended the findings, the decisions and the updated b-family API to `docs/progress/b-me.md`.

## Pending / handoffs (files I do not own)
- [ ] b-family: use `removeMemberGuarded` for `DELETE /family/members/:id` and `claimAdminExit(target, { leaving: false })`
      for demotions.
- [ ] b-core / b-uploads: tighten `cloudinaryUrl` / `isFamilyAssetUrl`. Only this app's cloud name, the `image/upload`
      delivery type and the family folder should be accepted. Today any `res.cloudinary.com` URL passes, including
      `…/image/fetch/https://any-site/…`, a proxy for arbitrary content, and other Cloudinary accounts. After that,
      b-me can switch `avatarUrl` to the family-folder check (b-sos's test `CLOUD_URL` would need the family folder).
- [ ] b-core: move the `profileName` rules into the shared `personName`, so that register and family members reject
      the same names.
- [ ] b-core (optional): normalise non-ASCII decimal digits (`٠-٩`, `०-९`) in the shared `phone` block before
      validation. Today they are rejected with 422, which is safe but unfriendly.
- [ ] b-auth (optional): re-check that the user exists after inserting a refresh token in `issueTokens`, to close the
      last deletion/sign-in race.
- [ ] f-settings (optional): the mock `DELETE /me` could mirror H6 (clear the SOS trail and last location).

## Known issues
- Under heavy contention a LAST_ADMIN guard can still end in a 409 the client can retry. It never leaves zero admins.
- The tests take about 16 s instead of about 8.5 s, because of the LAST_ADMIN retry pauses and the looped race tests.

## Verification
- `node scripts/check-syntax.js` → all OK (107 JS files, 6 JSON files).
- `node --test tests/me.test.js` → 85/85, five runs in a row.
- `node --test --test-concurrency=1 "tests/**/*.test.js"` → 623/623.
