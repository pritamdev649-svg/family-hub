# Progress · f-sos (Flutter SOS feature)

Owner files: `family_hub_app/lib/features/sos/**`, `family_hub_app/l10n_parts/sos.arb`,
`family_hub_app/test/features/sos/**`.
Contract: docs/03-API_CONTRACT.md §10. Tasks SOS-08 … SOS-16 in docs/TASKS.md.

## Built
- [x] **Domain** `domain/sos_alert.dart`
  - `SosStatus` (`active|resolved|expired`). An unknown status becomes `expired`, so it never starts tracking.
  - `SosResolution` (`safe|false_alarm|helped`, nullable).
  - `SosAlert`:
    - `fromJson` is defensive. It drops invalid trail points. A missing `expiresAt` becomes `startedAt + 15 min`.
    - `toJson`, `copyWith` (ValueGetter), `==`/`hashCode`.
    - Status helpers look at `expiresAt`: `effectiveStatusAt`, `isActiveAt`, `isActive`, `remainingAt`, `endedAtAsOf`.
    - Also `isOwnedBy`, `hasLocation`, `compareNewestFirst`.
- [x] **Repository** `data/sos_repository.dart` + `sosRepositoryProvider`
  - Methods: `create`, `active`, `history` (paged, limit ≤ 100), `get`, `sendLocation`, `resolve`.
  - `create` cuts the message to 140 UTF-16 units without splitting emoji. It drops a negative accuracy. A response
    without an `id` counts as malformed.
- [x] **Mock** `data/sos_mock_handlers.dart`
  - Implements all 6 routes with the backend's check order: 401 → NO_FAMILY → 400 → 422 → 404 → 403 → 409 → 403
    LOCATION_SHARING_DISABLED.
  - `POST /sos` is idempotent: it returns the caller's active alert with 200, otherwise 201.
  - Lazy expiry is persisted after 15 min.
  - `POST /sos/:id/location`:
    - Updates less than 3 s apart are accepted but not stored.
    - The trail is capped at 100 points.
    - Owner only (403 for others). 409 when the alert is no longer active; LOCATION_SHARING_DISABLED when the owner's
      mode is `never`.
  - `POST /sos/:id/resolve`: owner or admin. A repeat on a resolved alert is idempotent (the first resolution wins).
    An expired alert answers 409.
  - Only `GET /sos/:id` returns the trail.
  - Name, phone and avatar are resolved at read time (null for a removed member). The owner's **current** mode hides
    the location.
  - History is paginated.
  - Seed: no active alert, and 1 resolved alert (Priya, "safe", 3 days ago, 4 trail points) in the history.
  - Exported for other mocks: `mockActiveSosAlerts(db, familyId)`, `mockSosAlertJson`, `mockSosStatus`.
- [x] **Providers** `application/sos_providers.dart`
  - `activeSosAlertsProvider` (public):
    - Watches `sessionUserIdProvider`, the family and `DataScope.sos`.
    - Polls `GET /sos/active` every `AppDurations.pollActiveSos` (15 s), only while the app is in the foreground
      (`AppLifecycleListener`) **and** someone listens.
    - Polls are silent: the list is only replaced when it changed, and a failed poll keeps the last list. On app resume
      or listener resume it catches up right away.
  - `myActiveSosAlertProvider`, `otherActiveSosAlertsProvider`.
  - `sosAlertProvider(id)` (autoDispose): polls `GET /sos/:id` every `AppDurations.pollSos` (5 s), only while the
    alert is active and the screen is visible. Riverpod pauses the subscriptions of covered routes. `apply()` shows a
    mutation result right away.
  - `sosHistoryProvider`: paginated history with `loadMore`.
- [x] **Runtime** `application/sos_runtime.dart`
  - `sosClockProvider`, `sosAppForegroundProvider` (AppLifecycleListener), `sosTrackingTextsProvider` (localized
    foreground-service texts).
  - `SosPoller`: non-overlapping polls, each scheduled after the previous one finishes.
- [x] **SosController** `application/sos_controller.dart` (`sosControllerProvider`, `SosState`)
  - Phases: `idle → countdown (3..1, cancellable) → sending → active → idle`.
  - When the mode is `never`, it asks "Share location for SOS only" (`PATCH /me` `sos_only`, then `applyMe` and
    `markChanged(members)`) or "Send without location".
  - It then requests permission. If permission is denied, it sends without location and the outcome says why.
  - First fix: 5 s timeout. A last-known fix older than 10 min is not sent.
  - `POST /sos` is retried 2× on network / 5xx errors (safe, because the server is idempotent). A failure goes to
    `sendError`, which the screen shows with "Send again" and the emergency number.
  - Live tracking: `LocationService.track` uploads through `SosLocationUploader` at most every
    `AppConfig.sosLocationInterval`. Fast fixes are coalesced, so the newest one is always delivered.
  - Tracking stops:
    - at `expiresAt`;
    - on resolve;
    - on 409 SOS_NOT_ACTIVE, 404 or NO_FAMILY;
    - when the alert disappears from `/sos/active` (checked with `GET /sos/:id` first);
    - on logout / account switch.
  - LOCATION_SHARING_DISABLED, or the member switching to `never`, stops sharing but keeps the alert.
  - Switching `never` → `sos_only` during an alert starts sharing.
  - App start / resume: the member's active alert from `/sos/active` is adopted and tracking resumes **without** a
    permission prompt.
  - Permission revoked / GPS off shows as `SosSharing.unavailable`, with "Allow location" / "Open settings". Tracking is
    re-checked on resume.
  - Resolve: "I am okay" = `safe`, "False alarm" = `false_alarm`. It guards against a double submit and calls
    `markChanged({DataScope.sos})`.
  - `SosAlertActions` / `sosResolvingProvider`: resolve from the alert screen and the banner. Admin "helped" goes to the
    repository; the member's own alert goes through the controller. Busy state is kept per alert.
- [x] **SosScreen** (tab)
  - Huge round red `SosButton`: Semantics label, haptic feedback, diameter shrinks on narrow screens, content scales
    inside the circle for large text.
  - Countdown overlay + "Cancel SOS".
  - Disclaimer "Alerts your family only".
  - "Call emergency services <number>" from `currentCountryProvider`.
  - The location-sharing mode row opens `/settings/location`.
  - `SosActivePanel`:
    - pulsing live indicator (static when animations are disabled);
    - time remaining (m:ss);
    - "Location sent 5 seconds ago";
    - I am okay / False alarm;
    - "View alert details".
  - Other members' active alerts are shown as `SosAlertTile`s (through `AsyncValueView`), plus a link to the history.
  - Pull-to-refresh.
- [x] **SosStatusBanner** (public, shown in HomeShell)
  - The member's own alert: "Your SOS is active – sharing live location" + "I am okay".
  - One other alert: "<name> needs help" + Open → `/sos/alert/:id`.
  - Several alerts: "N family members need help" → SOS tab.
  - Otherwise `SizedBox.shrink`.
  - It is compact (min 48 dp, max 2 lines), RTL-safe (directional padding) and a live region. Watching it keeps the
    controller alive, so tracking resumes on app start.
- [x] **SosAlertTile** (public): the active style uses SOS colours. It shows a status/resolution chip, the started
  time, live location or not, and the end time. It opens `/sos/alert/:id` unless `onTap` is given.
- [x] **SosAlertScreen** `/sos/alert/:id` (also the push route)
  - Header: avatar, "<name> needs help" / "Your SOS", status chip, started time, time left / ended time, and "Helped ·
    by Amit".
  - Message, if any.
  - Last location: coordinates (LTR), "Accurate to about 12 m", "Updated 20 seconds ago", and Open in Maps
    (`UrlActions.openMap`).
  - The 5 newest trail points, each opening the map.
  - Call member (`memberPhone`) and call the emergency number.
  - Resolve: "I am okay" / "False alarm" for the owner; "Mark as helped" (with confirmation) for admins.
  - The member's `EmergencyCardView` (via `emergencyCardProvider`); hidden for former members.
  - A missing alert or malformed link shows "Alert not available" with "Go to SOS".
- [x] **SosHistoryScreen** `/sos/history`: `PaginatedListView` with load more, pull-to-refresh and an empty state.
- [x] **Routes** `sos_routes.dart`: `/sos/history`, `/sos/alert/:id`.
- [x] **l10n** `l10n_parts/sos.arb`: 83 `sos*` keys with descriptions, ICU plurals (`sosSendingIn`, `sosSecondsAgo`,
  `sosManyNeedHelp`) and placeholders. It reuses `services*` keys for permission texts and the foreground notification,
  and `locationSharing*` labels.
- [x] **Tests** `test/features/sos/` — 79 tests:
  - model parsing (9);
  - repository requests (10);
  - mock rules (22);
  - uploader throttling / stop conditions in fake time (7);
  - controller (19): countdown / cancel / never-mode dialog both ways / failed mode switch / permission denied + retry /
    network retries / resolve / 409 / expiry / resolved elsewhere / mode switch / logout / resume adoption / polling
    pause in background;
  - widget tests (12): SosScreen idle, countdown + cancel, full send + "I am okay", never-mode dialog, others' alerts;
    banner in 4 states; alert screen with maps / call / emergency card / helped; not-available state; history + empty.

## Decisions
- `pollSos` (5 s) is used for the alert screen and `pollActiveSos` (15 s) for the active list, as the task and docs/02 §5
  say. The doc comments in `app_durations.dart` describe the two the other way round (see handoffs).
- The "share your location?" dialog appears **after** the countdown ("on send"). So an accidental tap can still be
  cancelled before any question. It cannot be dismissed by tapping outside; the back button counts as "send without
  location". An SOS is never dropped.
- Stopping the location stream is fire-and-forget (`SosLocationUploader.stop()` is sync). Awaiting
  `StreamSubscription.cancel()` can hang (root-zone future), and callers never need to wait for the platform.
- Riverpod 3 pauses the subscriptions of providers nobody listens to, and of covered routes. So the active-list polling
  pauses while a full-screen route covers the shell. Tracking (its own stream and timers), expiry and resolve keep
  working, and polling catches up when the shell is visible again.
- The first SOS fix waits at most 5 s. Live tracking delivers the location shortly after, so alerting the family is
  never delayed by GPS.
- Admins resolving someone else's alert must confirm. The owner's "I am okay" / "False alarm" need no confirmation
  (speed).

## Pending / handoffs
- [x] (dashboard owner, done by f-dashboard) The `/dashboard` mock `activeSos` can use `mockActiveSosAlerts(db, familyId)` from
      `features/sos/data/sos_mock_handlers.dart`. `DashboardScreen` can show `SosAlertTile(alert)` for
      `activeSosAlertsProvider` / `activeSos`.
- [ ] (f-settings, optional DRY) The `/me/export` mock's `_exportSosAlert` duplicates `mockSosAlertJson(db, doc,
      withTrail: true)`.
- [ ] (f-design) The doc comments of `AppDurations.pollSos` / `pollActiveSos` in `lib/core/design/app_durations.dart`
      are swapped compared with docs/02 §5 (5 s = the alert screen, 15 s = the global banner). Only the comments need
      fixing; the values are right.
- [ ] (translations) 83 new `sos*` keys.
- [ ] (QA-10) Test the permission matrix on real devices, in background and killed state (Android foreground-service
      notification, iOS blue indicator).

## Known issues
- While debugging a hanging fake-async test I ran `pkill -f flutter_tester` once. That may have ended other agents'
  concurrently running `flutter test` processes at that moment; those runs should be repeated if they failed without a
  test error.
- Time left and expiry use the phone clock against the server's `expiresAt`. A skewed clock can end local tracking a
  little early or late; the server's 409 stays authoritative.
- There is no in-app map. Locations open in the maps app / browser (`UrlActions.openMap`), as specified.

## Verification
- `dart run tool/l10n.dart` → sos.arb 83 keys, gen-l10n OK
- `dart analyze lib/features/sos test/features/sos` → No issues found
- `dart analyze lib` → No issues found
- `flutter test test/features/sos` → +79, all tests passed
- `flutter test test/app_smoke_test.dart test/widget_test.dart` → +7 passed. The settings / family mock tests and
  `test/core/network` → +117 passed (they share `MockDb.sosAlerts` / `registerAllMocks`).

## Hardening review (f-sos-harden, 2026-09-27)

Reviewer + hardener pass over the whole feature. Contract §10 and the backend module
(`family_hub_backend/src/modules/sos/*`) were compared call by call. Paths, methods, field names, enum wire names,
pagination meta and error codes all match; the mock's check order, idempotency, 3 s throttle, trail cap, lazy expiry,
message clean-up (b-sos-harden H2) and "owner's current mode" privacy rule (H3) match the backend. The b-sos-harden
item "Flutter SOS screen / mock: 140 UTF-16 units, clean-up, privacy" was already done (repository `clampMessage`,
`mockCleanSosMessage`, `mockSosAlertJson`). Guide grep (hard-coded sizes / colours / fonts, `Icons.*`, left/right,
string literals): clean.

### Findings fixed
1. **An SOS could be held back forever by a question.** With sharing `never`, the "share your location?" dialog
   waited for an answer, and the system permission prompt was awaited without a limit. Someone who cannot answer
   never alerted the family. Now:
   - the dialog answers "send without location" by itself after 10 s, with a visible countdown
     (`sosLocationDialogAutoSend`); the controller applies the same limit (`SosController.locationChoiceTimeout`).
     Silence never means "share" (privacy by default);
   - the permission prompt is awaited at most 10 s (`permissionPromptTimeout`); a later "allow" starts live
     tracking without a second prompt.
2. **Ended alerts flashed back.** `sosEndedAlertIdsProvider` was defined but never filled. The controller's `_end`
   and `SosAlertActions.resolve` (success, 409, 404) now record the id, and adoption skips recorded ids. The banner no
   longer shows "Your SOS is active" / "Priya needs help" again from a list fetched before the end.
3. **The banner and the SOS tab list blinked on every `markChanged({sos})`.** `whenData` turns a reload into a bare
   `AsyncLoading`, so `otherActiveSosAlertsProvider` lost its value during each refetch. It now keeps the last list
   as data while reloading.
4. **Polling stopped after a failed (re)load.** A refetch that failed (offline right after a change) never started
   the poller, so the banner stayed stale until restart. The active list keeps polling after a failed load. The alert
   screen also keeps polling after a transient failure, but not after 404 / 400 / NO_FAMILY / 401.
5. **Removed from the family.** A `NO_FAMILY` poll kept the last list forever (eternal "Priya needs help"). Now:
   - the list is cleared, and the session is re-read (`sosSessionResyncProvider`), which moves the app out of the
     family;
   - the same resync runs on NO_FAMILY from send, location upload, resolve and verification;
   - an own resolve that gets NO_FAMILY ends the local alert.
6. **Demoted on another phone.** `FORBIDDEN` on "Mark as helped" now re-reads the session, so the action disappears
   instead of failing again and again.
7. **First resolution wins, and the UI now says so.** When the owner said "I am okay" but an admin's "Mark as
   helped" arrived later, the idempotent response kept `safe`, yet the admin saw "The SOS was marked as helped".
   `showSosResolved(…, result:)` now shows "This SOS alert has already ended." when the stored resolution differs.
   This applies to the banner, the SOS tab and the alert screen.
8. **Rapid taps stacked screens.** The following could push the same route twice:
   - the banner's "Open", the alert tiles and "View alert details";
   - the history links and the location-settings links.

   `presentation/sos_navigation.dart` (`openSosRoute` / `openSosAlert`) ignores a tap when the router already shows
   the location or the screen is covered.
9. **Expiry while a screen is open.**
   - The alert screen's resolve buttons now disappear exactly at `expiresAt` (they tick like the header's status).
   - `SosAlertTile` now recomputes its red highlight when the alert expires; before, it was computed once per build.
   - Long names in tiles are capped at 2 lines.
10. **Family switch.** `sosAlertProvider` now watches the family id, like the list providers.
11. **Status bar (user request "make status bar transparent").** While the SOS banner was shown, the status-bar
    strip above it showed the page background. The status-bar icons also kept whatever colour the previous screen
    had chosen: white icons from the dashboard's gradient header ended up invisible on a light strip. The banner now:
    - continues its red behind the transparent status bar;
    - annotates the strip with light status-bar icons (status-bar fields only; the navigation bar is left to the
      screens).

    This is done inside `sos_status_banner.dart` (`_StatusBarBackdrop`), so `TopBannerSlot` did not need to change.
    Its `SafeArea` now also has `top: true`, which is a no-op while the slot removes the inset.
12. Mock: `mockExpireStaleSosAlerts(db, familyId)` is now public, so the member-removal cascade can expire stale
    alerts before closing the removed member's alerts (see handoffs).

### Edge-case sweep (status)
| # | Case | Handling |
|---|---|---|
| 1 | Offline / timeout while sending | 2 retries (idempotent server), then "Send again" + emergency number |
| 2 | Offline during live tracking | same fix retried after the interval; newest fix wins |
| 3 | Refetch fails right after a change | polling continues and recovers (fix 4) |
| 4 | 401 expiry mid-action | interceptor refresh; failure → session reset → tracking stops; uploader retries 401 |
| 5 | 403 FORBIDDEN (demoted admin) | error snackbar + session resync hides the action (fix 6) |
| 6 | 403 NO_FAMILY (removed) | lists cleared, tracking ended, session resync (fix 5) |
| 7 | 404 (push opens a deleted alert / deleted while open) | "Alert not available" + "Go to SOS"; polling stops |
| 8 | 409 SOS_NOT_ACTIVE on resolve / location | local alert ends, lists refresh |
| 9 | Idempotent resolve by someone else | "already ended" message (fix 7) |
| 10 | 422 | never sent: unusable coordinates dropped, message clamped to 140 UTF-16 units |
| 11 | Unanswered location question / permission prompt | auto-send after 10 s (fix 1) |
| 12 | Stale list after an alert ended | ended-ids set (fix 2), no reload flicker (fix 3) |
| 13 | Rapid repeated taps | SOS button busy guard; resolve buttons busy; single push (fix 8); dialog answers once |
| 14 | Alert expires while open | header, actions and tiles follow `expiresAt` (fix 9); server status authoritative for lists |
| 15 | Empty lists | "No one in your family needs help right now"; history empty state |
| 16 | Very long names / text | banner and tile titles max 2 lines; buttons wrap; message card wraps |
| 17 | Large text | SOS button content scales inside the circle; banner min 48 dp, 2 lines |
| 18 | Timezone / month boundaries, clock skew | all times via `Fmt` in local time; "ago" never in the future; server status wins in lists |
| 19 | Deleted / renamed member | names resolved at read time; "Former member"; card and call hidden |
| 20 | Pagination end / shifting pages | `hasMore` stops "load more"; duplicates removed by id; progress kept on refetch |
| 21 | Location permission revoked / GPS off while active | "not shared" + Allow / Open settings; re-check on resume |
| 22 | Account / family switch | every provider watches user + family id; controller teardown stops tracking |
| 23 | Two phones, same member | resolve on one → the other verifies with `GET /sos/:id` and stops |
| 24 | Status bar above the banner | red strip + light icons (fix 11) |

### Tests
- New `test/features/sos/sos_edge_cases_test.dart` (13 tests):
  - the unanswered question and prompt, and the dialog countdown;
  - the stale list after an end (no flash, no re-adoption);
  - NO_FAMILY on a poll and on send, FORBIDDEN on "helped";
  - first-wins resolution, expiry while open, deleted while open;
  - double-tap "Open";
  - the status-bar strip colour (pixel check) and icon style;
  - the mock expiry helper.
- The fixes for the flash / flicker, the double tap and the status-bar strip were checked by temporarily reverting
  them: the tests failed, and pass again with the fixes.
- Fakes: `activeGate` (slow refetch) and `promptGate` (pending permission prompt).
- Suite: 92 tests, all passing.

### Still open (other owners)
- (f-shell / design) App-wide transparent status bar:
  - In `main.dart`: `SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge)` and a transparent
    `setSystemUIOverlayStyle`.
  - In `app_theme.dart`: `AppBarThemeData.systemOverlayStyle` with `statusBarColor: Colors.transparent`.
  - `TopBannerSlot` still leaves a canvas strip above the **offline** banner.
  - The f-shell known issue "the status-bar strip uses the scaffold background" no longer applies to the SOS banner.
- (f-family) `removeMember` in `family_mock_handlers.dart` should call `mockExpireStaleSosAlerts(db, familyId)`
  before it resolves the removed member's active alerts (backend `removeMemberCascade` expires first).
- (core) Three copies of "push once" exist: `openTaskRoute` (tasks), `openFromDashboard` (dashboard) and
  `openSosRoute` (SOS). There are also three session-resync helpers: ledger, emergency card and SOS. Both belong in
  `core/router` / `shared/providers`.
- Still open from the build: the f-design `AppDurations` doc comments, the f-settings `_exportSosAlert` DRY, and
  translations (84 keys, 1 new: `sosLocationDialogAutoSend`).
- (redesign) The SOS screens still use a plain canvas `AppBar`. The design doc asks for `GradientHeaderScrollView`
  on the tab and optionally on the alert screen. The banner's status-bar handling does not depend on it.
