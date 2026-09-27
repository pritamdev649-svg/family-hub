# Progress · f-shell (Flutter app shell: bootstrap, settings, router, l10n tooling, home shell)

Owner files: `family_hub_app/lib/main.dart`, `lib/app.dart`, `lib/core/l10n/l10n.dart`, `lib/core/settings/**`,
`lib/core/router/**`, `lib/features/home/**`, `family_hub_app/tool/**`, `l10n_parts/common.arb`, `l10n_parts/home.arb`,
`analysis_options.yaml`, `test/widget_test.dart`, `test/core/router/**`, `test/core/settings/**`.

## Built
- [x] **`tool/l10n.dart`**: merges every `l10n_parts/*.arb` (sorted by file name) into `lib/l10n/app_en.arb`
      (`"@@locale": "en"` first, each message followed by its `@metadata`), then runs `flutter gen-l10n`.
      - Fails (exit 1, template left untouched) on duplicate keys **across files (prints both files)** and **within one
        file** (`jsonDecode` hides these, so a small JSON scanner finds them), invalid JSON, non-object root, invalid key
        names (must be lowerCamelCase identifiers), non-string messages and non-object metadata. Orphan `@meta` and a
        foreign `@@locale` only produce warnings.
      - Lock: atomic `family_hub_app/.l10n.lock`. `Directory.createSync` does not fail on an existing directory, so the
        atomic claim is an exclusive (`O_EXCL`) create of `.l10n.lock/owner.json` (pid, host, startedAt, token). Waits up
        to 120 s. A lock older than 180 s is stale: it is renamed aside and deleted, with a token check that puts back a
        fresh lock after a race. Release renames the directory before deleting it and never removes a lock it does not own.
        The lock is also released on SIGINT/SIGTERM.
      - Writes the template atomically (temp file + rename) and only when the content changed. Prints a summary with
        keys per fragment. If gen-l10n fails, it prints which fragment each key named in the error came from.
      - Options: `--no-gen`, `--help`. Env `FLUTTER_BIN`. Exit codes: 1 merge error, 2 app root not found, 3 lock
        timeout, 4 flutter could not start, otherwise the gen-l10n exit code.
- [x] `tool/merge_arb.dart`: merge-only variant (same lock), kept because docs/05 §2/§6 mention it.
- [x] `tool/src/l10n_tool.dart`: shared logic. `tool/test/l10n_tool_test.dart` covers merge rules, the duplicate scanner
      and the lock (timeout, hand-over, stale break, empty leftover, takeover safety).
- [x] `l10n_parts/common.arb`: `appName`, `appTagline`, all 47 required `common*` keys (plural `commonMinutesAgo`,
      `commonHoursAgo` and `commonDaysAgo`), plus `commonSearch`, `commonSend`, `commonSubmit`, `commonContinue`,
      `commonSkip`, `commonUndo`, `commonCreate`, `commonUpdate`, `commonView`, `commonUnknown`, `commonNotSet`,
      `commonShowPassword`, `commonHidePassword`, `commonDiscard`, `commonDiscardChangesTitle`,
      `commonDiscardChangesMessage` and `commonTryAgainLater`. Translator descriptions are included.
- [x] `l10n_parts/home.arb`: `navHome`, `navTasks`, `navSos`, `navSosTooltip`, `navMoney`, `navMore`,
      `homeSplashLoading`, `homeRouteNotFoundTitle`, `homeRouteNotFoundMessage`, `homeGoHome`.
- [x] `analysis_options.yaml`: flutter_lints plus `prefer_const_constructors`, `prefer_const_declarations`,
      `prefer_final_locals`, `avoid_print`, `always_use_package_imports`, `require_trailing_commas: false`. Excludes
      `lib/l10n/*.dart` and `build/**`.
- [x] `lib/core/l10n/l10n.dart`: `context.l10n`, and re-exports `AppLocalizations`.
- [x] `lib/core/settings/settings_controller.dart`:
      - `AppSettings {localeCode?, largeText, themeMode}` with `copyWith` (ValueGetter for `localeCode`) and `==`.
      - `SettingsKeys` (`settings.localeCode`, `settings.largeText`, `settings.themeMode`).
      - `SettingsController` / `settingsControllerProvider` with `setLocale` (null or `'system'` follows the device;
        unsupported codes throw `ArgumentError`), `setLargeText` and `setThemeMode`. The state updates first, then
        persists; a failed write is rolled back and rethrown. Reads tolerate corrupt or mistyped values.
      - `deviceLocalesProvider` follows system language changes at runtime through `WidgetsBindingObserver`.
      - `resolvedLocaleProvider` returns the chosen locale if supported, else the first device language the app
        supports, else `en`. The result is language-only.
- [x] `lib/core/settings/locale_resolution.dart`: pure `normalizeLocaleCode` (`pt-BR` -> `pt`, `HI` -> `hi`) and
      `resolveAppLocale`.
- [x] `lib/core/settings/text_scale.dart`: `AppTextScale.resolve` returns a `BoundedTextScaler`. With large text the
      scale is at least 1.3 and at most 1.6; otherwise the system scale is capped at 1.6. Bounds apply per font size, so
      Android 14 non-linear scaling is kept.
      - Re-clamping merges bounds safely. The framework's clamped scaler asserts `max > min`, so large text plus
        `MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3)` (the nav bar) crashed in debug builds. That bug was
        found by the stub integration test below, fixed, and now has a regression test.
- [x] `lib/core/router/app_routes.dart`: every path. The naming scheme is documented in the file header:
      - static routes are one `const` (for example `AppRoutes.login`);
      - parameterised routes have a `…Path` pattern plus a builder (`taskDetailPath` / `taskDetail(id)`);
      - query routes work the same way (`taskNewPath` / `taskNew(assigneeId:)`, `ledgerEntryNew(type:)`,
        `register(mode:, code:)`);
      - key constants: `idParam`, `memberIdParam`, `modeQuery`, `codeQuery`, `assigneeIdQuery`, `typeQuery`;
      - groups `tabs`, `signedOutPaths`, `onboardingPaths`, `publicPaths`; helpers `isPublic`, `isSignedOutPath`,
        `isTabRoot`, and `sanitizeLocation`, which rejects absolute, `//host`, relative and dot-segment paths.
- [x] `lib/core/router/route_guard.dart`: `RouteGate {loading, signedOut, needsVerification, needsFamily, ready}`,
      `routeGateOf(AsyncValue<SessionState>)` (a refresh keeps the previous value, so the splash does not flash),
      `RouteGuard.redirect` (docs/05 §9), and a pending deep link. A protected location requested during restore, or a
      notification tap before the session is complete, opens after sign-in instead of `/home`. It is forgotten on
      sign-out.
- [x] `lib/core/router/app_router.dart`:
      - `routeGateProvider`.
      - `goRouterProvider`: `refreshListenable` is a `ValueNotifier<RouteGate>` bridged from
        `sessionControllerProvider`, so the redirect runs only when the gate changes. The redirect reads the provider,
        which is always fresh. It also sets `initialLocation` `/splash`, `/` -> splash, and `errorBuilder`.
      - `StatefulShellRoute.indexedStack` with five `NoTransitionPage` branches, followed by the top-level feature
        route lists.
      - `rootNavigatorKey`.
      - `DeepLinkOpener` / `deepLinkOpenerProvider`: sanitises the location, remembers it while the session is
        incomplete, uses `go` for tab roots and `push` otherwise, and does nothing if that location is already open.
- [x] `lib/core/router/route_error_screen.dart`: localised "Page not found" with a "Go to home" button.
- [x] `lib/features/home/home_shell.dart`:
      - `NavigationBar` with Home / Tasks / SOS / Money / More. The SOS destination is always red
        (`semanticColors.sos`, indicator `sosContainer`) and has a tooltip.
      - Re-tapping a tab pops it to its root. Android back on a non-home tab root goes to Home.
      - Nav label scale is capped at 1.3 so the fixed-height bar never overflows.
      - Watches `backgroundSyncProvider`.
- [x] `lib/features/home/widgets/top_banner_slot.dart`: puts `SosStatusBanner` above the tab content and gives the
      status-bar inset to whichever is on top. The banner is measured after layout. The tree shape stays stable, so tab
      navigator state survives the banner appearing or disappearing.
- [x] `lib/features/home/splash_screen.dart`: brand icon, app name, tagline and `LoadingView`.
- [x] `lib/main.dart`:
      - Binding, `initializeDateFormatting()` and `SharedPreferences`.
      - Guarded `Firebase.initializeApp` with a 10 s timeout; on failure it logs and continues without push.
      - `onBackgroundMessage` only if Firebase initialised.
      - `ProviderScope(overrides: prefs, retry: appProviderRetry)`. Network, timeout and 5xx errors retry up to 2
        times (0.5 s, then 1 s). 4xx, auth, cancelled and non-API errors do not retry.
- [x] `lib/app.dart`:
      - `MaterialApp.router` with themes built once, `themeMode`, `locale: resolvedLocale`, the generated
        delegates and supported locales, and `onGenerateTitle`.
      - Text-scale `builder`.
      - Subscribes to `routeTaps` before `push.init()`, so the cold-start tap is not lost, and sends taps through
        `DeepLinkOpener`.
- [x] Tests:
      - `test/core/router/app_routes_test.dart` (9 tests).
      - `test/core/router/route_guard_test.dart` (13 tests).
      - `test/core/settings/locale_resolution_test.dart` (8 tests).
      - `test/core/settings/text_scale_test.dart` (10 tests).
      - `test/core/settings/settings_controller_test.dart` (7 tests).
      - `test/widget_test.dart`: retry policy, `TopBannerSlot`, splash, and an app smoke test (splash, then the
        session resolves signed out, then the router redirects to `/welcome` through the refresh bridge).

## Verified
- [x] `dart run tool/l10n.dart`: merged every fragment present and `flutter gen-l10n` succeeded.
- [x] 4 concurrent `dart run tool/l10n.dart` runs: all exit 0, runs waited for the lock, and no lock was left behind.
- [x] Scratch copy with a 2020 stale lock and a broken fragment: the stale lock was broken; a within-file duplicate,
      a cross-file duplicate (both files named) and an invalid key were reported; exit 1; template untouched.
- [x] `flutter test tool/test`: 14 passed.
- [x] `flutter test` in the real tree: `test/core/router` 22 passed, `locale_resolution_test` 8 passed,
      `text_scale_test` 10 passed.
- [x] **Stub integration check** in a scratch copy of the app: throwaway stubs stood in for the missing feature routes,
      screens, `SosStatusBanner`, `backgroundSyncProvider` and mock handlers. The real tree was not touched.
      - `dart analyze lib test tool`: no issues in real code.
      - `flutter test`: `widget_test.dart` 6 passed (splash, then the session resolves signed out, then `/welcome`
        through the refresh bridge); `settings_controller_test.dart` 7 passed.
      - A scratch-only shell test passed: a signed-in session lands on `/home` in `HomeShell`; there are 5 destinations;
        the SOS icon is `semanticColors.sos`; tab switching works; back on the Tasks tab goes to `/home`;
        `DeepLinkOpener` handles `/money` and rejects an external URL; an unknown route shows the localised error
        page and "Go to home" works.
      - Stored settings (hi, dark, large text) drive `MaterialApp.locale`, `themeMode` and a 1.3 text scale.
        Switching large text off gives 1.0.
      - Whole-suite result: 346 passed, 2 failed. Both failures are in other agents' tests
        (`test/core/design/app_theme_test.dart`, `test/core/widgets/async_and_feedback_test.dart`).
- [x] `dart analyze` on my files: no issues except errors caused by files other agents have not written yet (listed
      below).

## Pending / blocked on other agents
- [ ] `lib/core/router/app_router.dart` and `lib/features/home/home_shell.dart` compile once these exist:
      - route lists: `features/auth/auth_routes.dart` (`authRoutes`), `features/tasks/tasks_routes.dart`
        (`taskRoutes`), `features/ledger/ledger_routes.dart` (`ledgerRoutes`), `features/family/family_routes.dart`
        (`familyRoutes`), `features/notices/notices_routes.dart` (`noticeRoutes`),
        `features/emergency_card/emergency_card_routes.dart` (`emergencyCardRoutes`), `features/sos/sos_routes.dart`
        (`sosRoutes`), `features/settings/settings_routes.dart` (`settingsRoutes`);
      - tab screens with const constructors: `DashboardScreen`, `TasksScreen`, `SosScreen`, `MoneyScreen`, `MoreScreen`;
      - `const SosStatusBanner()`;
      - `backgroundSyncProvider`.
- [ ] `test/core/settings/settings_controller_test.dart` and `test/widget_test.dart` compile once the files above exist
      and `lib/core/network/mock/mock_registry.dart` can resolve every feature's `register*Mocks` (pulled in through
      `core_providers.dart`). Then run `flutter test`.

## Known issues / decisions
- While the SOS banner is visible, the status-bar strip above it uses the scaffold background, not the banner colour.
  This avoids a double top inset whatever the banner does internally. The banner must not pad itself for the status bar.
- The text scale is capped at 1.6 even when large text is off, because layouts are verified up to that scale.
- `firebaseMessagingBackgroundHandler` is registered in `main.dart` (per spec) and again by
  `PushNotificationService.init()`. Registering the same handler twice is harmless.
- `setLocale` changes only the device UI language. The account `locale` on the server (push and email language) must be
  sent by the language screen with `PATCH /me`.
