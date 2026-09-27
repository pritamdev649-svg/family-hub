# f-dashboard: Flutter dashboard feature (progress)

Owner: f-dashboard. Scope: `family_hub_app/lib/features/dashboard/**`, `family_hub_app/l10n_parts/dashboard.arb`,
`family_hub_app/test/features/dashboard/**`. Contract: docs/03-API_CONTRACT.md §11 (tasks DASH-03 to DASH-08).

## Built
- [x] **Domain** (`domain/dashboard_data.dart`)
  - `DashboardData` parses `GET /dashboard` and reuses `Family`, `Member`, `FamilyTask`, `SavingsGoal`, `Notice`,
    `SosAlert` and `LedgerSummary`.
  - Parsing never throws. Blank or duplicate ids are dropped. A missing `monthSummary` becomes an empty summary for
    the current month (family scope for admins, personal scope for members).
  - Derived values: `myStats`, `myPendingCount`, `hiddenMyTasksCount`, family totals, `hasOtherMembers`,
    `hasAnyTasks` and `isNewFamily`. `withoutLocations()` strips member and SOS positions.
  - It also provides `toJson`, `copyWith` and `==`.
  - `MemberStats`: counters are clamped to 0 or more, overdue is never more than pending, and a flattened row is
    accepted.
  - `DashboardSnapshot` holds `{userId, data, savedAt}`. A non-null `savedAt` marks an offline copy.
  - `dashboard_greeting.dart` has `GreetingPeriod`: morning 5–12, afternoon 12–17, evening 17–22, and otherwise a
    neutral "Hello" (no "good night"). It also has `firstNameOf`.
- [x] **Data**
  - `DashboardRepository.fetch()` with `dashboardRepositoryProvider`. A payload without `family` or `me` fails as
    `UNKNOWN`.
  - `DashboardCache` keeps the offline copy in `LocalCache` (`dashboard.last`):
    - Tagged with the user, family and format version. Copies older than 30 days are ignored.
    - Location data is never written.
    - Corrupt entries are dropped. The session clears the cache on logout.
- [x] **Mock**: `registerDashboardMocks` / `mockDashboardPayload(req, {now})`
  - Computed from `families`, `members`, `tasks`, `goals`, `notices`, `sosAlerts` and `ledgerEntries`, using the other
    features' public mock serializers (`mockTaskJson`, `compareMockTasks`, `mockGoalsList`, `mockFamilyNotices`,
    `mockActiveSosAlerts`, `mockLedgerSummary`, `MockSerializers`).
  - Counter rules match the backend (docs/progress/b-dashboard.md). Counts are per assignee. Overdue means due before
    local midnight. `completedThisWeek` is bounded to `[Monday, next Monday)`. Limits are myTasks 5, goals 3 and
    notices 3. The invite code is sent to admins only, and the summary is personal for members.
- [x] **Application** (`application/dashboard_providers.dart`)
  - `dashboardProvider` (public), an `AsyncNotifierProvider<DashboardNotifier, DashboardSnapshot>` with
    `retry: apiRetryPolicy`. It watches `sessionUserIdProvider`, the family id, `isAdminProvider` and the whole
    `dataRefreshProvider` (all DataScopes).
  - Offline fallback when the server is unreachable (network, timeout, 5xx):
    - It returns the saved copy.
    - On a slow first load it shows the copy after 2 s, or right away when the app already knows it is offline.
    - When connectivity comes back it refetches by itself.
  - `NO_FAMILY` clears the copy and resyncs the session.
  - A resync also runs when the server reports another member, role or family than the session. Each mismatch is
    resynced at most once, so it cannot loop.
  - `dashboardViewProvider` is what screens watch. It never exposes a snapshot of another account or family. Riverpod
    keeps the previous value during a reload, so without it the old account's data could flash after an account
    switch.
  - `refreshDashboard(ref)` is the pull-to-refresh: `markAllChanged()` and then it awaits the dashboard.
  - `dashboardActiveSos(...)` prefers the live `activeSosAlertsProvider` list. An offline copy only keeps alerts whose
    15-minute window has not passed.
  - Injectable for tests: the clock, the fallback delay, the session refresh and the live SOS feed.
- [x] **Presentation**: `DashboardScreen`, the Home tab
  - Top to bottom:
    - Offline notice with a retry button (offline copy only).
    - Header: date, a greeting with the first name, then "Family · designation" (falls back to the role).
    - Active SOS alerts (`SosAlertTile`), only while there are any.
    - Quick actions as tonal buttons: Add task, Add expense, Post notice, Emergency cards.
    - Getting-started checklist for new families (DASH-05). It is role aware: the member and goal steps are for admins
      only.
    - My tasks: up to 5 `TaskTile`s, "See all" opens the Tasks tab, and a "+N more" link appears when there are more.
    - Family board: avatar, name, "You" badge, designation, pending / overdue / done-this-week chips. Tapping a card
      opens `/members/:id`.
    - Goals (`GoalProgressCard`, empty state with "New goal" for admins).
    - This month (`MonthSummaryCard`; the scope comes from the server).
    - Latest notices (`NoticeCard` in compact mode, "See all" opens `/notices`).
  - Pull to refresh, and a static skeleton while loading.
  - Responsive: from `DashboardLayout.wideMinWidth` (scaled by the text size) the board uses 2 columns and the quick
    actions one row of four. Grid rows share the height of their tallest card.
  - Uses design tokens only, and every text is localised. RTL-safe and safe with large text (tested at 1.6× in RTL on
    a 320 dp phone).
  - Navigation goes through `AppRoutes` with a push guard that stops double taps from stacking screens.
- [x] **l10n**: `l10n_parts/dashboard.arb` has 38 keys, all prefixed `dashboard`, using ICU select and plural. Merged
      and generated with `dart run tool/l10n.dart`.
- [x] **Tests**: 71 tests in `test/features/dashboard/`, all passing.
  - `dashboard_data_test.dart` (19): parsing, defensive defaults, clamping, round trip, stripping locations, greeting,
    cache (same account and family only, no locations on disk, corrupt entries, versions).
  - `dashboard_providers_test.dart` (22):
    - Load and save. Refetch on every DataScope and on a role change. The signed-out case.
    - Offline fallback (network, 5xx, no copy, another account's copy, other errors).
    - Resync on `NO_FAMILY` and on a mismatch, once each.
    - Slow first load, known-offline start, refetch when back online.
    - `dashboardViewProvider` hides another account's or family's data.
    - The SOS merge rules.
  - `dashboard_mock_handlers_test.dart` (9):
    - Shape and member order. Counters cross-checked against the tasks mock's `/tasks` filters.
    - myTasks order and limit. Goal and notice limits.
    - Member scope. Week and overdue boundaries with a fixed clock.
    - Active SOS. 401 and 403 `NO_FAMILY`. Route registration.
  - `dashboard_screen_test.dart` (20):
    - All sections render. SOS comes first, and the live SOS list wins.
    - New-family checklist. The member view has no admin actions.
    - Skeleton, error with retry, offline copy notice with retry, pull to refresh.
    - Seven navigation targets.
    - Phone, wide, large-text and RTL layouts.
  - `dashboard_mock_backend_test.dart` (1): the real repositories against the seeded mock backend. Completing a task
    from the dashboard refetches it through the data-change bus.

## Decisions
- `dashboardProvider` holds a `DashboardSnapshot`, not a bare `DashboardData`. That is how the UI knows whether it
  shows the offline copy and which account the data belongs to. No other feature used the provider.
- Quick actions use `FilledButton.tonal` directly because `AppButton` has no tonal variant (handoff below).
- The members "alone" hint lives in the getting-started checklist, so there is no duplicate call to action on the
  board.
- The dashboard's SOS section uses the live, polled SOS list when it is available, so it always agrees with the
  `SosStatusBanner`.
- Pull to refresh bumps every DataScope (`markAllChanged`), as `DataRefresh` documents for the dashboard.

## Pending
- [ ] Translations of the 38 `dashboard*` keys in `lib/l10n/app_<lang>.arb` (translation agents).
- [ ] The getting-started checklist cannot be dismissed. It hides by itself once the family is set up.

## Known issues
- Mock mode uses device local time for "today" and "this week" instead of the family time zone. The tasks and ledger
  mocks do the same. The real backend uses the family time zone.
- On a slow first load, `refreshDashboard` can resolve as soon as the offline copy is shown. The spinner stops while
  the request keeps running, and the fresh data still replaces the copy when it arrives.

## Handoffs
- [ ] Core widgets owner: add `AppButtonVariant.tonal` to `AppButton`, then the quick actions can use it.
- [ ] Core widgets owner: promote a compact section empty card to `lib/core/widgets/`. Ledger's `SectionEmptyCard` and
      dashboard's `DashboardEmptyCard` are the same widget.
- [ ] Core widgets owner: promote a shared "push once" navigation guard to `lib/core/router/`. The tasks
      (`openTaskRoute`), family (`pushIfTop`), ledger (`LedgerOpenGuard`) and dashboard features each have their own.
- [ ] Design owner: add a layout breakpoint token to `AppSizes`. The dashboard derives
      `DashboardLayout.wideMinWidth = AppSizes.maxContentWidth * 0.75`.
- [ ] Docs owner:
  - Note in docs/05-FLUTTER_GUIDE.md §10 that `dashboardProvider` holds a `DashboardSnapshot` and that screens watch
    `dashboardViewProvider`.
  - Tick DASH-03 to DASH-08 in docs/TASKS.md.
