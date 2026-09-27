# fc-flutter: Flutter foundation integration (progress)

Owner for this step: everything under `family_hub_app/` except the feature folders `lib/features/<feature>/`
(other than `home`), where only placeholder stubs were created. Goal: make the parallel foundation work
(f-design, f-core, f-services, f-domain, f-shell) compile, run and pass its tests together.

## Built

### Feature stubs (each file starts with `// STUB - replaced by feature agent`)
Created only where no file existed (no-clobber copy); none existed, so none were skipped.
- [x] Mock handlers at the paths `mock_registry.dart` imports, each `void registerXMocks(MockBackend b)`:
      `registerDashboardMocks`, `registerEmergencyCardMocks`, `registerFamilyMocks`, `registerLedgerMocks`,
      `registerNoticeMocks`, `registerSosMocks`, `registerTaskMocks`, and `registerMeMocks` + `registerUploadMocks`
      (`settings`). All are empty: those routes answer `404 NOT_FOUND`, like an unknown route on the server.
- [x] `auth/data/auth_mock_handlers.dart` (`registerAuthMocks`) is **minimal but working**, so the seeded demo accounts can
      sign in now: `POST /auth/login` (trim + lower-case the email, 422 with field details, a single `INVALID_CREDENTIALS`
      for unknown email or wrong password), `POST /auth/refresh` (`MockTokens.rotate`), `POST /auth/logout` (revokes only the
      caller's own refresh token) and `GET /auth/me` (`MockSerializers.session`). Not implemented yet (they answer 404):
      register, verify/resend, forgot/reset/change password, login lockout.
- [x] Route lists `List<RouteBase> get …Routes`: `taskRoutes`, `ledgerRoutes`, `familyRoutes`, `noticeRoutes`,
      `emergencyCardRoutes`, `sosRoutes`, `settingsRoutes` (empty) and `authRoutes`, which has placeholder screens for
      `/welcome /login /register /forgot-password /verify-email /family-setup`.
- [x] Tab screens with const constructors at the exact guide §9 paths: `DashboardScreen`, `TasksScreen`, `SosScreen`,
      `MoneyScreen`, `MoreScreen`.
- [x] `SosStatusBanner` (`const SosStatusBanner({super.key})` → `SizedBox.shrink()`) and
      `backgroundSyncProvider` (`Provider<void>`, no-op).

### Placeholder support (home, temporary)
- [x] `lib/features/home/widgets/feature_placeholder.dart`: `FeaturePlaceholderScreen` (AppBar + localized
      `EmptyState` inside `ResponsiveCenter`), `PlaceholderSignOutButton`, and `PlaceholderDemoSignInButton`
      (**mock mode only**: signs in as `demo@familyhub.app`). Both buttons share one busy-state and
      double-submit-safe action button, and errors go to `context.showError`.
- [x] `l10n_parts/home.arb`: `homePlaceholderTitle`, `homePlaceholderMessage`, `homePlaceholderDemoSignIn`,
      `homePlaceholderSignOut` (marked "Temporary" for translators).
- [x] Placeholder behaviour: `/welcome` has "Try the demo family" (mock mode). `/verify-email`, `/family-setup` and the More
      tab have "Sign out", so a signed-in user is never stuck on a placeholder.

### Foundation fixes and handoffs I owned this step
- [x] `home_shell.dart`: `OfflineBanner` added under `SosStatusBanner` in the `TopBannerSlot` banner. Both are zero-height
      when idle; SOS sits on top because it matters most.
- [x] `main.dart`: `ProviderScope(retry: apiRetryPolicy)`. The duplicate `appProviderRetry` was removed, so the app-wide
      default and the per-provider policy are the same function. Behaviour change: timeouts are no longer retried,
      because they have already waited the 15–20 s client timeout.
- [x] `core/l10n/error_messages.dart`: `localizedErrorMessage` now unwraps Riverpod `ProviderException` itself
      (new `unwrapProviderError`). `core/widgets/widget_errors.dart` delegates to it (no duplicate loop).
- [x] `core/services/push_notification_service.dart`: the device API reads `meRepositoryProvider` lazily (test overrides apply).
- [x] `core/config/app_config.dart`: doc comment corrected to `POST /uploads/signature`.
- [x] `config/dev.example.json` + `config/dev.json` (mock mode) with `API_BASE_URL, USE_MOCK_API, APP_ENV,
      CLOUDINARY_CLOUD_NAME, CLOUDINARY_UPLOAD_PRESET, PRIVACY_POLICY_URL, TERMS_URL`. The URL keys hold the real default
      URLs, because a key defined as `""` makes `String.fromEnvironment` return `""` instead of its `defaultValue`.
- [x] `family_hub_app/.gitignore`: `/config/dev.json`, `/.l10n.lock`, `/.l10n.lock.*`.
- [x] Already satisfied (checked, no change): `AppTheme.light()/dark()` passed to `MaterialApp.router`; prefs override
      and `initializeDateFormatting` in `main`; flutter_localizations delegates via
      `AppLocalizations.localizationsDelegates`; `context.showError` already silent for cancelled uploads
      (`isCancellation`); AndroidManifest permissions + label; iOS Info.plist usage strings, background modes and 15
      localizations.

### Tests added
- [x] `test/core/network/mock_login_test.dart` (9 tests, real providers in a `ProviderContainer`): registry wiring and `/health`;
      demo login → contract `{user, tokens}` (no password; token formats; stored tokens authenticate `/auth/me`);
      case-insensitive email; wrong password → 401 `INVALID_CREDENTIALS` without refresh or sign-out event; unknown email
      gives the same error; 422 field details; refresh rotation + reuse detection; `SessionController.login` → complete
      session (Amit, admin, Sharma Family, INR, IN) → `logout` → signed out, tokens cleared, refresh token revoked, then 401.
- [x] `test/app_smoke_test.dart`: the real `FamilyHubApp` in mock mode goes splash → `/welcome` → demo login → `/home` in `HomeShell`
      (5 destinations, SOS tooltip) → Tasks / More tabs → offline banner shows and hides → logout → `/welcome`.
      Login goes through the controller, not the placeholder UI, so the test survives the stub replacement.
- [x] `test/core/l10n/error_messages_test.dart` (4 tests): code mapping, `ProviderException` unwrap, Dio/timeout, fallbacks.
- [x] `test/widget_test.dart`: the retry-policy group now covers `apiRetryPolicy`.

## Verified
- [x] `dart run tool/l10n.dart`: 7 fragments, 156 keys merged, `flutter gen-l10n` OK.
- [x] `flutter analyze`: **No issues found** (whole package: lib, test, tool).
- [x] `flutter test`: **363 passed** (349 existing + 14 new). f-shell's scratch run had flagged failures in
      `app_theme_test` and `async_and_feedback_test`; both pass in the real tree.
- [x] `flutter test tool/test`: 14 passed.
- [x] `flutter build apk --debug --dart-define-from-file=config/dev.json`: built `build/app/outputs/flutter-apk/app-debug.apk`.
- [x] `flutter build ios --simulator --debug --dart-define-from-file=config/dev.json`: first `pod install` (adds
      `ios/Podfile.lock` and the Pods integration), then built `build/ios/iphonesimulator/Runner.app`.
- [x] Ran it on the booted iPhone 17 Pro simulator (`simctl install/launch`). Splash, then the welcome placeholder; tapping
      "Try the demo family" opened the Home shell with 5 tabs and the red SOS tab. Firebase not configured, so push
      stays disabled as designed.

## Pending
- [ ] Feature agents replace every `// STUB - replaced by feature agent` file. When none import
      `features/home/widgets/feature_placeholder.dart` any more, delete it together with the four `homePlaceholder*` keys.

## Known issues / decisions
- The auth mock stub has no login lockout (5 failures / 15 min). f-auth owns that.
- Restore without a cached session, while the server is unreachable, ends on `/welcome` after the retries (tokens are kept).
  I did not add a splash retry button. If wanted: `ref.invalidate(sessionControllerProvider)`.
- The `'UPLOAD_CANCELLED'` mapping in `error_messages.dart` is kept (harmless). Removing it and its
  `servicesErrorUploadCancelled` key must happen together, and translation files may already contain the key.
- `lib/core/config/app_config.dart` is still not `dart format`-clean. I only fixed a doc comment, and did not reformat it
  because f-core deliberately restored its formatting.
- `docs/05-FLUTTER_GUIDE.md` was not changed: no documented API changed. `appProviderRetry` was never in the guide, and
  `unwrapProviderError` is additive.
