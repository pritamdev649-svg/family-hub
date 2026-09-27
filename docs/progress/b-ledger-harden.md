# b-ledger-harden: adversarial review of the backend ledger module

Owner: b-ledger-harden. Scope: the same files as b-ledger:
- `family_hub_backend/src/modules/ledger/**`
- `src/i18n/locales/en/ledger.json`
- `tests/ledger.test.js`

The full list of findings and fixes is in `docs/progress/b-ledger.md`, section "Hardening review".

## Method
1. I read contract §8 (plus §1 and §13), the backend guide, the data models, all of `modules/ledger`, and the shared helpers
   it relies on (`lib/validate.js`, `money.js`, `dates.js`, `access.js`, `pagination.js`, `services/push.js`, `middleware/auth.js`).
2. Two scratch probe suites attacked the running API:
   - Unicode, emoji, RTL, lone surrogates and control characters.
   - Operator injection in the query and the body, and mass assignment.
   - Numeric, date, month and pagination extremes.
   - Push spam, and deleted members.
   - Contributions racing an archive, a goal deletion, entry deletions and a target change; parallel type/category PATCHes.
3. For every confirmed issue I wrote a fix and a regression test (the `hardening:` suites in `tests/ledger.test.js`).
   Behaviour that proved correct got regression tests too.

## Built / fixed
- [x] Text limits are counted in UTF-16 units. Emoji-heavy notes, titles and descriptions no longer return a raw Mongoose 422 that echoes the text.
- [x] Notes and descriptions are normalised (`optionalMultiLineText`):
  - The response now equals what MongoDB stores: well-formed UTF-16, and CRLF becomes LF.
  - Control characters are removed.
  - Text made only of invisible characters becomes `null`.
- [x] Goal titles are single-line and must contain a visible character.
- [x] `goal_achieved` push throttle: re-reaching the same target within 24 h does not notify again, which stops the contribute/delete spam loop. A new target resets it.
- [x] The push is never lost when an entry deletion or a compensation wins the `achieved` transition.
- [x] Goal `targetDate` must be a family-local day within 2000-01-01 … 2100-12-31. New key: `ledger.errors.targetDateRange`.
- [x] PATCH unlinks an entry whose goal is gone, so it no longer stays amount-locked.
- [x] Dashboard helpers:
  - `getMonthSummary` with a bad `month` → 422 (was a 500).
  - `listActiveGoals` clamps `limit` (0 or a negative number meant "no limit").
- [x] New `rebaseBusinessDates({ familyId, fromTimeZone, toTimeZone })` keeps entry and goal dates on their calendar day when the family time zone changes.
- [x] 20 new tests (74 in total), green on 3 consecutive runs.

## Pending (other owners)
- [ ] Family owner: `PATCH /family` must call `rebaseBusinessDates` (from `src/modules/ledger/ledger.service.js`) after
      saving a new `timezone`, passing the previous zone. Task `dueDate`s need the same treatment (tasks owner).
- [ ] Translation agents: `ledger.errors.targetDateRange` in the 14 other locales.
- [ ] Docs owner:
  - Contract §8: the goal `targetDate` window; text rules (UTF-16 lengths; invisible-only notes / descriptions become null); `goal_achieved` is not re-sent within 24 h for the same target.
  - `docs/04-DATA_MODELS.md`: `Goal.achievedAt` now means "when the current target was last reached". It is kept on reopen and cleared when the target changes.
- [ ] b-core: move `toSingleLine` / `toMultiLine` / `hasVisibleText` (tasks.schemas.js) and `maxUnits` (ledger.schemas.js) to `src/lib/`.
- [ ] Contract / product: idempotency keys for POST `/ledger/entries` and `/goals/:id/contributions` (a retry after a timeout duplicates money).
- [ ] Flutter mock owner: mirror the `targetDate` window (422 `details.targetDate`).

## Known issues
- The push cooldown is per goal. A goal that genuinely drops below its target and is re-reached within 24 h does not notify twice (by design).
- `rebaseBusinessDates` reads each stored date as the nearest midnight in the old zone. Run it once per zone change.
  Running it again is a no-op unless the two zones are more than 12 h apart.
- `$sum` in the monthly summary is exact up to 2^53 minor units per family and month. That is far beyond real use.
