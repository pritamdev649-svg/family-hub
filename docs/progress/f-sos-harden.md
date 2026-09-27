# Progress · f-sos-harden (review + hardening of the Flutter SOS feature)

Scope (same as the builder): `family_hub_app/lib/features/sos/**`, `family_hub_app/l10n_parts/sos.arb`,
`family_hub_app/test/features/sos/**`. The full list of findings, fixes and the edge-case table is appended to
`docs/progress/f-sos.md` ("Hardening review").

## Done
- [x] Contract conformance (§10) of the repository and every mock handler against the contract and the backend
      module. Nothing to change. The b-sos-harden item "140 UTF-16 units / clean-up / privacy" was already in place.
- [x] Guide conformance grep (tokens, `Icons.*`, `Colors.*`, left/right, literals, `AsyncValueView`,
      `context.mounted`, `markChanged`). Clean.
- [x] An SOS is never held back:
  - the unanswered "share location?" dialog auto-sends without location after 10 s, with a visible countdown;
  - the permission prompt is awaited at most 10 s; a late grant starts tracking.
- [x] `sosEndedAlertIdsProvider` is wired (controller `_end`, `SosAlertActions`, adoption). Ended alerts no longer
      flash back from stale lists.
- [x] No reload flicker: `otherActiveSosAlertsProvider` keeps the last list while reloading.
- [x] Polling survives a failed (re)load, for the active list and for the alert screen (transient errors only).
- [x] `NO_FAMILY` / `FORBIDDEN`:
  - they re-read the session (`sosSessionResyncProvider`);
  - a NO_FAMILY poll clears the family's alerts;
  - an own resolve that gets NO_FAMILY ends the local alert.
- [x] First-wins resolution: the UI says "already ended" instead of a false confirmation.
- [x] Push-once navigation (`presentation/sos_navigation.dart`) for the banner, the tiles and the links.
- [x] Expiry while open:
  - the alert screen actions hide at `expiresAt`;
  - the tile highlight updates; tile titles are capped at 2 lines.
- [x] `sosAlertProvider` resets on a family switch.
- [x] Status bar (user request "make status bar transparent"):
  - the SOS banner continues its red behind the transparent status bar;
  - it sets light status-bar icons (`_StatusBarBackdrop`);
  - no change to `TopBannerSlot` was needed.
- [x] Mock: `mockExpireStaleSosAlerts` is public, for the member-removal cascade.
- [x] Tests:
  - new `sos_edge_cases_test.dart` (13 tests);
  - fakes `activeGate` and `promptGate`;
  - 92 SOS tests pass;
  - 3 of the new tests were mutation-checked against the old behaviour.
- [x] l10n: one new key, `sosLocationDialogAutoSend` (84 `sos*` keys).

## Pending / handoffs (other owners)
- [ ] f-shell / design: app-wide transparent status bar.
  - `main.dart`: `SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge)` and
    `setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent))`.
  - `core/design/app_theme.dart`: `AppBarThemeData(systemOverlayStyle: …transparent…)`.
  - `TopBannerSlot`: the offline banner still has a canvas strip above it.
- [ ] f-family: `removeMember` should call `mockExpireStaleSosAlerts(db, familyId)` first.
- [ ] core: one shared push-once helper and one shared session-resync helper. Today there are copies in tasks,
      dashboard, ledger, emergency card and SOS.
- [ ] f-auth: `lib/features/auth/presentation/screens/welcome_screen.dart:154` overflows by 24 px. That breaks
      `test/widget_test.dart` and `test/app_smoke_test.dart`. It is not SOS-related.
- [ ] Still open from the build: the f-design `AppDurations` doc comments, the f-settings `_exportSosAlert` DRY,
      translations, and QA-10 device tests.
- [ ] Redesign agent: SOS screens → `GradientHeaderScrollView` (design doc §3b).

## Known issues
- `_StatusBarBackdrop` paints the strip between the top of the screen and the banner, outside its own bounds. It
  never paints more than the status-bar height, and nothing when the banner is at the very top or lower down. If
  `TopBannerSlot` ever hands the inset to the banner, the banner's `SafeArea(top: true)` takes over and the strip
  becomes zero.
- The two 10 s limits add at most 20 s before an alert without location goes out, and only when nobody answers.
  Someone who answers is not delayed.
- Phone-clock skew still affects the local "time left". Lists trust the server status.

## Verification
- `dart run tool/l10n.dart` → sos.arb 84 keys, `flutter gen-l10n` OK
- `dart analyze lib/features/sos test/features/sos` → No issues found
- `flutter test test/features/sos` → +92, all tests passed
- `flutter test test/features/dashboard test/core/network/mock_login_test.dart` → +80, all passed
- `flutter test test/widget_test.dart test/app_smoke_test.dart` → 2 failures, both caused by the `welcome_screen.dart`
  overflow (auth, in progress by another agent)
