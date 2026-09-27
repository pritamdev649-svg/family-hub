# b-dashboard-harden: adversarial review of the backend dashboard module

Owner: b-dashboard-harden. Scope: the same files as b-dashboard:
- `family_hub_backend/src/modules/dashboard/**`
- `family_hub_backend/tests/dashboard.test.js`

The full list of findings and fixes is in `docs/progress/b-dashboard.md`, section "Hardening review".

## Method
1. I read contract §1, §2 and §11, the backend guide, all of `modules/dashboard`, and every helper it relies on:
   - `lib/access.js`, `lib/dates.js`, `middleware/auth.js`, `middleware/error.js`
   - `services/serializers.js`, `services/memberDirectory.js`
   - `tasks.query.js`, `tasks.serializer.js`
   - `goals.service#listActiveGoals`, `ledger.service#getMonthSummary`, `notices.service#listLatestNotices`
   - `sos.service#activeAlertsForFamily` and `sos.serializer.js`
2. Scratch probe suites attacked the running API:
   - Tokens, methods and paths.
   - GET bodies (operators, mass assignment, malformed, oversized) and prototype-pollution query keys.
   - Contract key sets, Unicode, money and time-zone extremes.
   - Orphaned SOS alerts, future-dated completions, and concurrency.
   - `explain` and profiler runs on families with years of history.
3. For every confirmed issue I wrote a fix and a regression test (the `hardening:` suites at the end of
   `tests/dashboard.test.js`). Behaviour that proved correct got regression tests too.

## Built / fixed
- [x] `completedThisWeek` is bounded to the current week `[Monday 00:00, next Monday 00:00)` in the family time zone.
      Before, a future-dated `completedAt` counted. A mutation run confirms the tests catch it.
- [x] The shared `clockOf()`: an invalid injected `now` falls back to server time in `getDashboard` and
      `memberTaskStats`, instead of a `RangeError` giving a 500.
- [x] 17 new tests (47 in total; 45 pass and 2 are index-dependent `todo`), green on 3 consecutive runs:
  - Tokens: expired, forged, `alg: none`, foreign audience, operator-shaped `sub`, deleted user.
  - HEAD, trailing slash, and sub-paths giving 404.
  - A GET body is ignored (operators and mass assignment). Malformed and oversized bodies get clean 4xx errors.
  - Prototype-pollution query keys.
  - A forged service actor, and an invalid clock or zone.
  - Exact contract key sets and value types of every nested object.
  - Unicode, emoji and RTL round trips.
  - Money edge cases: 0.1 + 0.2, the 1e12 maximum, a negative net.
  - The America/New_York DST week, and the +14 h, −11 h and +5:45 zones.
  - Completions after the current week.
  - An orphaned SOS fails closed.
  - 10 concurrent requests: identical payloads, the lazy expiry persisted once, no push or e-mail.
  - No COLLSCAN in a dashboard request.
  - Two profiler checks for whole-history scans (`todo` until the indexes below exist; verified to pass with them).

## Pending (other owners)
- [ ] Models owner, `src/models/Task.js`: add the index `{ familyId: 1, status: 1, completedAt: -1 }`.
      - Today the counters aggregation examines every done task the family ever had: 5,020 docs for about 3 years of
        history, against 2 with the index.
      - The index also serves `GET /tasks?status=done`.
- [ ] Models owner, `src/models/Notice.js`: change the board index to `{ familyId: 1, pinned: -1, createdAt: -1, _id: -1 }`.
      - `NOTICE_SORT`'s `_id` tie-breaker forces a blocking sort over every notice (3,000 examined to return 3). With
        the index it examines 3 and has no SORT stage.
      - `GET /notices` benefits too.
- [ ] Docs or core owner: contract §1 does not list the `413 PAYLOAD_TOO_LARGE` (and 415) responses that
      `middleware/error.js` sends for oversized or unsupported bodies on every endpoint. Either document them or map
      them to `400 BAD_REQUEST`.
- [ ] Still open from b-dashboard:
  - Contract §11 wording (counter definitions, goal order, no query parameters, `Cache-Control`).
  - Ticking DASH-01 and DASH-02 in docs/TASKS.md.
  - Flutter mock parity (DASH-06). The mock should also bound `completedThisWeek` to the current week.

## Known issues / accepted
- There is no snapshot isolation across the six parallel reads: a task completed mid-request can appear in `myTasks`
  while being counted as done. This is accepted; MongoDB snapshot reads need replica-set transactions.
- Conditional GET can answer 304 thanks to Express's weak ETag, even with `no-store`. Nothing leaks, and Dio sends no
  validators.
- Only English i18n files exist so far, so localized error messages for `NO_FAMILY` / `UNAUTHORIZED` fall back to
  English (translation owners).
