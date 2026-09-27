# f-ledger-harden: review + hardening of the Flutter ledger feature

Owner: f-ledger-harden · Scope (same as f-ledger): `family_hub_app/lib/features/ledger/**`,
`family_hub_app/l10n_parts/ledger.arb`, `family_hub_app/test/features/ledger/**` · Contract: docs/03-API_CONTRACT.md §8,
backend reference: `family_hub_backend/src/modules/ledger/**`.

## 1. Contract conformance (repositories + mock) 
- [x] Repositories: every path, method, body field, enum wire name and the pagination meta match §8. Null query values
      are dropped by `ApiClient`, so no `month=null` is sent. No changes needed.
- [x] Mock handlers now use the backend's check order: `401` → `403 NO_FAMILY` → `403 FORBIDDEN` (admin-only goal
      writes) → `400 BAD_REQUEST` (malformed `:id`) → `422` (malformed body/query, all problems at once) → `404` →
      `403` (role) → `422` business rules.
- [x] Mock fixes, matching the backend:
  - admin + unknown/other-family `memberId` → `422 details.memberId` (was 404)
  - malformed ids → 400; malformed `memberId`/`goalId` query → 422
  - goal-linked entries also lock `type` and `category` (not only `amount`)
  - date window 1 Jan 2000 … tomorrow (lower bound was missing), plus the coarse 2000–2100 range for `targetDate`
  - `memberName` is the member's current name (stored snapshot for removed members)
  - `byCategory` ties sorted income first, then by category
  - a member recording for someone else gets 403 before the date-window check
  - `PATCH memberId: null` → 422; `amount` must be ≥ 0.01
  - `mockEntryJson(e, {db})` keeps its old call shape for the settings export mock

## 2. Guide conformance
- [x] Tokens: no hard-coded sizes, colours or fonts. The grep hits were `semanticColors` / `AppColors` false positives.
- [x] RTL: the last `EdgeInsets.fromLTRB` / `.only` in the feature became `EdgeInsetsDirectional`. Chevron icons
      mirror automatically (`matchTextDirection`).
- [x] l10n: no user-visible literals. 15 new `ledger*` keys (159 in total).
- [x] AsyncValueView everywhere. The only exception is a deleted goal, which gets a dedicated `GoalNotFoundView`
      instead of a Retry that can never succeed.
- [x] `markChanged` after every mutation (through `LedgerActions`), `mounted` checks after awaits, busy buttons.

## 3. Edge-case sweep (all handled; tests in brackets)
| # | Edge case | Handling |
|---|---|---|
| 1 | Offline / 5xx on load | Per-section ErrorView with Retry; previous data kept with a stale notice; 2 automatic retries (`apiRetryPolicy`). |
| 2 | Timeout on a write (it may have succeeded) | `LedgerActions` refreshes the lists; the message says to check the list before retrying [edge: timed-out save]. |
| 3 | 401 expiry mid-action | Core single-flight refresh + retry; on failure the router signs out. Every screen checks `mounted`. |
| 4 | 403 because the role changed | Specific message, plus a background session resync, so admin UI disappears [edge: 403 on delete; providers: FORBIDDEN resync]. |
| 5 | 403 NO_FAMILY (removed from the family) | Reads and writes resync the session, so the router goes to family setup [providers: NO_FAMILY read]. |
| 6 | Role change while a screen is open | Summary, recent entries and entry lists watch `isAdminProvider` and refetch (scope/visibility follow the role) [providers: role change]. The entries screen drops the member filter for non-admins. |
| 7 | Entry deleted by someone else, then deleted here | Treated as done: the sheet closes with "already deleted" and the lists refresh [edge]. |
| 8 | Entry deleted by someone else, then edited here | The error explains it and the form closes [edge]. |
| 9 | Goal deleted: stale link / push, while viewing, while editing, while contributing | `GoalNotFoundView` with "Back to Money"; the edit form shows it too; contribute and archive give specific errors and refresh the lists; a second delete counts as done [edge ×5, goal_screens]. |
| 10 | Goal archived meanwhile (409 VALIDATION_ERROR) | Archived message; the lists refresh, so the detail shows the archived notice [edge]. |
| 11 | 422 whose field the form can't know about (member left, family time zone date, amount, category) | Mapped from `details` to specific text; `memberId` also refreshes the members list [edge ×2]. |
| 12 | Member deleted or renamed but still on records | Live name when known, stored snapshot otherwise. "Former member" for a creator who left; a note in the form when editing a removed member's entry (the owner is kept); the member filter keeps a removed member instead of hitting a DropdownButton assertion [edge ×3]. |
| 13 | Rapid repeated taps | Submit and delete were already guarded. New `LedgerOpenGuard` for pushes and sheets: a double tap on a goal card pushed two screens before this fix [edge ×3; a mutation test confirmed it]. The contribute sheet can't be closed with back or a barrier tap while saving. |
| 14 | Pagination end / overlapping pages | `loadMore` is a no-op at the end [providers]; de-dupe by id; a generation guard stops a stale page being appended (builder). |
| 15 | Empty data | Empty month, no goals (different text for admin and member), filtered-empty with "Clear filters", no contributions (builder). A month with only income now defaults the breakdown to income [edge]. |
| 16 | Very long text / big amounts / large text / RTL | Builder's check at 320 dp, 1.6× text and RTL on every screen; FittedBox amounts; titles wrap or ellipsize. |
| 17 | Month / time-zone boundaries | Dates are calendar days (`calendarDate`); the server's date window, which can be ±1 day off the device, maps to a clear message. Months later than the current one are not offered. |
| 18 | Stale data after another member's change | Pull to refresh, own mutations, and now 404/409/timeout refresh the lists. There is no realtime channel; see handoff 2. |

## 4. Tests: 102 → 137, all passing
- [x] `data/ledger_mock_handlers_test.dart` (+8): format-before-window, 403 order, 422 memberId, live names,
      400/422 ids, PATCH order, goal-linked type/category lock, summary tie-break, empty month, goal write order,
      contribution order and date window.
- [x] `application/ledger_providers_test.dart` (+7): 404/409/timeout refresh, 422 memberId → members, FORBIDDEN and
      NO_FAMILY resync, shared resync (also when the refresh throws synchronously), role-change refetch,
      loadMore at the end.
- [x] `presentation/edge_cases_test.dart` (new, 20).
- [x] `goal_screens_test.dart`: the unknown-goal test now expects the not-found view and the way back.
- [x] Mutation check: disabling the goal-card guard, the stale-member item or the breakdown default each makes a test
      fail. The two sheet double-tap tests are behaviour checks only, because Flutter's Navigator already absorbs
      same-frame taps on a synchronous push.

## Pending / known issues
- [ ] Editing an entry still passes it as go_router `extra`, because the contract has no `GET /ledger/entries/:id`.
      Edit screens can't be deep-linked or restored (builder decision, unchanged).
- [ ] The contract has no idempotency key. A create that times out and is retried can be recorded twice. The UI warns
      and refreshes the list, but can't prevent it.
- [ ] `LedgerOpenGuard` checks `ModalRoute.isCurrent` on the nearest navigator. On the Money tab (a shell branch
      navigator) a pushed top-level page does not make the tab non-current, so only the one-frame pending flag
      protects there. That flag covers the double-tap case (test).
- [ ] The contribute sheet can still be dragged down while saving; the contribution is still recorded and refreshed.
- [ ] Translations of the 159 ledger keys (15 new).
- [ ] `ledger_errors.dart` sends a localized text through `showError` using a private `ApiException` subclass,
      because `SnackX` has no error-text API (handoff 1).

## Handoffs (files I do not own)
1. **f-core (`lib/core/widgets/snackbars.dart`)**: add `SnackX.showErrorMessage(String)` (error-styled, text already
   localized). `ledger_errors.dart` would then drop `_LocalizedLedgerError`.
2. **f-shell / settings (`HomeShell` or `features/settings/application/background_sync.dart`)**: call
   `ref.read(dataRefreshProvider.notifier).markAllChanged()` on app resume. Nothing calls it today, so money, tasks
   and notices changed by other members only appear after pull to refresh.
3. **docs owner (`docs/03-API_CONTRACT.md` §8)**: document the backend rules the mock now mirrors: unknown member →
   `422 details.memberId`; goal-linked entries lock type and category; date window 2000-01-01 … tomorrow in the
   family time zone; `memberName` is the live name; `byCategory` tie-break; archived → `409 VALIDATION_ERROR` with
   `details.goalId`.
4. **Dashboard owner**: `GoalProgressCard` is now a `ConsumerStatefulWidget` (double-tap guard). Its constructor API
   `GoalProgressCard(goal, {onTap})` is unchanged.
5. **Translation agents**: 15 new `ledger*` keys in `l10n_parts/ledger.arb`.
