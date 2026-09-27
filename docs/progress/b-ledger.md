# b-ledger: Backend ledger and savings goals (progress)

Owner: b-ledger · Scope: docs/03-API_CONTRACT.md §8 · Files: `family_hub_backend/src/modules/ledger/**`,
`src/i18n/locales/en/ledger.json`, `tests/ledger.test.js`.

## Built

### Routes (mount points already in `src/routes/index.js`)
- [x] `ledger.routes.js`: `/ledger`. Every route requires `requireAuth` and `requireFamily`.
  - `GET /entries`: filters `month` (family time zone), `type`, `memberId`, `goalId`; `date` desc, then newest first; paginated.
  - `POST /entries` → 201.
  - `PATCH /entries/:id`.
  - `DELETE /entries/:id` → `null`.
  - `GET /summary`.
- [x] `goals.routes.js`: `/goals`.
  - `GET /`: any member.
  - `POST /`, `PATCH /:id`, `DELETE /:id`: admin only (`requireAdmin`).
  - `POST /:id/contributions`: any member → 201 `{ goal, entry }`.
- [x] Each route is layered as routes → controller → service. Validation uses zod in `ledger.schemas.js` and `goals.schemas.js`.
      Controllers set `Cache-Control: private, no-store` because this is financial data.

### Rules implemented
- [x] Family scoping on every query. A resource from another family, or an unknown id, returns 404. A malformed id returns 400.
- [x] Visibility: admins see every entry. Members see entries where `memberId` or `createdById` is themselves. Entries a member cannot see return 404 on PATCH/DELETE. A member who can see an entry but did not create it gets 403.
- [x] Create: a member may only use `memberId` = self (403 otherwise). An admin may use any member of the family. A member id from another family or an unknown one returns `422 details.memberId`, never 404, matching tasks.
- [x] Category must be valid for the type. This is checked by zod when both are sent, and by the service against stored values on PATCH.
- [x] Amounts must be > 0 and ≤ 1e12, and at least 0.01. They are stored as integer minor units through `lib/money.js` (1.005 → 101).
- [x] Business dates:
  - They are stored as **family-local midnight**. `YYYY-MM-DD` becomes midnight of that day in the family zone. An ISO date-time is snapped to the nearest family-local midnight, which absorbs a phone in another zone (up to ±12 h).
  - Allowed window: 2000-01-01 … tomorrow in the family zone (`date ≤ today + 1 day`).
- [x] Goal-linked entries: the amount is locked (`422 details.amount`), and so are type and category (a contribution stays `expense/savings`). Note, date and owner stay editable. The same amount, re-sent, is accepted.
- [x] Deleting an entry:
  - A goal-linked entry is removed with `findOneAndDelete`, so a double delete never subtracts twice.
  - The goal is updated with a clamped pipeline, `max(0, saved − amount)`.
  - An achieved goal that drops below its target is reopened (`active`, `achievedAt = null`). Archived goals stay archived.
- [x] Summary: aggregation `$match` on the family-time-zone month range (`{familyId, date}` index), then `$group` by type/category.
  - Admins get `scope: family`. Members get `scope: personal` (their `memberId`).
  - `byCategory` is sorted by amount desc, then income first, then category.
  - `month` defaults to the current month in the family zone.
- [x] `getMonthSummary({ familyId, memberId /* null → family */, month, timeZone, currency })` is exported from `ledger.service.js` for the dashboard. It loads zone and currency from the family when they are omitted.
- [x] Goals:
  - List: active first, then achieved, then archived; newest first within a status. Returned as a plain array (the contract has no pagination here). `?status=` defaults to `all`.
  - Create is admin only and returns 201.
  - PATCH is admin only. `status: archived` archives the goal. `active` or `achieved` restore an archived goal, and the saved amount decides which (an unfinished goal can never be marked achieved by hand). Changing the target re-derives the status.
  - DELETE is admin only. Linked entries are kept, with `goalId` set to null.
- [x] Contributions:
  - An atomic conditional `$inc` on `savedMinor` (the goal must not be archived, and the total cannot overflow).
  - Creates an `expense/savings` entry owned by the caller. The date defaults to today in the family zone.
  - If creating the entry fails, the `$inc` is reverted.
  - An archived goal returns **409 `VALIDATION_ERROR`** with `details.goalId`.
- [x] Status transitions (`goals.balance.js#reconcileGoalStatus`) are conditional updates, so concurrent requests converge. Only the request that wins the `active → achieved` transition sends `goal_achieved`. The push goes to the whole family: route `/money`, keys `ledger.push.goalAchieved.*`, fire-and-forget.
- [x] One 422 response reports all service-level problems (`ValidationIssues`). The top-level message is the specific `ledger.errors.*` text when there is only one problem.
- [x] Serializers: `ledger.serializer.js` (`serializeEntry`, `serializeEntries`, `serializeGoal`, `serializeGoals`) produce the exact contract shapes. `memberName` is the member's current name, falling back to the stored snapshot. `progress` comes from the model virtual, including for lean objects.
- [x] `goals.service.js#listActiveGoals(familyId, { limit })` is exported for the dashboard.
- [x] `src/i18n/locales/en/ledger.json`: push texts and every `ledger.errors.*` message.

### Tests (`tests/ledger.test.js`, 54 tests)
- [x] Auth and no-family checks on every route; exact envelopes and shapes; minor-unit storage and rounding; pagination meta.
- [x] Create validation (every field, category per type, amount bounds, note, date window, time-zone normalisation, read-only keys stripped).
- [x] List visibility, sorting, filters (including the month boundary in IST and in New York), blank filters, 422 on bad queries, live name with snapshot fallback.
- [x] PATCH permission matrix (403, 404, other family 404, 400), type/category pairs, null handling, owner changes, goal-linked locks.
- [x] DELETE: goal decrement, reopening, clamp at 0, archived goals, parallel deletes, dangling goal links.
- [x] Summary: family and personal scope, byCategory ordering, default month, empty month, time-zone boundaries, family isolation, direct `getMonthSummary` calls.
- [x] Goal CRUD and validation, ordering and filter, permissions, target-driven status and push, archive and restore (no push on restore), delete detaching entries.
- [x] Contributions: happy path, achieved plus exactly one push, overshoot, 10 concurrent contributions (atomic, one push), archived → 409, 404/400/422, dates.
- [x] i18n keys and localized error message.

## Pending / not in scope
- [ ] Translations of `ledger.json` into the other 14 locales (translation agents).
- [ ] Dashboard wiring: `getMonthSummary` and `listActiveGoals` are ready. The dashboard owner must call them (handoff).
- [ ] Contract doc updates for the decisions below (docs owner).

## Known issues / decisions
- Archived-goal contributions return HTTP **409** with code `VALIDATION_ERROR`, the literal reading of "409 CONFLICT-style VALIDATION_ERROR". This matches the Flutter mock.
- Lowering a goal's target to or below the saved amount achieves the goal and sends `goal_achieved`, like a contribution does. Restoring an archived goal that was already complete does not send a push.
- Business dates are normalised to family-local midnight. Clients that send a real timestamp instead of a local midnight (contract violation) are snapped to the *nearest* midnight.
- Manual entries with category `savings` are allowed (the contract lists it as an expense category). Only contributions set `goalId`.
- There is no `GET /ledger/entries/:id` or `GET /goals/:id`: they are not in the contract, and the app does not use them.
- Without MongoDB transactions (standalone in-memory server), a contribution uses compensation. If the goal is deleted mid-request, the new entry is removed and the request returns 404.

## Hardening review (b-ledger-harden)

An adversarial review ran against the live API (scratch probe suites) with the same files owned. Every confirmed issue
has a fix and a regression test in the `hardening:` suites of `tests/ledger.test.js`.

### Findings and fixes
- [x] **Text lengths were counted in code points.** zod 4's `.max()` counts code points, while Mongoose `maxlength` and the
      app (Dart `String.length`) count UTF-16 units. 101–200 emoji passed zod and then failed in Mongoose with a raw 422 that
      **echoed the user's text** (`Path \`note\` (\`😀😀…\`, length 202) is longer …`).
      - Affected: notes, goal titles and descriptions, on POST and PATCH, and contribution notes.
      - Fix: limits are now checked in UTF-16 units (`ledger.schemas.js#maxUnits`) and return clean messages.
- [x] **Text normalisation was missing.** Fix: notes and descriptions now follow the task / notice rules (`optionalMultiLineText`):
      - Text is made well-formed, so a lone surrogate becomes U+FFFD, which is what MongoDB stores. The response used to differ from the stored value.
      - CRLF becomes LF, and NUL, BEL and other control characters are removed.
      - Text made only of invisible characters becomes `null`.
- [x] **Goal titles** could be a lone zero-width space, and could hold newlines or tabs (they show in the push).
      - Now single-line (`toSingleLine`), with at least one visible character (`Title is required`).
- [x] **`goal_achieved` push spam.** A member could loop "contribute → delete their contribution → contribute" and push
      the whole family on every cycle.
      - Fix: `achievedAt` now means "when the current target was last reached". It is kept when the goal reopens, and
        re-reaching the target within `GOAL_ACHIEVED_NOTIFY_COOLDOWN_MS` (24 h) sends nothing.
      - A *new* target (an admin changes `targetAmount` and the goal is not still achieved) clears it, so reaching the new
        target notifies again (`clearAchievementForNewTarget`).
      - The `active → achieved` transition is one `findOneAndUpdate` (`returnDocument: 'before'`). Exactly one request wins,
        and it sees the previous `achievedAt`.
- [x] **A `goal_achieved` push could be lost.** When an entry deletion (or the compensation path) won the transition,
      because a concurrent contribution's `$inc` landed first, nobody sent the push. Every winner now sends it.
- [x] **Goal `targetDate` had no day window** (`1999-12-31` was stored). It must now be a family-local day within
      2000-01-01 … 2100-12-31 (`422 details.targetDate`, key `ledger.errors.targetDateRange`). Past days are still fine.
- [x] **Dangling goal links.** An entry whose goal vanished without being detached (a goal deletion interrupted between its
      two steps) stayed amount-locked forever. PATCH now unlinks it (`goalId → null`) and edits it like any entry.
- [x] **Dashboard helpers.**
      - `getMonthSummary` with a malformed `month` threw a `RangeError`, which became a 500. It now throws `422 VALIDATION_ERROR`.
      - `listActiveGoals({ limit: 0 | -n })` meant "no limit" in Mongo. The limit is now clamped to 1 … 100.
- [x] **Family time-zone change** (for the family module, which is still a stub): business dates are family-local
      midnights, so a timezone change moved every entry to the wrong day and month. New `rebaseBusinessDates({ familyId,
      fromTimeZone, toTimeZone })` in `ledger.service.js` moves ledger `date` and goal `targetDate` to the same day in the
      new zone. It uses conditional batched `bulkWrite`s and is safe to re-run. Wiring it up is a handoff.

### Verified, no change needed (regression tests added)
- Operator injection:
  - `?memberId[$ne]=…`, `?type[$ne]=…` and `?goalId[$exists]=…` are plain unknown keys for Express 5's simple parser. They are ignored, and visibility still applies.
  - Repeated keys are arrays, which return 422.
  - `{ "$ne": null }` in any body field returns 422.
  - `__proto__` is an unknown key.
- Mass assignment: `savedAmount`, `savedMinor`, `status` on POST, `achievedAt`, `familyId`, `createdById`, `goalId`, `amountMinor` and `memberName` are stripped on every route. A contribution is always the caller's own `expense/savings` entry for that goal.
- Numbers:
  - `1e400` (Infinity), `-0`, `1e13`, `"1e3"`, arrays and objects all return 422.
  - `999999999999.995` rounds to exactly the 1e12 cap.
  - Goal overflow returns `422 goalFull`, and the saved amount is left unchanged.
- Pagination far past the end, and months such as `0000-01` or `9999-12`, return empty results instead of errors.
- Races: contributions racing an archive (clean 409s), deletes racing contributions and a target change, a goal deleted
  mid-contribution (no orphan entry), and a failed entry write (the saved amount is restored and no push is sent). In every
  case `savedMinor` equals the sum of the linked entries, and type/category pairs stay valid under concurrent PATCHes.
- Deleted members: their entries stay editable by admins, and entries cannot be moved to a deleted member (422).
- Push recipients: only current family members with an account. Each message is localized to its device locale, falling back to the account locale.

### Pending / known issues after the review
- [ ] `PATCH /family` must call `rebaseBusinessDates` when `timezone` changes (family owner; task due dates have the same problem, tasks owner).
- [ ] `ledger.errors.targetDateRange` needs translating into the 14 other locales.
- [ ] POST `/ledger/entries` and `/goals/:id/contributions` have no idempotency key, so a client retry after a timeout records the money twice (contract / product decision).
- [ ] The shared text helpers live in `tasks.schemas.js` and are imported by notices and ledger. They should move to `src/lib/` (b-core).
- Monthly `$sum` is exact up to 2^53 minor units (about 9e13 major units in one month and family). That is far beyond real use and accepted.
- The cooldown is per goal, not per member. A goal really re-reached within 24 h (e.g. a mistaken contribution corrected) does not notify twice, by design.
