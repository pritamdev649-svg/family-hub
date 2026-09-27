# f-auth-harden: review and hardening of the Flutter auth feature

Owner: f-auth-harden (same files as f-auth): `family_hub_app/lib/features/auth/**`,
`family_hub_app/l10n_parts/auth.arb`, `family_hub_app/test/features/auth/**`.
Details of every finding are in `docs/progress/f-auth.md`, section "Hardening review".

## Method
1. Read the contract (§1, §2, §4), the Flutter guide, the product brief, the builder's report and
   every auth file, plus the shared code it relies on (session controller, auth repository,
   router guard, interceptor, validators, core mock).
2. Compared the `/auth` mock with the **hardened** backend (`family_hub_backend/src/modules/auth`,
   `docs/progress/b-auth.md` "Hardening review"), rule by rule.
3. Grepped for guide violations (hard-coded sizes / colours, left/right, string literals, missing
   `mounted` checks) and walked through 20 edge cases (list in f-auth.md).
4. Fixed what I found, then wrote a test for each fix. I checked that the lifecycle tests catch
   the bug: with the fix removed, 3 of them fail.

## Built / fixed
- [x] Mock parity with the hardened server: one live code per email + purpose; resend cooldown
      `max(60 s, wrong codes × 3 min)` (after 5 wrong codes: 15 min); forgot-password sends
      nothing inside the cooldown; native digits in codes and invite codes; code input ≤ 64
      characters; server `displayName` rules for person and family names; new passwords
      ≤ 72 UTF-8 bytes; strict ISO dates of birth; logout needs `refreshToken`, and a late
      replay of a logged-out token gets a plain `INVALID_REFRESH_TOKEN`; a decoy reset code
      gets `INVALID_OTP`; reset also drops the verification code; verify-email validates the
      code before its idempotent answer; on join, the pre-added profile's date of birth decides
      the age gate; `MEMBER_EMAIL_EXISTS` is checked before any write.
- [x] Shared rules in `domain/auth_rules.dart` (`AuthInputs`, `OtpRules`), used by the forms,
      the forgot-password controller and the mock (DRY).
- [x] Forms check the server rules first, with localized messages (`AuthValidators`): invisible
      names, control / bidi-override characters, passwords over 72 bytes (for example about
      25 Tamil or Devanagari letters).
- [x] Non-English users no longer see the server's English `VALIDATION_ERROR` details under a
      field; they get `authFieldRejected`.
- [x] Waits are shown in minutes ("Try again in 14 minutes."), not "840 seconds". The consent-age
      gate on family setup is explained with the country's age.
- [x] Forgot password:
  - a `429` on step 1 no longer skips to step 2 later, as if a code had been sent;
  - the resend button follows the server's growing cooldown, so it never promises a code that
    will not come.
- [x] Resend when the email is already verified (on another device) reloads the session instead
      of saying "code sent".
- [x] Verify email and family setup reload the session when the app returns to the foreground,
      and they keep the session-expired notice listening (`OnboardingSessionWatch`).
- [x] `/family-setup?code=` / `?mode=join` pre-fills join mode (invite link while signed in
      without a family).
- [x] The sign-up "Log in" link and a directly opened forgot-password screen hand the email to
      log-in.
- [x] Country picker:
  - dial codes stay `+91` in RTL (isolated LTR);
  - dial-code search accepts native digits;
  - only a query made of digits matches dial codes.
- [x] The consent checkbox now has a screen-reader label. A new invite link clears stale server
      errors on the open sign-up screen.
- [x] 5 new l10n keys (`auth.arb` now has 90 keys), merged with `dart run tool/l10n.dart`.
- [x] Tests: 149 auth tests, up from 112 (+37). Dependent suites pass: core mock login,
      settings, family, shared, ledger.

## Pending
- [ ] Handoffs to other owners (the list is in the final report and in f-auth.md): router keeps
      `?code=` on the redirect to family setup; the app shell keeps the session-expired notice
      alive; `SnackX.showErrorMessage`; `MockTokens` deletes tokens on logout, plus the core
      test that goes with it; the family mock applies the name rules; `Validators.password`
      checks the 72-byte limit; `AuthRepository.changePassword` stores the returned tokens;
      contract §4 notes; translations of the 90 auth keys.
- [ ] Not run on a device or simulator. Covered by widget tests at 320 dp, RTL and 1.4× text.

## Known issues / decisions
- The mock does not normalise to NFC / NFKC (Dart has no built-in normaliser). The client
  counts raw UTF-8 bytes for the 72-byte check. The server stays the authority.
- The mock keeps logged-out refresh-token rows, flagged `revokedAt` + `loggedOutAt`, because a
  core test expects the row. Its own refresh handler refuses them without reuse detection. It
  does not end tokens rotated from a logged-out token (the server does).
- Auth-specific error texts use the info snackbar style until core offers an error-styled
  snackbar for text that is already localized.
- The client mirrors the growing resend cooldown only for forgot password. Verify email gets
  the exact wait from the server's `429` on resend.
