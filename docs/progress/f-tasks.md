# f-tasks: Flutter tasks feature (progress)

Owner files: `family_hub_app/lib/features/tasks/**`, `family_hub_app/l10n_parts/tasks.arb`,
`family_hub_app/test/features/tasks/**`. Contract: docs/03-API_CONTRACT.md §7.

## Built

### Domain (`lib/features/tasks/domain/`)
- [x] `family_task.dart`: `FamilyTask` plus the enums `TaskStatus` (unknown → pending), `TaskCategory` (unknown → other) and
      `TaskPriority` (unknown → medium), each with `wireName`/`fromWire`.
      - Parsing never throws.
      - `toJson`, `copyWith` (a `ValueGetter` clears a nullable field), `==` and `hashCode`.
      - Due-date helpers: `dueDay` is the calendar day, viewer-independent, via `calendarDate`. `isOverdue`/`isOverdueOn(now)` are true only for pending tasks. `isDueToday`/`isDueOn(date)`, `isDone`, `isPending`.
- [x] `task_query.dart`: `TaskQuery {assigneeId, status: TaskListStatus pending|done|all, due: TaskDueFilter overdue|today|week}`. It has value equality because it is the family argument, plus `toQueryParameters`.
- [x] `task_requests.dart`:
      - `TaskDraft` (POST body): trimmed, blanks omitted, the due date sent as local midnight in UTC.
      - `TaskPatch` (PATCH body, `PatchBody`): `TaskPatch.diff(before, …)` sends only the changed fields, and `null` clears the description or due date.
      - `TaskLimits` (title 120, description 1000).
- [x] `task_permissions.dart`: `TaskPermissions`, the UI mirror of §7:
      - create: admin for anyone, member only for self;
      - complete/reopen: assignee or admin;
      - edit/delete: admin or creator.
- [x] `task_templates.dart`: `TaskTemplate`, age-appropriate quick templates:
      - child: homework, tidy room, read 20 min;
      - teen: learn a skill, help cook, budget practice;
      - adult: pay bills, family check-in;
      - senior: medicine reminder, walk.
      Each template has a category and a priority. An unknown age gets the adult templates.
- [x] `task_grouping.dart`: `groupTasks` puts tasks into Overdue, Today, Upcoming and No due date, in that order, keeping the server order inside each section.

### Data (`lib/features/tasks/data/`)
- [x] `task_repository.dart`: `TaskRepository` (`list(TaskQuery, {page, limit})`, `get`, `create`, `update`, `complete`, `reopen`, `delete`) + `taskRepositoryProvider`.
      Malformed responses become `ApiException(UNKNOWN)`. An empty patch is not sent. Blank ids fail fast with `NOT_FOUND`.
- [x] `tasks_mock_handlers.dart`: `registerTaskMocks` covers every `/tasks` endpoint.
      - Filters: `assigneeId`; `status` (defaults to `all`); `due`, evaluated in device local time with a Monday-based week (overdue matches pending tasks only).
      - Sort order from the contract, and pagination.
      - Permissions: a member creates or reassigns only for themselves; completing needs the assignee or an admin; editing or deleting needs an admin or the creator.
      - Complete and reopen are idempotent.
      - Validation errors return `422` with field details. A malformed id returns `400`. Another family's task returns `404`.
      - Seed: 14 tasks of the Sharma family with stable ids (`MockTaskSeed`), some overdue, some due today, this week, later or undated, and 4 already done.
      - Public helpers for other mocks: `mockTaskJson(db, doc)` and `compareMockTasks`.

### Application (`lib/features/tasks/application/`)
- [x] `task_providers.dart`:
      - `taskListProvider(TaskQuery)`: an `AsyncNotifier`, autoDispose family, with `loadMore()` that de-duplicates and drops stale pages after a refresh. State is `TaskListState {page, isLoadingMore}`.
      - `taskByIdProvider(id)`.
      - `taskPermissionsProvider`.
      - All of them watch `sessionUserIdProvider` and `DataScope.tasks`, with `retry: apiRetryPolicy`.
- [x] `task_controller.dart`: `taskControllerProvider` (`TaskController`, state `TaskMutations {latest, deleted, busy}`).
      - Methods: `create`, `update`, `setDone`/`complete`/`reopen` (optimistic, rolled back and rethrown on error; a second toggle while one is in flight is ignored), and `delete`.
      - Every successful mutation calls `markChanged({DataScope.tasks})`.
      - The local state is applied on top of any server data through `resolve`/`apply`/`pick`; a newer server `updatedAt` wins. This is how the dashboard's `TaskTile`s pick up changes too.
- [x] `tasks_filter.dart`: `tasksFilterProvider` holds `TasksFilter {view: mine|family|done, due: TaskDueChoice, memberId}` and maps it to a `TaskQuery`. It resets when the account changes.

### Presentation
- [x] `presentation/tasks_labels.dart`: label extensions for category (plus a `const IconData` icon), priority (label, icon, colour), status, section, view, due choice and template. `TaskIcons` holds the const icons.
- [x] `presentation/widgets/task_tile.dart`: **`TaskTile(task, {showAssignee, onTap})`**, the public widget.
      - A checkbox when the member may toggle; otherwise a read-only status icon.
      - The title is struck through when done.
      - Assignee avatar and name, the due date (red with an "overdue" icon when late), category and priority indicator.
      - Toggling shows a busy state and an error snackbar. Tapping opens the detail.
- [x] `presentation/widgets/task_meta.dart`: `TaskDueLabel`, `TaskCategoryLabel`, `TaskPriorityIndicator`, `TaskAssigneeLabel`, `TaskStatusChip`, plus the helpers `dueDayLabel`, `dueDayRelative` and `daysFromToday`, which are DST-safe.
- [x] `presentation/screens/tasks_screen.dart`: **`TasksScreen`** (the tab).
      - SegmentedButton My tasks / Family / Done.
      - Due chips All / Overdue / Today / This week. They are hidden in Done.
      - Member chips (Everyone plus each member, with avatars) that scroll horizontally, in Family and Done.
      - Grouped sections and a count summary from the server total.
      - Load more, pull to refresh, AsyncValueView loading/error-with-retry states, and an empty state for each filter with a "New task" call to action.
      - The FAB opens `/tasks/new` with the filtered member pre-selected.
      - The filters are capped at half the height and scroll there, so short or large-text screens never overflow.
- [x] `presentation/screens/task_form_screen.dart`: **`TaskFormScreen`** (create and edit).
      - Fields: assignee dropdown (an admin can pick anyone; a member is locked, with a helper text), quick ideas by the assignee's age group (create only), title, description, due date, category chips with icons, priority chips.
      - Validation, and `?assigneeId=` pre-selection (ignored when the caller may not assign that member).
      - Busy button, then a success snackbar and close. Editing sends only the changes, compared with the task as it was when the form opened.
      - Asks before discarding unsaved changes. Opening edit without permission shows a refusal state.
- [x] `presentation/screens/task_detail_screen.dart`: **`TaskDetailScreen`**.
      - Shows the title, status, priority and category chips, and the description.
      - Shows the assignee, due date with a relative day, created-by with a relative and an exact time, completed-by, and last updated.
      - Complete/reopen for the assignee or an admin; otherwise an explanation.
      - Edit and delete for an admin or the creator. Delete asks first, then closes.
      - Pull to refresh, and a busy bar in the app bar.
- [x] `presentation/task_navigation.dart`: `closeTaskScreen` pops, or goes to `/tasks` after a deep link.
- [x] `tasks_routes.dart`: `taskRoutes` = `/tasks/new`, `/tasks/:id/edit`, `/tasks/:id` (also the push route `/tasks/:id`).

### l10n
- [x] `l10n_parts/tasks.arb`: 106 `tasks*` keys with descriptions and ICU plurals (`tasksPendingCount`, `tasksDoneCount`, `tasksDueInDays`).
      The dashboard member row can reuse `tasksPendingCount` (the example in docs/07).

### Tests (`test/features/tasks/`): 75 tests, all passing
- [x] `family_task_test.dart` (19): model parsing and defaults, due helpers, grouping, draft/patch, query/filter mapping, permissions, templates.
- [x] `task_controller_test.dart` (12): pagination and load-more retry, refetch on `markChanged`, filters, optimistic toggle with busy guard and rollback, create/update/delete, the `resolve` rules.
- [x] `tasks_mock_handlers_test.dart` (16): seed shape, sort orders, due filters, paging, validation, permissions, idempotency, family scoping.
- [x] `task_repository_test.dart` (4): repository → ApiClient → Dio → mock backend, end to end.
- [x] `tasks_screen_test.dart` (12): widget tests of the tab.
      - Covered: sections, views, member filter, empty states, retry, optimistic toggle and rollback, member permissions, FAB pre-selection, create-then-refresh.
      - Layout: RTL at text scale 1.6, and a 640×360 landscape screen at 1.6.
- [x] `task_form_and_detail_test.dart` (11):
      - Form: templates by age, validation, locked assignee, edit diff, discard dialog, permission refusal.
      - Detail: complete, member view, delete, not-found, large-text RTL.
- [x] `tasks_app_flow_test.dart` (1): the real app in mock mode. Demo login → Tasks tab → complete → Done → detail.

## Pending / handoffs
- [ ] Translations of the 106 `tasks*` keys into the other 14 languages (translation agents).
- [ ] Backend (tasks module owner): `PATCH /tasks/:id` must accept `dueDate: null` and `description: null`, which clear the fields (the app sends them).
      The app always sends `status` explicitly; the mock defaults a missing `status` to `all`.
      `due=overdue` should match pending tasks only, and `week` should be the Monday-based week containing today in the family time zone. The mock implements both.
- [ ] Docs owner: consider writing the three clarifications above into docs/03 §7.
- [ ] Family mock owner: removing a member should also delete that member's **pending** tasks from `MockDb.tasks` (contract §6). The tasks mock resolves names live and falls back to the stored `assigneeName`/`createdByName`.
- [ ] Dashboard mock owner: can reuse `mockTaskJson` and `compareMockTasks` from `features/tasks/data/tasks_mock_handlers.dart` for `myTasks` and the counts. Stored task docs keep `familyId` plus every contract field.

## Known issues / decisions
- In mock mode "today/this week/overdue" use device local time; the real server uses the family time zone (contract).
- The Done view is family-wide, with the member filter and no due chips, because an overdue filter makes no sense for done tasks.
- "My tasks" hides the assignee on tiles. A member filter pointing at someone who left falls back to Everyone.
- An optimistically completed task stays in its section, checked, until the refetch removes it from pending lists. It does not jump.
- Completing from the tile shows a short success snackbar. Rollback shows the localized error.
- Templates overwrite the title and fill the description only when it is empty.
- The due-date picker allows today up to 5 years ahead. When editing, an existing past due date stays selectable.

## Hardening review (f-tasks-harden, 2026-09-27)
The full checklist and the 26 edge cases checked are in `docs/progress/f-tasks-harden.md`. Test count:
75 → 119, all passing.

### Findings and fixes
- [x] **The detail showed "Something went wrong" with a useless Retry for a deleted task** (for example
      when opened from a push). A `TaskGoneView` with "Back to tasks" now replaces it, also when a
      refresh of an open detail or edit screen finds the task deleted.
- [x] **Mutations on a task deleted elsewhere left it visible.** A 404 now hides it everywhere,
      refetches the lists and says "deleted by someone else". Deleting a task that is already gone
      counts as a success.
- [x] **403 after a role change left stale controls.** The change is rolled back, and tasks and the
      session are re-read (`taskSessionRefreshProvider`).
- [x] **Generic "check the highlighted fields" for 422 on the detail screen.** Task-specific localized
      messages now cover 404, 403 and 422 assignee errors (`showTaskError`).
- [x] **Removed members showed as "Unknown", and reopening their done tasks failed with 422.** They now
      show as "Former member"; reopen is explained up front, and editing keeps the former assignee
      without forcing a new one. A stale member list is not mistaken for a removal.
- [x] **The mock kept stored names for removed members; the backend sends `null`.** The mock now matches
      the backend.
- [x] **Double taps on the FAB or a tile stacked two screens.** Fixed with `openTaskRoute`.
- [x] **"Overdue" and "Today" went stale after midnight, and task data went stale after coming back to
      the app.** Fixed with the `taskTodayProvider` midnight rollover and a refetch on resume, at most
      once a minute.
- [x] **New-task form without a member profile: Create silently did nothing.** The screen now shows a
      refusal state.
- [x] **Mock check order and rules differed from the backend.** Fixed:
  - PATCH order 400 → 422 → 404 → 403 → assignee;
  - an unchanged assignee is a no-op;
  - reopen with a removed assignee gives 422;
  - dueDate format and window, including date-only and midnight at UTC+14;
  - title and description control-character rules and visible-title rule;
  - a malformed `assigneeId` query gives 422.
- [x] **The client accepted titles made only of zero-width characters, which the server rejects.**
      Client validation now rejects them too.

### Resolved from the list above
- The earlier backend handoff (PATCH `dueDate: null` / `description: null`) is done in the backend
  (docs/progress/b-tasks.md).
