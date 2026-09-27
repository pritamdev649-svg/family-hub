# b-tasks: backend tasks module (progress)

Owner: b-tasks. Scope: `family_hub_backend/src/modules/tasks/**`, `src/i18n/locales/en/tasks.json`, `tests/tasks.test.js`.
Contract: docs/03-API_CONTRACT.md §7 (tasks TASK-01 … TASK-06).

## Built
- [x] `tasks.routes.js`: all 7 endpoints under `/tasks`, each behind `familyMember` (`requireAuth` + `requireFamily`).
      Order: 401, then 403 NO_FAMILY, then 400 (malformed id), then 422 (query or body), then the service.
- [x] `tasks.controller.js`: HTTP only. It uses `ok`, `created` and `paged`.
- [x] `tasks.schemas.js`: zod built from the shared blocks.
  - title: 1–120 chars, trimmed.
  - description: up to 1000 chars. `null` or blank means null.
  - assigneeId: an ObjectId.
  - dueDate: an ISO instant, or a date-only `YYYY-MM-DD`. It must fall in 2000–2100.
  - category and priority: enums. POST defaults them to `other` and `medium`.
  - PATCH makes every field optional. `null` is allowed only for description and dueDate.
  - Unknown keys (`status`, `completedAt`, `familyId` …) are stripped.
  - Query: blank values count as "not given". `status` defaults to `all`.
- [x] `tasks.query.js`: shared list logic.
  - The `$match` builder casts ids to ObjectId.
  - `dueFilter`: overdue, today and week, in the family time zone, using `lib/dates.js`.
  - `TASK_SORT_STAGES`: the contract sort, computed per status group.
    - pending: `dueDate` ascending with nulls last, then `createdAt`.
    - done: `completedAt` descending.
    - all: pending first.
    - `_id` breaks ties, so pages never overlap.
- [x] `tasks.serializer.js`: `serializeTask` and `serializeTasks`. They give the exact contract shape and fill names
      through `memberDirectory`.
- [x] TASK-01 `GET /tasks`:
  - Filters: `assigneeId` (another family's id matches nothing), `status`, and `due`.
  - `due=overdue` matches pending tasks due before today's local midnight. `overdue` + `status=done` returns an
    empty page without a DB call. `today` and `week` (Monday-based) match any status.
  - Pagination runs through `paginateAggregate`: one `$facet` round trip and one member query.
- [x] TASK-02 `POST /tasks`:
  - An admin may assign anyone in the family; a member may assign only themselves.
  - An assignee outside the family gives `422 VALIDATION_ERROR`, `details.assigneeId`.
  - A member assigning someone else gets `403 FORBIDDEN` with a localized message.
  - `task_assigned` goes to the assignee when the assignee is not the creator.
- [x] TASK-03 `GET /tasks/:id`, `PATCH /tasks/:id` and `DELETE /tasks/:id`:
  - Another family's task gives 404.
  - PATCH and DELETE need an admin or the creator.
  - PATCH is an atomic `$set` of only the given fields.
  - A member-creator may re-assign only to themselves. The assignee rules run only when the assignee really changes.
  - An empty PATCH returns the task unchanged.
  - DELETE returns `data: null`.
- [x] TASK-04 `POST /tasks/:id/complete` and `/reopen`:
  - They need the assignee or an admin.
  - Idempotent: a repeat returns the task unchanged.
  - Race-safe: a conditional `findOneAndUpdate` on `status`. 6 parallel completes give one transition and one push.
  - `task_completed` goes to the creator when the creator is not the completer, and only on the real transition.
- [x] Pushes:
  - Fire-and-forget `void sendToMembers(...)`, route `/tasks/<id>`.
  - No push for the actor, for managed profiles without an account, or for removed members.
  - Push texts carry the actor's name and the task title, shortened to 60 code points.
  - For `health` tasks the title is left out (`bodyPrivate`), per docs/08-COMPLIANCE.md §3 row 20.
- [x] TASK-05 `src/i18n/locales/en/tasks.json`:
  - `push.assigned|completed.title|body|bodyPrivate`.
  - `errors.assigneeNotInFamily|assigneeRemoved|assignSelfOnly|editNotAllowed|completeNotAllowed`.
- [x] TASK-06 `tests/tasks.test.js`: 49 tests. They cover:
  - 401, NO_FAMILY, 400 and 404 on every route.
  - The envelope and the Task shape.
  - Create: defaults, trimming, limits, the validation matrix, stripped keys, date-only resolution in the family
    time zone, pushes (recipients, route, keys, vars, delivered text, private health text, long titles).
  - Get and names: renames; a removed member's name is null.
  - List: empty list, sort orders for all, pending and done, pagination and hasMore, the assignee filter, query
    validation, and the due filters in 3 time zones (+5:30, −7/−8, +14) with boundary tasks.
  - The PATCH permission matrix, null rules, re-assign push, member self-only rule, and re-sending a removed assignee.
  - Complete and reopen: idempotency, the race test, push rules, 403 and 422 edge cases.
  - Delete matrix.
  - i18n keys and the helper units.

## Verified
- `cd family_hub_backend && node scripts/check-syntax.js`: 86 JS files and 4 JSON files, all OK.
- `node --test tests/tasks.test.js`: 49/49 pass (about 10 s).
- `npm test` (whole suite, `--test-concurrency=1`): 344/344 pass.
- Mutation check: I made the service ignore the family time zone (UTC) and all 5 time-zone tests failed. The
  service was then restored.

## Pending / not in scope
- [ ] Translations of `tasks.json` for the other 14 locales. The translation agents own them and need the same keys.
- [ ] The contract (§7) does not yet document the decisions below. This is a handoff to the docs owner.
- [ ] The dashboard (DASH-01) should reuse `serializeTask` and `tasks.query.js`. This is a handoff.

## Decisions / known issues
- **`status` defaults to `all`**, like the Flutter mock. `category` and `priority` are optional on POST (defaults
  `other` and `medium`) because the model and the mock accept that. The app always sends them.
- **Check order**:
  - Create: 422 for an assignee outside the family, then 403 for a member assigning someone else. The mock uses
    the same order.
  - PATCH: 404, then 403 (not admin or creator), then 422 (assignee), then 403 (member self-only).
- **PATCH re-assignment also sends `task_assigned`** to the new assignee, unless that person is the actor. The
  contract only mentions POST, but a person who is newly assigned must be told.
- **Reopening a done task whose assignee was removed** gives `422 VALIDATION_ERROR`, `details.assigneeId`
  (`tasks.errors.assigneeRemoved`). Removing a member deletes their pending tasks, so an orphan pending task would
  break that rule. The admin re-assigns first. Completing a task, or re-sending the current assignee in a PATCH,
  still works for such tasks.
- **A date-only `dueDate` (`YYYY-MM-DD`) means midnight in the family time zone.** UTC midnight would fall on the
  previous day west of UTC. The app sends full ISO instants, which are stored unchanged.
- **dueDate must fall in 2000-01-01 … 2100-12-31.** This catches typos such as the year 0202. Past due dates are
  allowed (back-filling).
- **Names of removed members are `null`**, from `memberDirectory.nameOf`. The app already maps null to `''`.
  Names are resolved at read time, so renames show up immediately.
- **Health tasks never put their title in a push.** Other titles are cut to 60 code points with "…".
- **`week` means the Monday-based calendar week that contains today**, in the family zone, for any status. So it
  includes tasks due earlier this week.
- **Due filters use the family time zone.** A member whose device is in another zone may see "today" shifted. The
  Flutter mock uses the device zone, as documented in its header.
- **Validation `details` messages are English**, the shared convention. The top-level `message` is localized.

## Hardening review (b-tasks-harden, 2026-09-27)

An adversarial review of the module. Every issue found has a regression test in `tests/tasks.test.js`
(`tasks hardening: …` suites, 22 new tests, 71 in total). Each fix was mutation-checked: reverting it
makes its tests fail.

### Found and fixed
- [x] **Race in complete / reopen that bypassed permissions.** The assignee check ran on a snapshot, but
      the conditional update only matched `status`. Scenario: the old assignee calls complete while an
      admin moves the task to someone else. The old assignee could then complete (or reopen) a task that
      no longer belonged to them. Fix: the update now also requires the snapshot's `assigneeId`. After a
      lost race the task is re-read and all checks run again: the old assignee gets 403, and an admin
      retries and succeeds. After 3 lost races in a row the call gives `409 CONFLICT`, with the task
      unchanged; this cannot happen in practice.
- [x] **Emoji-heavy titles leaked a raw Mongoose message that echoed the input.** zod 4.6 `.max()`
      counts code points, while the Task model's `maxlength` (and the app's `String.length` validator)
      count UTF-16 units. So 61 emoji passed zod and failed in Mongoose with
      ``details.title = "Path `title` (`🧹🧹…`, length 122) is longer than …"``. Fix: title and
      description limits are now counted in UTF-16 units in the schema, and a normal 422 message is
      returned.
- [x] **Invisible titles were accepted.** A title made only of zero-width or format characters
      (`​`, ZWJ, word joiner, soft hyphen, a lone combining mark) passed `trim()` and `min(1)`.
      Titles now need at least one letter, digit, symbol/emoji or punctuation mark; otherwise
      "Title is required".
- [x] **Control characters were stored as sent.** NUL, DEL, C1, CR/LF and TAB in titles reached lists and
      lock-screen pushes. Titles are now single-line: every run of control characters becomes one space.
      Descriptions keep `\n` and `\t`; CRLF/CR become LF and other control characters are removed. RTL
      text and bidi marks (RLM/LRM) are kept exactly as typed (there is a test for this).
- [x] **Lone surrogates.** `"Milk \uD83E"` was returned as sent but stored by MongoDB as U+FFFD. Text is
      now made well-formed first, so the response always equals what was saved.
- [x] **Push titles split grapheme clusters.** `pushTitle` cut by code points, which splits Indic
      conjuncts (क्ष, ত্র: a dotted circle on the lock screen), ZWJ emoji (👨‍👩‍👧) and flags (🇮🇳). It now
      cuts by grapheme clusters (`Intl.Segmenter`) and trims the space before "…".
- [x] **A pending task could be left for a removed member (race with member removal).** Create,
      re-assign (PATCH) and reopen check the assignee against the member map, then write. If the member
      was removed in between, a pending task for a non-member survived. Now, after any write that leaves
      a task pending, the service checks again that the assignee still exists (`Member.exists`). If they
      are gone it undoes the write and answers 422 `details.assigneeId`:
      - create: the task is deleted and no push is sent;
      - PATCH: every field of that PATCH, and `updatedAt`, go back to their old values;
      - reopen: it goes back to done with the original `completedAt`, `completedById` and `updatedAt`.
      This fully closes the race only once member removal deletes the member row before purging pending
      tasks (handoff to the memberCascade owner).
- [x] **`task_assigned` was sent when re-assigning a done task.** The new assignee got "New task from …"
      for something already finished. Re-assigning now pushes only when the task is pending.
- [x] **Due-date lower bound rejected valid local midnights.** The app sends local midnight as UTC. For
      2000-01-01 in UTC+5:30 … +14 that is on 1999-12-31 in UTC, which was rejected while the same day
      in UTC-west zones was accepted. Instants are now accepted from 1999-12-31T10:00Z (midnight at
      UTC+14). A date-only `1999-12-31` is still rejected.

### Probed and found safe (tests added where useful)
- **NoSQL operator injection in the body**: `{"$ne":null}` in title, assigneeId, dueDate, description,
  category or priority gives 422. Top-level `$set` / `$where` keys are stripped. In the query,
  Express 5's simple parser ignores `status[$ne]` and `assigneeId[$gt]`, and `familyId=` is stripped.
- **Mass assignment on POST and PATCH**: `familyId`, `createdById`, `status`, `completedAt`,
  `completedById`, `_id`, `id`, `createdAt` and a literal `__proto__` key are stripped. The task never
  moves to another family.
- **Pagination bounds**: `page=2^53-1` gives an empty page (no 500). Non-safe integers, fractions,
  negatives, NaN and Infinity, and `limit>100`, give 422.
- **Authorization**: a demoted admin loses powers on the next request; a removed member with a valid
  token gets 403 NO_FAMILY on every route; another family's admin cannot use this family's member ids
  (422 / an empty list); the existing 404 matrix already covers other families' task ids.
- **Pushes**: only the recipient's devices get them, each in its own device locale, then the user's
  locale, never the actor's `Accept-Language`. Placeholder injection (`{name}` in a title) is impossible
  because `i18n.interpolate` does a single pass with a callback.
- **Errors**: no submitted value, "Path `", "Cast to" or other mongoose text appears in any 422, and
  404s carry no details.
- **Payload size**: over 100 kb gives 413 PAYLOAD_TOO_LARGE, from the app-level parser.

### Known issues / not changed
- Within a family, list and get show every task, health tasks included, to every member. This is the
  contract (§7 "member"). The compliance rule (§3 row 20) covers push texts only, and those stay
  private.
- There is no cap on tasks per family. The global rate limiter bounds abuse, and list sorting is
  in-memory per family, which is fine for family-sized data.
- A PATCH undo is skipped if a third write changed the task in the same few milliseconds. The client
  still gets 422 while the change stays. Accepted: it needs two simultaneous races.
