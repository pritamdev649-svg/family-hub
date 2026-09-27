# b-dashboard: backend dashboard module (progress)

Owner: b-dashboard. Scope: `family_hub_backend/src/modules/dashboard/**`, `tests/dashboard.test.js`.
Contract: docs/03-API_CONTRACT.md §11 (tasks DASH-01, DASH-02).

## Built
- [x] `dashboard.routes.js`: `GET /dashboard` behind `familyMember` (requireAuth + requireFamily). The placeholder
      router is replaced and the file still does `export default router`. The mount in `src/routes/index.js` was
      already correct and is unchanged.
- [x] `dashboard.schemas.js`: `dashboardQuery = z.object({})`. The endpoint takes no input. Unknown query keys are
      stripped like everywhere else, so `?_=<cache-buster>` works and `?familyId=` / `?month=` cannot change the scope.
- [x] `dashboard.controller.js`: HTTP only. It sets `Cache-Control: private, no-store` (the payload holds SOS
      locations, contact data and money) and responds with `ok`.
- [x] `dashboard.service.js`, `getDashboard(actor, { now })`:
  - Stage 1 runs in parallel: the family (lean) and `getMemberMap`.
  - Stage 2 runs 6 independent reads with `Promise.all`:
    - per-member counters in **one** aggregation (`memberTaskStats`, exported)
    - `myTasks`: `taskListMatch` + `taskListPipeline` from tasks.query.js, plus `$limit 5`
    - `listActiveGoals(familyId, { limit: 3 })`
    - `listLatestNotices(familyId, { limit: 3, members })`
    - `activeAlertsForFamily(familyId, { members, now })`, which runs the lazy expiry first
    - `getMonthSummary(...)` for the current month in the family time zone. Admins get the family scope and
      members get the personal scope.
  - Serializers reused: `serializeFamily` (memberCount from the map, inviteCode for admins only), `serializeMember`
    and `sortMembers` (contract order), `serializeTasks`. Goals, notices and SOS come back already serialized from
    their module services.
  - Query budget: 9 DB operations after requireAuth, whatever the family size or amount of data (a test enforces it).
- [x] Counter rules (family time zone, same definitions as `GET /tasks?due=`; a test cross-checks them):
  - `pendingTasks`: `status = pending`.
  - `overdueTasks`: pending with a real due date before local midnight today. A task due today is not overdue.
    Pending tasks with no due date are never overdue. The `$type: 'date'` guard is there because null is less
    than any date in aggregation expressions.
  - `completedThisWeek`: `done` with `completedAt` on or after Monday 00:00 local.
  - All three count per **assignee**. A task an admin completes on the assignee's behalf counts for the assignee.
    Members without tasks get zeros. Tasks of members who left are ignored.
- [x] Robustness:
  - 403 `NO_FAMILY` when the family or the caller's member row disappears between requireAuth and the read.
  - An invalid stored time zone falls back to UTC.
  - Assignees, creators or authors who left serialize with `null` names.
  - The admin-only view (invite code, family-wide money) follows the member row read in this request, not the
    role in the token. A demotion racing the request cannot leak them, and `me.role` always matches.
- [x] `tests/dashboard.test.js`: 30 tests in 9 suites.
  - Access: 401, 403 NO_FAMILY (removed, left, family gone), only GET, query keys ignored.
  - Exact shape and envelope. Every section `deepEqual`s its own endpoint (`/family`, `/family/members`, `/tasks`,
    `/goals`, `/notices`, `/sos/active`, `/ledger/summary`) for both admin and member.
  - Id and ISO formats.
  - Role matrix and summary scope, including the demotion race. Family isolation (no id of the other family in
    the payload).
  - Counters with every boundary.
  - Fixed-clock day, week and month boundaries for Asia/Kolkata (Monday 1 June 00:30 IST) and America/Los_Angeles
    (Sunday 31 May 23:30 PDT). An invalid time zone falls back to UTC.
  - List limits and orders.
  - SOS lazy expiry persisted, and SOS location privacy.
  - `lastLocation` only for members sharing `always`. No internal keys or secrets in the payload.
  - The query budget.

## Decisions
- No `?month=` or other parameters. The contract defines none, and "current month in family timezone" is binding.
  The app uses `/ledger/summary?month=` to browse months.
- Unknown query keys are ignored, not answered with 422 (the shared convention). So this endpoint has no 422 path.
  The test suite shows that bad input cannot fail the request or widen its scope.
- `goals` are active goals, newest first (from `listActiveGoals`). The contract gives no order.
- `members` follow the contract order of `GET /family/members` (admins first, then oldest to youngest).

## Pending
- [ ] Contract §11 could state the decisions above: counters per assignee, goal order, no query parameters,
      `Cache-Control`. This is for the docs owner. Nothing contradicts the current text.
- [ ] docs/TASKS.md DASH-01 / DASH-02 checkboxes (docs owner).
- [ ] The Flutter mock `dashboard_mock_handlers.dart` (DASH-06) should use the same counter rules and orders
      (f-dashboard owner).

## Known issues
- ~~`completedThisWeek` has no upper bound.~~ Superseded by the hardening review below: it is now bounded to the
  current week `[Monday 00:00, next Monday 00:00)`.

## Hardening review (b-dashboard-harden)

Adversarial review of everything above. Method: read contract §1/§2/§11, the backend guide and every helper the
service relies on, then attack the running API with scratch probe suites. Each confirmed issue got a fix and a
regression test. Behaviour that proved correct got regression tests too. The new tests are the `hardening:` suites
at the end of `tests/dashboard.test.js`.

### Findings and fixes
1. **`completedThisWeek` counted completions after the current week** (confirmed by a probe: a done task with
   `completedAt` 30 days ahead counted as 1). Causes: clock skew between API instances, imported or corrupted data,
   and the injectable `now` (fixed-clock callers and tests saw every later completion).
   **Fixed:** the `$match` is now `completedAt ∈ [weekStart, weekEnd)` via `weekRange(now, tz)`.
   Tests: a completion 1 ms before next Monday counts, next Monday 00:00 and 2031 do not. The New York DST week checks
   both ends, and a mutation run (bound removed) makes both tests fail.
2. **An invalid injected clock caused a `RangeError` (500)** in `getDashboard` / `memberTaskStats` for internal
   callers. **Fixed:** the shared `clockOf()` means anything but a valid `Date` is the server time. Tests: `new Date('garbage')`,
   `'yesterday'`, `0`, and an invalid zone combined with an invalid clock.
3. **Scaling: the counters aggregation reads the family's whole task history.** `profiler` / `explain` show that the
   done branch filters `completedAt` after an IXSCAN on `{familyId, status, dueDate}`, so it examines every done task
   the family ever had (5,020 docs for about 3 years of history, 302 in the test). With
   `{ familyId: 1, status: 1, completedAt: -1 }` it examines 2. **Handoff** (models owner, `src/models/Task.js`). The
   index also serves `GET /tasks?status=done`, which is sorted by `completedAt` desc.
4. **Scaling: `latestNotices` does a blocking sort over every notice of the family.** `NOTICE_SORT` ends with the
   `_id: -1` tie-breaker, which is not in the `{familyId, pinned, createdAt}` index. So 3,000 notices were examined to
   return 3. With `{ familyId: 1, pinned: -1, createdAt: -1, _id: -1 }` it examines 3 with no SORT stage, and
   `GET /notices` pages benefit too. **Handoff** (models owner, `src/models/Notice.js`).
   Findings 3 and 4 are covered by two profiler-based tests. They run as `todo` while the schema lacks the index (the
   run reports them as todo, not as failures) and become ordinary checks once the index is declared. I verified in a
   scratch run that both pass with the proposed indexes.

### Verified correct (regression tests added)
- Tokens: an expired token gives 401 `TOKEN_EXPIRED`. A forged secret, `alg: none`, a foreign audience, an
  operator-shaped `sub`, and a valid token of a deleted user all give 401 `UNAUTHORIZED`.
- Methods and paths: HEAD returns headers only (with `no-store`). `/dashboard/` works. `/dashboard/<anything>`
  (id, `..%2F`, `%00`) gives 404 `NOT_FOUND`.
- A GET body is ignored: operators (`{"$ne":null}`, `$where`) and mass-assignment keys (`familyId`, `memberId`, `role`,
  `savedMinor`) change neither the scope nor the role, and nothing is written. A malformed body gives 400 `BAD_REQUEST`,
  an oversized one gives 413 in the standard envelope, and neither gives a 500.
- Query keys `__proto__[role]`, `constructor[prototype][role]` and repeated or array keys: the payload is unchanged and
  `Object.prototype` is not polluted.
- Forged service actor: a member id of another family, the family id of another family, operator-shaped ids and
  `undefined` all give 403 `NO_FAMILY`. No data of any family leaks.
- Contract conformance: every nested object (Family, Member, Task, SavingsGoal, Notice, SosAlert, location, month
  summary, `byCategory` row) has exactly the contract keys and value types, for admin and member.
- Unicode: Arabic, Hebrew, Devanagari, Tamil, CJK, ZWJ emoji families, flags and skin tones round-trip unchanged (NFC)
  in the family name, member names, designation, task title and description, goal title, notice title and body, and
  SOS message.
- Money: 0.1 + 0.2 = 0.3, the contract maximum (1e12) is exact, and a negative net works.
- Time zones (fixed clock): the America/New_York DST week, plus Pacific/Kiritimati (+14), Pacific/Pago_Pago (−11)
  and Asia/Kathmandu (+5:45) month and overdue flips at local midnight (±1 ms).
- An orphaned active SOS (owner row gone) is listed exactly like `/sos/active`, but fails closed: no location, no
  names, `locationShared: false`.
- Concurrency: 10 parallel requests (admin and member) return identical payloads per caller. The stale alert is
  expired once (not resolved), and no push or e-mail is sent by reading the dashboard.
- There is no COLLSCAN in any query of a dashboard request (profiler).

### Reviewed, no change
- **Conditional GET:** Express adds a weak ETag, so `If-None-Match` can answer 304 despite `no-store`. The client
  must already hold the body to send the tag, so nothing leaks. Dio sends no validators, so the app never gets a 304.
- **No snapshot across the six parallel reads** (MongoDB snapshot reads need a replica-set transaction). A task
  completed mid-request can appear in `myTasks` and be counted as done in the same response. This is accepted because
  the next refresh is consistent.
- **Push and e-mail:** the endpoint sends none. The lazy SOS expiry is a silent status change, and a test covers it.

### Handoffs
- [ ] Models owner: add `taskSchema.index({ familyId: 1, status: 1, completedAt: -1 })` (`src/models/Task.js`).
- [ ] Models owner: add `_id: -1` to the Notice board index, as `{ familyId: 1, pinned: -1, createdAt: -1, _id: -1 }`
      (`src/models/Notice.js`). Drop the old index in production, since it becomes a prefix duplicate.
- [ ] Docs / core owner: contract §1 has no row for `413 PAYLOAD_TOO_LARGE` (or the 415 case), but
      `middleware/error.js` returns them for oversized or unsupported bodies on every endpoint. Either document them or
      map them to `400 BAD_REQUEST`.
