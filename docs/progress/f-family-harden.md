# f-family-harden: review + hardening of the Flutter "family" feature

Owner files (same as f-family): `family_hub_app/lib/features/family/**`, `family_hub_app/l10n_parts/family.arb`,
`family_hub_app/test/features/family/**`.

## Review results

### 1. Contract conformance (docs/03-API_CONTRACT.md §1, §2, §6)
- [x] Repository calls (shared `FamilyRepository`) use the contract's paths, methods, bodies and enum wire names. No
      pagination, because `GET /family/members` is not paginated.
- [x] Mock: error codes and statuses match the contract (401 → 403 `NO_FAMILY` → 403 `FORBIDDEN` → 404, 409
      `MEMBER_EMAIL_EXISTS` / `LAST_ADMIN` / `ALREADY_IN_FAMILY`, 422 `GUARDIAN_CONSENT_REQUIRED` / `VALIDATION_ERROR`,
      400 `INVALID_INVITE_CODE`).
- [x] **Fixed:** a malformed `:id` on `GET/PATCH/DELETE /family/members/:id` now answers `400 BAD_REQUEST` (contract
      §1 "invalid id format"). It used to answer 404. The check runs after the auth / family checks, as the other mocks
      do.
- [x] **Fixed:** date-of-birth bounds are checked by calendar day. Before, 1 Jan 1900 picked in India (sent as
      `1899-12-31T18:30Z`) was rejected as "out of range".

### 2. Guide conformance (docs/05-FLUTTER_GUIDE.md)
- [x] Tokens only. The grep found no hard-coded EdgeInsets numbers, `SizedBox` sizes, `fontSize`, `Color(0x…)`,
      `Colors.*`, left/right alignment or durations.
- [x] l10n: no user-visible literals. 6 new keys (106 in total).
- [x] RTL: directional insets. The only vertical-only `EdgeInsets` left are direction-neutral.
- [x] Every async screen uses `AsyncValueView`. `markChanged` runs after every mutation. `mounted` /
      `context.mounted` is checked after every await.
- [x] **Fixed:** `!` on server data in the detail rows (phone, email, `recordedAt`) and in the settings `data:`
      builder.
- [x] **DRY:** the age logic existed three times (`MemberFormData.ageOn`, `FamilyMockService.ageOf`, `Member.ageOn`
      in shared). The two copies in my files now use the core `ageFrom`.

### 3. Edge-case sweep (all handled and covered by tests)
1. [x] **Opening a removed or unknown member** (old notification, stale link): a dedicated `MemberGoneView` ("This person
       is no longer in the family") replaces "Something went wrong" and its useless Retry. It offers Back, or "View
       members" when opened directly.
2. [x] **Malformed id** (`400 BAD_REQUEST`): treated as gone, same view.
3. [x] **Member removed by another admin while the detail or edit screen is open:** a refresh that answers
       `NOT_FOUND` switches to the gone view instead of showing stale data under a "couldn't refresh" notice.
4. [x] **Removing a member who was already removed** (`NOT_FOUND` on `DELETE`, or a retry after a lost answer): treated
       as done (`MemberRemovalOutcome.alreadyRemoved`). An info snackbar shows, the screen closes, and the cascade
       scopes refresh.
5. [x] **Signed-in user removed from the family** (`NO_FAMILY` from any family call): the session is re-read
       (`refreshMe`), so the router switches to family setup.
6. [x] **Admin demoted on another phone while a screen is open:** a fresh `GET /family/members` that lists the user with
       a different role (or name, photo …) is merged into the session. The FAB, Edit, Remove and Assign actions update
       at once, and the add / edit form switches to "admins only". `FORBIDDEN` from any mutation also re-reads the
       session.
7. [x] **Member promoted to admin while family settings is open:** `familyProvider` now watches `isAdminProvider` and
       refetches, so the editable view shows the invite code (members get `inviteCode: null`).
8. [x] **Server answers `GUARDIAN_CONSENT_REQUIRED` although the app thought no consent was needed** (a different
       consent table on the server, a birthday or time-zone boundary). This used to be a dead end: the checkbox was
       hidden, so the error could not be fixed. Now the checkbox appears, the form scrolls to it, and the ticked value
       is sent (`consentRequired`).
9. [x] **`MEMBER_EMAIL_EXISTS` and `VALIDATION_ERROR` details** are shown under the field they concern, not only in a
       snackbar. They clear once the field changes, and every field then re-validates as the user types.
10. [x] **Offline or timeout on "Add member" after the server actually created it:** the member list is refetched
        (outcome unknown). Adding the same name again asks "Aarav is already in the family. Add anyway?", which stops
        duplicate managed profiles.
11. [x] **Offline, timeout or 5xx on edit, remove, save settings or new invite code:** the affected data is refetched,
        because the change may have gone through. The form keeps its values and the retry is idempotent.
12. [x] **`LAST_ADMIN` / `MEMBER_EMAIL_EXISTS` / `NOT_FOUND` on a mutation:** the member list is refetched, because
        what the screen showed was stale.
13. [x] **Rapid repeated taps:** a second tap during a push transition could open the same screen twice (FAB, member
        rows, Edit, Emergency card, Assign task, settings icon, members card) or open two dialogs (Remove, New code,
        duplicate-name dialog). All go through `pushIfTop` / `isTopRoute`. The test was checked against the unguarded
        code, where it fails. Double submits were already blocked by the controllers.
14. [x] **Inputs changed while a save runs:** the photo, date, gender and role pickers are locked (`IgnorePointer`), as
        the text fields already were.
15. [x] **Screens opened directly (deep link or notification) with nothing to pop:** after removing, saving or
        discarding, `popOrGo` goes to `/members` (or `/home`). Before, go_router threw "nothing to pop" after a removal
        and discard did nothing.
16. [x] **Very long names (60 characters) and long designations** at 1.4× text, RTL and 320 dp: no overflow on the list
        or the detail screen. The mock rejects 61 characters with field details.
17. [x] **Empty member list:** empty state with the Add action for admins.
18. [x] **Month and time-zone boundaries of birthdays:** leap-day birthdays (17 on 28 Feb, 18 on 1 Mar), born today
        (age 0), the consent birthday itself, and calendar-day date bounds in the mock.
19. [x] **Stale data after another member changes something:** pull-to-refresh on every screen, and the family and
        member session copies are merged (settings and list).
20. [x] **401 expiry mid-action:** handled by the core `AuthInterceptor` (single-flight refresh + retry). If the refresh
        fails, the session-expired flow runs; family screens only show the localized error while still mounted.
21. [x] **Pagination end:** not applicable. `GET /family/members` is not paginated, and the list uses
        `ListView.separated`.

### 4. Mock mirrors the backend rules
- [x] Re-checked against contract §6 and docs/04-DATA_MODELS.md: self-limited PATCH (other keys → 403), admin checks,
      consent by the family's country, email uniqueness (case-insensitive), `LAST_ADMIN` on demote and delete, the delete
      cascade, invite code for admins only, rotation. The backend family module is still a stub
      (`family_hub_backend/src/modules/family/family.routes.js`), so the contract is the reference.

### 5. Tests (`test/features/family/`, now 126 tests, previously 79)
- [x] `family_controllers_test.dart`:
  - Stale versus uncertain refresh scopes, `FORBIDDEN` → session resync, `consentRequired`.
  - Removal outcomes (removed, already removed, busy) and offline removal.
  - Timeouts on the invite code and on save.
  - `familyProvider` refetch on a role change.
  - `FamilySessionSync` (role merge, location-only differences ignored, missing self → resync, family merge, shared
    resync).
- [x] `member_form_data_test.dart`: leap-day and birthday ages, `consentRequired`, duplicate-name matching, long and
      Indic initials.
- [x] `family_mock_handlers_test.dart`: 400 on malformed ids (after 401), calendar-day DOB bounds, 60 / 61 character
      names, deleting twice → 404.
- [x] `members_screen_test.dart`: empty state, double tap on the FAB and on a row, demotion hides admin actions,
      `NO_FAMILY` resync, long names at 320 dp / 1.4× / RTL.
- [x] `member_detail_screen_test.dart`:
  - Gone view (unknown id, and malformed id opened directly).
  - Member removed while the screen is open.
  - Already removed on delete.
  - Deep-link removal → member list.
  - Double tap on Remove.
  - Demotion while open.
- [x] `member_form_screen_test.dart`:
  - Duplicate-name dialog.
  - Consent required by the server.
  - Inline `MEMBER_EMAIL_EXISTS` and `VALIDATION_ERROR` errors.
  - Offline retry.
  - Demotion → "admins only".
  - Member removed while editing.
  - Deep-link save → member list.
- [x] `family_settings_screen_test.dart`: promotion shows the invite code, double tap on "New code", a fresher family
      reaches the session, `NO_FAMILY` resync, offline save then retry.

## New and changed files
- New: `application/family_session_sync.dart`, `presentation/family_navigation.dart`,
  `presentation/widgets/member_gone_view.dart`.
- Changed: `application/family_providers.dart`, `member_editor_controller.dart`, `member_removal_controller.dart`,
  `family_settings_controller.dart`, `domain/member_form_data.dart`, `data/family_mock_handlers.dart`, all four
  screens, `widgets/designation_field.dart`, `l10n_parts/family.arb`, and every file in `test/features/family/`.

## Pending
- [ ] Saving while a photo upload is still running saves without the new photo, and the upload is cancelled when the
      form closes. `ImagePickerField` (core) does not report its busy state, so the form cannot wait for it. Handoff to
      f-core.
- [ ] The session sync runs on list and family *changes* (`WidgetRef.listen` has no `fireImmediately`). A cached member
      list fetched while no family screen was open is merged on its next refresh, not when the screen opens.
- [ ] Carried over from f-family: localized country names, a share button for the invite code (no package), and a
      real-device check of the invite cells with Indic / Arabic fonts.

## Known issues / decisions
- `NOT_FOUND` on `DELETE /family/members/:id` counts as success ("already removed"). From the UI the id always comes
  from the caller's own family, so NOT_FOUND can only mean it is gone.
- The duplicate-name check compares case- and space-insensitively against the list on screen. It asks for confirmation
  and never blocks: families can have two people with the same name.
- Server field errors are shown for `name`, `email`, `phone` and `designation`. Other `details` keys only appear in the
  snackbar.
- The ledger, emergency-card, settings and family features each have their own "resync the session on a stale
  answer" helper. The family one also merges list data into the session. A shared helper would belong in
  `lib/shared` (handoff).
