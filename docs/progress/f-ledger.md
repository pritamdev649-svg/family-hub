# f-ledger: Flutter "ledger" feature (Money tab, entries, savings goals)

Owner: f-ledger · Scope: `family_hub_app/lib/features/ledger/**`, `family_hub_app/l10n_parts/ledger.arb`,
`family_hub_app/test/features/ledger/**` · Contract: docs/03-API_CONTRACT.md §8

## Built

### Domain (`domain/`)
- [x] `ledger_entry.dart`: `LedgerType` (income|expense), `LedgerCategory` with contract wire names (`other_income`,
      `household_help`…), `type`, `isIncome`, `isOther`, `isGoalOnly`, `incomeCategories`, `expenseCategories`,
      `forType`, `manualFor` (per-type list without `savings`, which comes only from goal contributions), `fromWire`
      (unknown or wrong-type → the type's `other_*`). `LedgerEntry` has defensive `fromJson` (type inferred from the
      category, negative amounts made positive, date-only `date` → local calendar day), `toJson`, `copyWith`, ==,
      `isGoalLinked`, `signedAmount` and `canBeModifiedBy` (admin or creator).
- [x] `savings_goal.dart`: `GoalStatus`, `SavingsGoal` (`progress` clamped 0–1 and computed when missing, `remaining`
      never negative and rounded to cents, `daysLeft({now})` in calendar days, DST-safe, `isOverdue`,
      `acceptsContributions`), `GoalContributionResult {goal, entry}`.
- [x] `ledger_summary.dart`: `SummaryScope` (family|personal), `CategoryTotal`, `LedgerSummary` (sorted `byCategory`,
      `net` falls back to income − expense, `isEmpty`, `categoriesOf`, `breakdown(type, maxItems: 6)`),
      `CategoryBreakdown` (top N plus `rest`; `other_*` always goes into `rest`, so the UI never shows two "Other" rows).
- [x] `ledger_requests.dart`: `LedgerLimits`, `roundMoney`, `LedgerEntryQuery` (family key, value equality),
      `LedgerEntryInput`, `LedgerEntryPatch.diff` (only changed fields; never sends the amount of a goal-linked entry),
      `GoalInput`, `GoalPatch.diff` / `GoalPatch.status`, `GoalContributionInput`. Date-only values are sent as
      local midnight in UTC (`toApiDate`).

### Data (`data/`)
- [x] `ledger_repository.dart`: `LedgerRepository` (`listEntries` paged, `createEntry`, `updateEntry` (empty patch → no
      request), `deleteEntry`, `summary`) + `ledgerRepositoryProvider`.
- [x] `goal_repository.dart`: `GoalRepository` (`listGoals(status)`, `createGoal`, `updateGoal`, `deleteGoal`,
      `contribute`) + `goalRepositoryProvider`, `GoalListFilter`.
- [x] `ledger_mock_handlers.dart` (`registerLedgerMocks`). Money is stored in integer minor units, like the backend.
  - `GET /ledger/entries`: month/type/memberId/goalId filters (bad month or type → 422). Admins see every entry;
    members see entries that are theirs or that they created. Sorted by date desc, then createdAt. Paginated.
  - `POST /ledger/entries`: validates type, the category for that type, amount > 0 and ≤ 1e12, note ≤ 200, and
    date ≤ tomorrow (required). A member recording for someone else gets 403. Another family's member id gets 404.
  - `PATCH` / `DELETE /ledger/entries/:id`: an entry the caller can't see is 404; not admin or creator is 403.
    Changing a goal-linked entry's amount is 422. Deleting a contribution lowers the goal's saved amount (never below 0)
    and reopens the goal if it drops below the target.
  - `GET /ledger/summary`: admins get family scope, members personal scope (`memberId = self`). Defaults to the current
    month. Returns `byCategory` sorted by amount.
  - `/goals` CRUD: admin only; list is active → achieved → archived. A contribution creates an `expense/savings` entry
    and moves the goal to achieved once saved ≥ target. Contributing to an archived goal returns
    **409 `VALIDATION_ERROR`** (the contract's wording). A status PATCH re-derives active/achieved from the saved
    amount. Deleting a goal detaches its entries (`goalId → null`).
  - Seed (demo family only, once per DB): 41 realistic INR entries for the previous and current month (salaries,
    rent, household help, groceries, school fees, utilities, pocket money, a Kamla ji health entry, FD interest,
    home-bakery income…). Current-month days are clamped to today. Goal **"Goa vacation"**: ₹60,000 target, target date
    +5 months, ₹12,500 saved through 2 linked contributions (`progress 0.2083`, same as the contract example).
  - Public helpers for the dashboard mock: `mockLedgerSummary(req, {month})`, `mockGoalsList(req, {status})`,
    `mockGoalJson`, `mockEntryJson`, `mockGoaGoalId`, `seedLedgerMockData(db, {now})`.

### Application (`application/ledger_providers.dart`)
- [x] `selectedLedgerMonthProvider` (`SelectedLedgerMonth`: previous / next (never past the current month) /
      select, resets on account switch) + `currentLedgerMonth`, `clampLedgerMonth`, `canGoToNextMonth`.
- [x] `ledgerSummaryProvider(monthKey)`, `recentLedgerEntriesProvider(monthKey)` (10), `savingsGoalsProvider`,
      `savingsGoalProvider(id)` (read from the list, since the contract has no `GET /goals/:id`, NOT_FOUND when missing).
      All watch `sessionUserIdProvider` plus their `DataScope`s and use `apiRetryPolicy`.
- [x] `ledgerEntriesProvider(LedgerEntryQuery)` → `LedgerEntriesController` (page 1 on every ledger change,
      `loadMore` with a generation guard against stale pages, de-dupe by id, keeps loaded items and rethrows on error).
- [x] `ledgerActionsProvider` → `LedgerActions`: every successful mutation calls
      `markChanged({DataScope.ledger, DataScope.goals})`. Empty patches and failures mark nothing.

### Presentation
- [x] `ledger_labels.dart`: labels/icons/colours for `LedgerType` (+ `flow` for `MoneyText`), `LedgerCategory` (18 const icons),
      `GoalStatus`, `SummaryScope`.
- [x] **Public** `MonthSummaryCard(summary, {onTap, showMonth})` and `GoalProgressCard(goal, {onTap})` (defaults to
      `AppRoutes.goalDetail`), plus `goalDeadlineLabel(...)`.
- [x] `MoneyScreen` (tab):
  - month switcher (prev/next, next disabled on the current month, tapping the label opens a month-list sheet)
  - `MonthSummaryCard` (Family/Personal chip) and category bars: expense/income toggle, top 6 + Other
  - goals section: active and achieved goals, archived ones behind a "Show n archived" toggle, "New goal" for admins,
    empty text that differs for admins and members
  - recent 10 entries + "See all", a FAB (Add entry → income/expense choice), and the "Records only – no real money is
    moved." caption
  - pull to refresh; each section has its own loading / error (retry) / empty state
- [x] `EntriesScreen` (`/money/entries`):
  - starts on the Money tab's month; filters are month (including "All months"), type chips, and member (admins only)
  - members see a caption about which entries they can see
  - paginated `PaginatedListView`; empty state with "Clear filters"
  - the filters stay on screen while a new filter combination loads
- [x] Entry details bottom sheet: shows category, date, owner, "added by", note and the goal link. Edit/delete are shown
      only to admins or the creator. Delete asks for confirmation (with a special message for contributions). Errors are
      shown inline, because a snackbar would be hidden behind the sheet.
- [x] `EntryFormScreen` (`/money/entries/new?type=`; edit mode = the same route with the entry in `extra`):
  - type segmented button; amount field with the currency symbol from `Fmt` in the label
  - `DecimalAmountInputFormatter`: locale decimal separator, max 2 decimals, native digits
  - `Validators.amount`; category chips with icons, filtered by type and reset when the type changes, validated
  - date ≤ tomorrow; note ≤ 200
  - member dropdown for admins; members are locked to themselves and see an explanation
  - goal-linked entries lock amount, type and category and show a notice
  - busy button, localized errors, "discard changes?" guard, `markChanged` via `LedgerActions`
- [x] `GoalFormScreen` (`/money/goals/new`, `/money/goals/:id/edit`): admins only (members see an explanation). Fields are
      title 1–80, target, optional target date and description. Edit sends a diff. Includes the discard guard.
- [x] `GoalDetailScreen` (`/money/goals/:id`): progress bar and percentage; saved, target and still-to-go; target date
      with days left or overdue; status chip; achieved and archived notices; "Contribute" (disabled when archived)
      opens a bottom sheet (amount, note, inline errors, archived-goal message) and celebrates with a dialog when
      the goal is reached. The contributions list is paginated with "Load more" (members get a note that they see only
      their own). An admin menu offers Edit, Archive/Restore (with confirm) and Delete (destructive confirm, then pop).
- [x] `ledger_routes.dart`: `ledgerRoutes` for `/money/entries`, `/money/entries/new`, `/money/goals/new` (before `:id`),
      `/money/goals/:id`, `/money/goals/:id/edit`. All navigation goes through `AppRoutes`.
- [x] `l10n_parts/ledger.arb`: 144 `ledger*` keys (ICU plurals for days left / overdue / archived count) with descriptions.

### Tests (`test/features/ledger/`, 102 tests)
- [x] `domain/ledger_models_test.dart` (23): wire names, fallbacks, defensive parsing, progress/remaining/daysLeft,
      breakdown top 6 + Other, patch diffs, and that the goal-linked amount is never sent.
- [x] `data/ledger_mock_handlers_test.dart` (22): seed, visibility, filters, pagination, validation, 403/404 rules,
      summary scopes, contributions and the achieved transition, archived → 409, deleting a contribution reopens the
      goal, deleting a goal detaches its entries.
- [x] `data/ledger_repositories_test.dart` (6): repositories end to end through `ApiClient` + `MockInterceptor`.
- [x] `application/ledger_providers_test.dart` (12): month notifier, providers when signed out, NOT_FOUND goal,
      paging, load-more failure, refresh from page 1, `LedgerActions` scopes.
- [x] `presentation/*` (39): Money screen (admin, member, month switch, month picker, error + retry, FAB → form, entry
      sheet delete), entry form (validation + create, type switch, member lock, goal-linked edit, discard guard), goal
      card, detail, contribute + celebrate, archived, not found, delete, goal form (create, edit diff, member blocked),
      entries list (filters, load more, empty + clear, member caption), amount formatter, and a check at 320 dp,
      1.6× text and RTL on every screen (it found and fixed two overflows). Plus one Money-tab test against the real
      mock backend.

## Pending / known issues
- [ ] There is no dedicated edit route for entries: edit mode reuses `/money/entries/new` with the entry passed as `extra`.
      The contract has no `GET /ledger/entries/:id`, so an edit route could not load the entry by id anyway. As a result,
      edit links can't be deep-linked or restored after the process is killed.
- [ ] The month picker lists the last 36 months (plus the selected month if it is older); the back arrow reaches anything
      older. It is based on the device-local month; the backend uses the family timezone (they can differ around
      midnight on the 1st).
- [ ] Money amounts use a fixed 2-decimal scale (contract). Zero-decimal currencies (e.g. JPY) still accept 2 decimals.
- [ ] The goal detail uses `AppSpacing.md` as the height of its large progress bar (there is no `AppSizes` token for a
      hero progress bar).
- [ ] Translations of the 144 new keys (only English exists).

## Decisions
- Manual entries can't use the `savings` category (it comes only from goal contributions). It is still kept when
  editing an entry that already uses it.
- Personal summary scope = entries whose `memberId` is the caller (whose money it is). Entry visibility for members
  = `memberId == self || createdById == self` (contract).
- Restoring an archived goal sends `status: active`. The mock (and suggested backend behaviour) re-derives `achieved`
  when saved ≥ target.
- Contribution date = today (local midnight). The contribute sheet has no date field.

## Hardening pass (f-ledger-harden, 2026-09-27)
Full report: `docs/progress/f-ledger-harden.md`. Summary of fixes:
- [x] **Mock mirrors the backend**: check order 400 → 422 → 404 → 403 → business 422; unknown or other-family
      `memberId` → `422 details.memberId` (was 404); goal-linked entries also lock type and category; date window
      now has its lower bound (2000-01-01); live `memberName`; `byCategory` tie-break; malformed ids → 400.
- [x] **Stale data**: `LedgerActions` refreshes the lists on 404, 409 and timeout, refreshes members on
      `422 memberId`, and resyncs the session on 403 / NO_FAMILY. Reads that return NO_FAMILY resync too. Summary and
      entry lists refetch when the role changes.
- [x] **Deleted / archived records**: new `GoalNotFoundView` (detail and edit form). Deleting something already
      deleted counts as done (entries and goals). Edit forms close when their record is gone. Specific messages via
      `presentation/ledger_errors.dart`.
- [x] **Removed members**: "Former member" labels; a note in the form when editing a removed member's entry; the
      entries member filter no longer hits a DropdownButton assertion when the filtered member leaves.
- [x] **Rapid taps**: `presentation/ledger_open_guard.dart` (a double tap on a goal card pushed two screens); the
      contribute sheet can't be closed with back or a barrier tap while saving.
- [x] **UX**: the breakdown defaults to income when a month has income but no expenses; the last non-directional
      paddings became `EdgeInsetsDirectional`.
- [x] Tests 102 → 137 (new `presentation/edge_cases_test.dart`; mock and provider edge cases).
