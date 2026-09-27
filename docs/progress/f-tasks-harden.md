# f-tasks-harden: review and hardening of the Flutter tasks feature

Scope (same as f-tasks): `family_hub_app/lib/features/tasks/**`, `family_hub_app/l10n_parts/tasks.arb`,
`family_hub_app/test/features/tasks/**`. Contract: docs/03-API_CONTRACT.md §7. Backend reference:
`family_hub_backend/src/modules/tasks` (including the b-tasks-harden changes).

## Review
- [x] Contract conformance: repository paths, methods, JSON names, enum wire names, pagination meta and
      error codes all match §7. No changes were needed in `task_repository.dart`.
- [x] Guide conformance: design tokens only (no hard-coded sizes, colours or fonts), RTL-safe insets,
      no user-visible literals, AsyncValueView everywhere, `markChanged` after every mutation,
      `mounted` checks after awaits. Nothing was found to fix.
- [x] Mock vs backend: 9 differences found and fixed (see "Mock backend" below).

## Built / fixed
### Failure handling (application + domain)
- [x] `domain/task_failure.dart`: `TaskFailure.of(error)` sorts errors into `gone` (404, or 400 for a
      malformed id), `notAllowed` (403), `noFamily`, `assigneeUnavailable` (422 with
      `details.assigneeId`) and `other`.
- [x] `TaskController` repairs stale state after a failure:
  - [x] **gone**: the task is hidden everywhere and every list refetches. Deleting a task that is
        already gone counts as a success.
  - [x] **403 / NO_FAMILY**: the change is rolled back, tasks refetch, and the session is re-read
        (`taskSessionRefreshProvider`, which tests can override), so a demoted admin sees the right
        controls and a removed member goes to family setup.
  - [x] **422 assignee**: members and tasks refetch.
- [x] `application/task_clock.dart`: `taskTodayProvider` (with an injectable `taskClockProvider`) rolls
      over at local midnight. Lists with a due filter refetch and the sections regroup.

### Screens
- [x] `presentation/task_errors.dart`: `context.showTaskError(e, TaskAction.x)` shows a localized
      message specific to the action for 404, 403 and 422 assignee errors. Other errors get the
      app-wide message.
- [x] `widgets/task_gone_view.dart`: "This task is no longer available" with a **Back to tasks**
      button. Shown on the detail and edit screens for 404/400, including when a refresh of an open
      screen finds the task deleted.
- [x] Removed members show as **"Former member"** (`taskPersonName`), since the API sends `null` names.
      The detail explains up front why a done task whose assignee left can't be reopened, instead of
      failing with a 422. Editing such a task keeps the former assignee without forcing a new one.
- [x] A stale member list (a member added on another phone) is not mistaken for a removal: the
      assignee's name is checked too, and the edit form refetches members.
- [x] Rapid taps:
  - [x] `openTaskRoute` never opens the same screen twice. It checks `GoRouter.state`, which is
        updated synchronously on push; `currentConfiguration.uri` stays at the shell location.
  - [x] Delete is guarded against a second dialog or a change already in flight.
- [x] The Tasks tab refetches task data when the app comes back to the foreground (at most once a
      minute) and re-checks the day then too, since iOS timers pause while the phone sleeps.
- [x] The new-task form refuses a signed-in user without a member profile. Before, pressing Create
      silently did nothing.
- [x] A title made only of zero-width characters now fails client validation, matching the backend.

### Mock backend (`data/tasks_mock_handlers.dart`)
- [x] Check order now matches the backend:
      PATCH 400 id → 422 body → 404 → 403 → assignee checks (422, then 403);
      POST 422 body → 422 assignee not in family → 403.
- [x] Re-sending the current assignee in a PATCH does nothing (no 403 or 422, even if they left).
- [x] Reopening a done task whose assignee left gives 422 `details.assigneeId`.
- [x] `assigneeName` / `createdByName` are the current names, or `null` for members who left (like
      the backend serializer).
- [x] A malformed `assigneeId` in a list query gives 422. The match ignores case.
- [x] dueDate accepts:
  - [x] ISO date-times with an offset, or a date-only `YYYY-MM-DD` (stored as local midnight);
  - [x] a calendar-checked date in the 2000–2100 window, with instants from 1999-12-31T10:00Z so local
        midnight of 2000-01-01 counts in UTC+14.
- [x] Text rules:
  - [x] Control characters in a title become one space.
  - [x] Descriptions keep LF and TAB.
  - [x] A title needs at least one visible character.
  - [x] Lengths are counted in UTF-16 units.

### l10n
- [x] 14 new `tasks*` strings (120 in total): former member, gone state, back to tasks, 6 action
      errors, reopen blocked, keep former assignee, create not allowed.

### Tests: 119 in `test/features/tasks`, all passing (75 before)
- [x] `task_edge_cases_test.dart` (new, 20):
  - [x] deleted tasks: push link, 400 link, deletion found on refresh, complete, edit or delete of a
        task deleted elsewhere;
  - [x] 403 on complete and on edit, and the form without a member;
  - [x] 422 when the assignee was removed;
  - [x] former members and stale member lists;
  - [x] double taps on the FAB, a tile and Create;
  - [x] refetch on resume, with throttling;
  - [x] long text in RTL at 1.6× on a 320 px screen;
  - [x] error-message mapping.
- [x] `task_controller_test.dart` (+10): failure recovery (404, 403, 422, delete of a task that is
      already gone), a second toggle while one is in flight, the failure classifier, midnight rollover.
- [x] `tasks_mock_handlers_test.dart` (+8): check order, the no-op assignee, a removed assignee,
      renames, dueDate formats and window, text rules, the `assigneeId` query.
- [x] `family_task_test.dart` (+5): viewer-independent due days, month, year, leap-year and DST day
      maths, local-midnight drafts, the former-member name.
- [x] `task_form_and_detail_test.dart` (+1, 2 updated): unknown task → gone view, offline load →
      retry, invisible titles.

## Edge cases checked (26)
1. Offline or timeout on the first load: an error with Retry.
2. Offline on refresh: the old data stays, with a notice.
3. Offline toggle: rolled back with an error, and nothing refetches.
4. Offline create or edit: the form keeps its input.
5. 401 in the middle of an action: the interceptor refreshes and retries once. If that fails, the
   session expires and every `await` checks `mounted`.
6. 403 because the role changed while the screen was open: a message for that action, the session is
   re-read, the controls update.
7. NO_FAMILY: the session is re-read, and the router sends the user to family setup.
8. A push opens a deleted task, or a task from another family: the gone view.
9. A malformed id in a link (400): the gone view.
10. The task is deleted while its detail is open, and a refresh finds out: the gone view.
11. Completing, reopening or editing a task deleted elsewhere: it is hidden everywhere and a message
    explains why.
12. Deleting a task that is already gone: counts as a success.
13. The assignee is removed while the form is open (422): a specific message, and members refetch.
14. Reopening a done task whose assignee left: explained up front, and a specific message if it
    happens anyway.
15. 409: the tasks API has none, apart from the backend's very rare CONFLICT. It gets the generic
    localized message.
16. Empty lists, per filter and after local deletions.
17. Very long titles and names.
18. The largest text size in RTL.
19. Month, year, leap-year and DST boundaries, and viewers in other time zones.
20. Midnight while the app stays open, and resuming after the phone slept.
21. Deleted members show as "Former member"; renamed members show their current name.
22. A stale member list.
23. Rapid taps: the FAB, tiles, Create, the toggle, and delete.
24. Data changed by another member: refetch on resume, pull to refresh, and the newer server
    `updatedAt` wins.
25. The end of the list, and a failed "load more".
26. Permissions change, or a user is signed in without a member profile, while a screen is open.

## Pending
- [ ] The 14 new `tasks*` keys still need translating into the 14 other languages (translation agents).
- [ ] Not tried on a device, simulator or browser. Checked only with widget tests and the full-app
      test in mock mode.

## Known issues
- Flutter's text-field counter counts grapheme clusters, while the validator and the backend count
  UTF-16 units. A long Hindi or emoji title can get "At most 120 characters" while the counter shows
  fewer. There is no server 422. This needs a core fix (handoff).
- "Today", "this week" and "overdue" use the phone's time zone. The server uses the family's. A member
  far from the family's time zone can see a date one day off. This is unchanged.
- The midnight and resume refreshes run while the Tasks tab is mounted. Dashboard tiles depend on the
  dashboard's own refresh.
- `showTaskError` passes its text through `ApiException(code: TASKS_LOCALIZED_ERROR, message, …)`,
  because `SnackX` has no way to show an already-localized error text (handoff).
