# f-auth: Flutter auth feature (progress)

Owner: f-auth. Scope: `family_hub_app/lib/features/auth/**`, `family_hub_app/l10n_parts/auth.arb` (85 keys, prefix `auth`),
`family_hub_app/test/features/auth/**`. Contract: docs/03-API_CONTRACT.md §4; tasks AUTH-11 … AUTH-20.

## Built

### Routes (`auth_routes.dart`)
- [x] `authRoutes`: `/welcome`, `/login` (optional `extra`: email), `/register?mode=create|join&code=`, `/forgot-password`
      (optional `extra`: email typed on log-in), `/verify-email`, `/family-setup`. All navigation uses `AppRoutes`; the
      router guard does the redirects, so screens never navigate after a session change.

### Screens (`presentation/screens/`)
- [x] `WelcomeScreen`: app name, tagline, three short benefits, a language picker (`LanguagePickerButton`: the 15
      `AppLanguages` native names → `settingsControllerProvider.setLocale`), and the buttons *Create a family* /
      *Join with invite code* / *I already have an account*. Shows "You were signed out" after the session expired.
- [x] `LoginScreen`: email + password (show/hide from `AppTextField`), autofill group, *Forgot password?* (the email is
      handed over and handed back), *Create an account*. `INVALID_CREDENTIALS` gives a generic inline banner.
      `TOO_MANY_REQUESTS` gives a banner with a live countdown ("Try again in 15 minutes" → "… 30 seconds"), and the
      button stays disabled until it ends. The lockout is **per email**. In mock mode a demo card has a *Fill in* button.
- [x] `RegisterScreen`: create / join switch (`FamilyModeSelector`, initial mode from the link: a `code` without a `mode`
      means join). Name, email, password + confirm, optional date of birth.
      - Create mode uses the shared `FamilyForm`.
      - Join mode uses `InviteCodeField` (upper-cases, keeps only letters/digits, max 8, `Validators.inviteCode`).
      - The consent checkbox has tappable *Privacy Policy* / *Terms of Service* links
        (`UrlActions.openUrl(AppConfig.privacyPolicyUrl / termsUrl)`). The links sit inside a translated sentence
        through placeholders, so word order works in every language. Submit stays disabled until the box is ticked.
      - `locale` = current resolved app language.
      - Server errors appear under their field: `EMAIL_TAKEN`, `INVALID_INVITE_CODE`, `VALIDATION_ERROR` details,
        and `GUARDIAN_CONSENT_REQUIRED` → "You must be at least N years old…".
      - Create mode also checks the country's consent age on the client before submitting.
- [x] `VerifyEmailScreen`: shows the email and a 6-digit field (`AutofillHints.oneTimeCode`; native digits and spaces
      are cleaned). It submits by itself at 6 digits.
      - *Resend code* counts down from 60 s. Sign-up already starts this timer, because register sent the first code.
        A `429` uses the server's `retryAfterSeconds`.
      - *Use another account* logs out.
      - In mock mode a hint shows the code `123456`.
- [x] `ForgotPasswordScreen`: step 1 is the email. Step 2 is the code, the new password and the confirmation, plus a
      resend with cooldown and *Use a different email*. On success a snackbar shows, and the screen goes back to log-in
      with the email filled in (or goes to `/login` when opened directly).
      - The wording never confirms that the account exists.
- [x] `FamilySetupScreen`: for a verified user without a family.
      - Greeting and "Signed in as …".
      - Create (the shared `FamilyForm`, `POST /family`) or join with a code (`POST /family/join`).
      - Log out from the app bar or the bottom button.
      - `ALREADY_IN_FAMILY` reloads the session so the router moves on.

### Shared auth widgets (`presentation/widgets/`) — DRY
- [x] `FamilyForm` + `FamilyFormController` (one widget for Register and FamilySetup): family name, `CountryPickerField`
      (flag + name, searchable bottom sheet by name / ISO code / dial code), currency dropdown (`Countries.currencies`,
      "EUR · €"), time zone dropdown (`Timezones.forCountry`, default `Timezones.defaultFor`).
      - Picking a country pre-fills the currency and the time zone.
      - When the country's default language differs from the app language, a snackbar offers it with a *Switch*
        action.
      - The first guess comes from the device locale (`en_IN` → India).
- [x] `AuthFormState` mixin + `ServerFieldErrors`: form validation, busy state (no double submit), keyboard dismissal,
      server field errors shown until the field is edited, other errors via `context.showError`.
- [x] `AuthScaffold`, `AuthHeader`, `AuthMessageBanner`, `AuthLinkRow`, `OtpCodeField`, `InviteCodeField`,
      `ConsentCheckbox`, `CooldownBuilder`, `ResendCodeButton`, `LanguagePickerButton`.

### Application / domain
- [x] `AuthActions` (`authActionsProvider`): login, register, verifyEmail, resendVerification, createFamily, joinFamily
      and logout on top of `SessionController`. It adds the bookkeeping: cooldowns, `markChanged({family, members})`
      after membership changes, and dismissing the session-expired notice on sign-in.
- [x] `AuthCooldown` (`authCooldownProvider`, auto-dispose family keyed by purpose + account). It stores an end time, so
      it stays correct in the background. A running cooldown keeps itself alive, and keys that were only watched are
      released. `authClockProvider` makes it testable.
- [x] `ForgotPasswordController` (step, email, busy flags, cooldown, no double submit).
- [x] `SessionExpiredNotice` (`sessionExpiredNoticeProvider`): listens to `AuthEvents.sessionExpired` (AUTH-17).
- [x] `authFieldErrors` / `authErrorCode` / `AuthField` (maps error codes to fields), `RegisterArgs` (query parsing),
      `AuthInputs` (OTP / invite code sanitising), `FamilyDraft` (country → currency / time zone),
      `signupConsentAgeIfTooYoung`, `formatWait`.

### Mock backend (`data/auth_mock_handlers.dart`, `registerAuthMocks(b, {clock})`)
- [x] Every `/auth/*` endpoint of §4. It is aligned with the real server's decisions (docs/progress/b-auth.md).
  - Register (create / join) goes through `FamilyMockService` (DRY with the `/family` mocks). It links the pre-added
    member with the same email.
  - Register errors: `EMAIL_TAKEN`, `INVALID_INVITE_CODE`, `MEMBER_EMAIL_EXISTS`, and the age gate
    `GUARDIAN_CONSENT_REQUIRED` (`details.consentAge`), except for a profile that already has guardian consent. A
    failed step is rolled back.
  - Login lockout: 5 failures within 15 min (the 5th already answers 429) lock the email for 15 min. Unknown emails
    are locked too. A success resets the counter.
  - OTP is always `123456`. It is valid 10 min; 5 × `INVALID_OTP`, then `OTP_EXPIRED`. Spaces and dashes are
    ignored. Resend has a 60 s cooldown.
  - forgot-password always answers `sent`. Unknown emails get decoy codes, so reset answers the same.
  - reset-password ends all sessions and marks the email verified.
  - change-password counts toward the lockout, ends all sessions and returns fresh `tokens`.
  - logout also removes the device token. me is implemented.
  - Sessions are ended by **deleting** refresh-token rows (a stale device then gets a plain `INVALID_REFRESH_TOKEN`
    instead of triggering reuse detection).

### Tests (`test/features/auth/`, 112 tests)
- [x] `auth_mock_handlers_test.dart` (31): every endpoint and rule above, with a controllable clock.
- [x] `auth_domain_test.dart` (28): RegisterArgs, input sanitising / formatters, FamilyDraft, the age gate,
      error → field mapping, ServerFieldErrors, formatWait, cooldown math, the country filter.
- [x] `auth_controllers_test.dart` (19): cooldowns (clock, keys, keep-alive / release), AuthActions (login, lockout,
      register → resend timer + data scopes, resend 429, verify, create / join, ALREADY_IN_FAMILY), the
      ForgotPasswordController (steps, cooldown, double submit, errors), and the session-expired notice.
- [x] Widget tests: `login_screen_test.dart` (6), `welcome_screen_test.dart` (4), `register_screen_test.dart` (7),
      `onboarding_screens_test.dart` (9: verify email, forgot password, family setup).
- [x] `auth_layout_test.dart` (7): every auth screen at 1.4× text, RTL, on a 320 dp wide phone, with no overflow.
- [x] `auth_flow_test.dart`: end to end in mock mode with the real app and router guard. It signs up, verifies with
      the OTP, lands on /home, logs out, and logs back in.

## Pending / handoffs
- [ ] **f-shell**: keep `sessionExpiredNoticeProvider`
      (`features/auth/application/session_expired_notice.dart`) alive while signed in, e.g.
      `ref.watch(sessionExpiredNoticeProvider);` in `FamilyHubApp.build` or `HomeShell`. Without that, the
      "You were signed out" notice only appears when the expiry happens while an auth screen is open.
- [ ] **f-domain**: `AuthRepository.changePassword` should save the `tokens` that the server (and now the mock)
      return with `{ changed: true, tokens }`. The server ends all other sessions, so a client that ignores them is
      signed out at its next refresh.
- [ ] **f-domain**: `repository_utils.normalizeOtp` removes native digits (`\D`). Using `Validators.normalizeOtp` would
      convert them. The auth screens already clean input with `AuthInputs.sanitizeOtp`, so this only affects other
      callers.
- [ ] **core / l10n owner**: country names in `Countries.all` are English only. They appear untranslated in the
      country picker (and in family settings). A localized `countryName(code, l10n)` would fix both.
- [ ] **docs owner**: contract §4 does not yet say that:
  - the 5th failed login answers 429;
  - resend-verification when already verified answers `{ sent: false, retryAfterSeconds: 0 }`;
  - reset-password marks the email verified;
  - change-password returns `tokens`;
  - register can answer `422 GUARDIAN_CONSENT_REQUIRED` with `details.consentAge`.

  b-auth lists the same items.
- [ ] **f-family**: auth's register now calls `FamilyMockService.validateNewFamily / createFamilyFor / joinFamilyFor /
      ageOf` and `founderDesignation`. Keep these signatures, or tell f-auth when they change.
- [ ] **fc-flutter / f-shell**: auth no longer uses `features/home/widgets/feature_placeholder.dart`. The dashboard
      and SOS stubs still do.
- [ ] Translations of `auth.arb` into the 14 other languages (translation agents).

## Known issues / decisions
- After sign-out the router goes to `/welcome` (route guard, not auth). The welcome and log-in screens both show the
  session-expired notice.
- The age gate runs on the client only in create mode, because the country is known there. In join mode the family
  country is unknown until the server answers, and the server's error appears under the date of birth.
- The forgot-password resend cooldown is 60 s on the client (the endpoint returns no wait). A `429` uses the server
  value.
- A `429` on step 1 of forgot password keeps the user on step 1 and shows the error with the wait.
- Mock access tokens never expire, so revoked sessions keep working in mock mode until the app restarts (core mock
  design, not auth).
- Mock validation `details` messages are English, like the server's.
- Not checked on a device or simulator in this step. Layout is covered by the widget tests: 400 dp and 320 dp, RTL,
  1.4× text.

---

## Hardening review (f-auth-harden, 2026-09-27)

A review of the feature above against the contract, the Flutter guide and the **hardened** backend
(`docs/progress/b-auth.md`, "Hardening review"). Every fix has a test. The auth suite has
**149 tests**, up from 112. Where this section disagrees with the sections above, this section
wins.

### Contract / guide conformance
- Paths, methods, bodies and field names of every `/auth/*` call and mock route match §4.
  `change-password` returns `tokens` (a superset). No pagination in auth.
- Tokens only: no hard-coded sizes, colours or durations in the UI. The remaining `EdgeInsets.all` /
  `symmetric` / `only(bottom:)` are symmetric, so RTL-safe. No left/right. No user-visible
  literals (`+91 · INR` is data). `context.mounted` / `mounted` is checked after every await, and
  every mutation guards against double submit.
- Found and fixed:
  - `\u` escapes in regexes had become literal bidi control characters in source; they are escaped
    now (analyzer `text_direction_code_point_in_literal`).
  - The consent checkbox had no screen-reader label.

### Mock ↔ hardened server (fixed)
- [x] One live code per email + purpose. A new code replaces it and resets its attempts; a used code
      is deleted.
- [x] Resend cooldown is `max(60 s, wrong codes × 3 min)`, so 5 wrong codes mean 15 min. The first
      code at sign-up skips the check. forgot-password inside the cooldown still answers `sent` and
      sends nothing.
- [x] Native digits in `otp` and `inviteCode`. `otp` longer than 64 characters → 422.
- [x] Names follow the server's `displayName` rules, for the person and the family (register): no
      control or bidi-override characters, and at least one visible letter, digit or symbol.
- [x] New passwords are at most 72 UTF-8 bytes. Login and current passwords are at most 128
      characters.
- [x] Date of birth: `YYYY-MM-DD` or an ISO date-time **with** an offset, calendar-checked, from
      1900, at most 1 day ahead.
- [x] Logout requires `refreshToken` (422 otherwise). A late replay of the logged-out token gets a
      plain `INVALID_REFRESH_TOKEN`, with no reuse detection, so other devices stay signed in.
- [x] Reset with a decoy code, or with a code whose account was deleted, → `INVALID_OTP`. A reset
      also drops any pending verification code.
- [x] verify-email validates the code before its idempotent "already verified" answer.
- [x] Join:
  - `EMAIL_TAKEN` comes before any family check;
  - `MEMBER_EMAIL_EXISTS` is checked before any write;
  - the pre-added profile's date of birth and consent decide the age gate;
  - `GUARDIAN_CONSENT_REQUIRED` carries `details.dateOfBirth` + `consentAge`.
- [x] `domain/auth_rules.dart` (`AuthInputs`, `OtpRules`) holds these rules once, for the forms, the
      controllers and the mock. `AuthInputs` moved there from `register_args.dart`, which
      re-exports it.

### App fixes
- [x] `AuthValidators.newPassword` (72 bytes) and `AuthValidators.displayName` (invisible, control or
      bidi characters) give localized messages. They are used on sign-up, reset and the family
      form. Without them a Devanagari passphrase would get the server's English error.
- [x] `VALIDATION_ERROR` details (English by backend convention) are shown under the field only in
      English. Other languages get `authFieldRejected`.
- [x] `authErrorText` / `context.showAuthError`:
  - server waits read "Try again in 14 minutes." instead of "… 840 seconds";
  - `GUARDIAN_CONSENT_REQUIRED` outside sign-up (family setup) shows the consent age.
- [x] Forgot password:
  - A `429` on step 1 starts no cooldown. Before, the next tap skipped to step 2 as if a code had
    been sent.
  - `INVALID_OTP` extends the resend wait to `sent + max(60 s, wrong × 3 min)`, like the server. The
    server answers `{ sent: true }` without sending inside that wait, so the old button promised
    codes that never came.
  - `AuthCooldown.extendUntil` never shortens a wait.
- [x] `AuthActions.resendVerification()` returns `bool`. `{ sent: false }` (verified on another
      device) reloads the session instead of showing "A new code is on its way".
- [x] `OnboardingSessionWatch` (verify email, family setup):
  - it re-reads the session when the app returns to the foreground (verified, or family
    created / joined, on another device);
  - it keeps `sessionExpiredNoticeProvider` listening, so an expiry on these screens is explained on
    the welcome screen.
- [x] `/family-setup?code=XXXX` (and `?mode=join`) starts in join mode with the code filled in.
- [x] The sign-up "Log in" link carries the typed email (useful right after `EMAIL_TAKEN`). A
      directly opened forgot-password screen goes to log-in with the email.
- [x] Country picker:
  - the dial code is isolated as LTR (`+91`, not `91+`, in Arabic);
  - the search accepts native digits;
  - only a query made of digits matches dial codes.
- [x] A new invite link on the open sign-up screen clears stale server errors.

### Edge-case sweep (auth-specific)
| # | Case | Handling |
|---|---|---|
| 1 | Offline / timeout on any submit | Localized snackbar, busy state released, no cooldown started. A resume refresh never throws. |
| 2 | Response lost after register succeeded | Retry gets `EMAIL_TAKEN` under the email. "Log in" carries the email. |
| 3 | Access token expires mid-action | The interceptor refreshes once and retries. A rejected refresh token signs out, and the notice survives on onboarding screens (fixed). |
| 4 | Refresh token expired while on verify / family setup | Router goes to welcome with "You were signed out" (fixed: the notice is now kept alive there). |
| 5 | 401 `INVALID_CREDENTIALS` | One generic banner. Never triggers a token refresh (interceptor checks the code). |
| 6 | Login lockout / rate limit (429) | Per-email countdown, button disabled, end time kept in the background. |
| 7 | Resend while the server cooldown grew (wrong codes) | Verify: the server's `retryAfterSeconds`. Forgot: mirrored locally (fixed). |
| 8 | 429 on forgot step 1 | Stays on step 1, wait shown in minutes, a retry really asks the server (fixed). |
| 9 | Deleted / regenerated invite code; family deleted | `INVALID_INVITE_CODE` under the field ("ask for the current code"). |
| 10 | Account deleted between forgot and reset | `INVALID_OTP` (mock parity, fixed). |
| 11 | 409 `ALREADY_IN_FAMILY` (joined on another phone) | Session reloaded, router moves on, plus a resume refresh (fixed). |
| 12 | Verified on another device | Resend `sent:false` → reload (fixed), plus a resume refresh (fixed). An idempotent verify accepts any code. |
| 13 | Under the consent age | Create: client check. Join: server error under the date of birth. Family setup: explained (fixed). Pre-added profile's date and consent win (mock, fixed). |
| 14 | 422 on fields the app does not check | Under the field. Localized outside English (fixed). |
| 15 | Very long / odd names | 60 characters. Invisible, control or bidi characters rejected with a message (fixed). All scripts, emoji and ZWJ are fine (tested). |
| 16 | Long passwords in Indic / Arabic scripts | 72-byte check with a localized message (fixed). |
| 17 | Native digits (Arabic-Indic, Devanagari …) | OTP, invite code, dial-code search (fixed), mock (fixed). |
| 18 | Rapid repeated taps / auto-submit + Enter | `isSubmitting`, `_resending`, `_signingOut` and the controller's busy flags → one request. |
| 19 | Large text, narrow phone, RTL | Layout tests at 1.4×, 320 dp and RTL for every screen, incl. family setup from an invite link (new). |
| 20 | Date / time-zone boundaries | The date of birth is sent as local midnight in UTC. The mock allows 1 day of slack and checks the calendar. Cooldowns are end times, correct across background and clock ticks. |
| 21 | Invite link while signed in without a family | `/family-setup?code=` works (fixed). The router still drops `code` on the redirect (handoff). |
| 22 | Pagination end / empty lists | No paginated data in auth. The country search shows an empty state. Currency and time-zone lists always contain the current value. |
| 23 | 403 non-admin | Not applicable (auth endpoints have no roles). Removal from the family → the router shows family setup. |

### Handoffs (other owners)
- [ ] **core router (`route_guard.dart`)**: when a `needsFamily` user opens `/register?code=X` (an
      invite link), redirect to `/family-setup?code=X` and keep the query. `FamilySetupScreen` reads
      it already. Today the code is lost.
- [ ] **f-shell / app**: keep `sessionExpiredNoticeProvider` alive in the signed-in shell (the
      onboarding screens do it themselves now).
- [ ] **core widgets (`snackbars.dart`)**: an error-styled snackbar for text that is already
      localized (`showErrorMessage(String)`). Auth uses `showInfo` for its wait and age-gate texts
      until then.
- [ ] **core mock (`mock_tokens.dart`)**: logout should delete the token and the tokens rotated from
      it, like the backend's `endDeviceSession`. Then `test/core/network/mock_login_test.dart` must
      expect the row to be gone instead of `revokedAt`. Auth works around it with `loggedOutAt`.
- [ ] **f-family (`family_mock_handlers.dart`)**:
  - `POST /family` does not apply the server's `displayName` rules to family names; it can reuse
    `AuthInputs.hasForbiddenNameChars` / `looksBlank`;
  - `/family/join` does not map native digits in invite codes;
  - member-name forms could reuse `AuthValidators.displayName`.
- [ ] **core validators**:
  - `Validators.password` does not check the 72-byte bcrypt limit; settings' change-password could
    use `AuthValidators.newPassword`;
  - `Validators.normalizeInviteCode` / `repository_utils.normalizeInviteCode` do not convert
    native digits.
- [ ] **f-domain** (still open from f-auth): `AuthRepository.changePassword` should store the
      returned `tokens`, and `repository_utils.normalizeOtp` drops native digits.
- [ ] **docs owner**: contract §4 should document:
  - the growing resend cooldown and the silent no-resend inside it;
  - logout requiring `refreshToken`;
  - native digits;
  - the `displayName` rules;
  - the 72-byte limit;
  - dates of birth with an offset;
  - `EMAIL_TAKEN` precedence;
  - `GUARDIAN_CONSENT_REQUIRED` on register.

  docs/05 §9 should list `/family-setup?mode=&code=`.
- [ ] **backend (b-core)**: localized `VALIDATION_ERROR` details would let the app show the specific
      reason in every language.
- [ ] **translations**: 5 new keys (`authPasswordTooLong`, `authNameInvalidCharacters`,
      `authNameNeedsLetter`, `authFieldRejected`, `authTooManyAttemptsWait`), 90 auth keys in total.
