# f-family: Flutter "family" feature (members, member form, family settings)

Owner files: `family_hub_app/lib/features/family/**`, `family_hub_app/l10n_parts/family.arb`,
`family_hub_app/test/features/family/**`.

## Built

### Routes (`family_routes.dart`)
- [x] `familyRoutes`: `/members`, `/members/new` (listed before `/members/:id`), `/members/:id`, `/members/:id/edit`,
      `/family/settings`. All navigation goes through `AppRoutes`.

### Screens (`presentation/screens/`)
- [x] `MembersScreen`: the list in server order (admins first, then oldest to youngest). Each row is a `MemberTile` with
      `MemberAvatar`, name, designation and badges (You, role, "Child · 9 years", "No account" / "Invited"). It has pull to
      refresh, and loading, error (retry) and empty states through `AsyncValueView`. Admins get an "Add member" FAB, and
      there is a settings shortcut in the AppBar.
- [x] `MemberDetailScreen`:
  - Header with avatar, name, designation and badges.
  - Call and Email buttons through `UrlActions`, with a localized message when no app can open.
  - Info rows: age, date of birth, gender, role (with its description), phone, email, location-sharing mode, last known
    location (relative time plus an "Open map" button, only when the member shares `always`), account status, and
    guardian consent (minors only, shown in the warning colour when missing).
  - Location sharing: a member's own profile has a "Change" link to `AppRoutes.settingsLocation`.
  - Actions: Emergency card (`AppRoutes.emergencyCard`) for everyone. Assign a task (`AppRoutes.taskNew(assigneeId:)`)
    and Edit for admins and for yourself. Remove for admins, not on yourself: it asks for confirmation, shows a busy
    state, and handles `LAST_ADMIN` and other errors with a localized snackbar.
- [x] `MemberFormScreen` (add and edit):
  - Fields: circular `ImagePickerField(folder: avatars)`, name, email (optional, with invite / managed / linked hints),
    phone (hint with the country dial code), `DatePickerField` for date of birth, gender chips (incl. "Prefer not to
    say"), designation with age-appropriate localized suggestion chips, and role (admin, never for yourself).
  - Guardian consent: a mandatory checkbox, shown when age < `currentCountryProvider.consentAge`. It names
    `country.privacyLaw` and the consent age, and blocks the form until ticked.
  - Access via `MemberFormAccess`: a non-admin editing themselves only sees name, phone, photo, gender and date of birth.
    A non-admin trying to add or edit someone else gets an "admins only" state.
  - Behaviour: busy button with no double submit, localized errors, discard-changes confirmation on back, and pop on
    success.
- [x] `FamilySettingsScreen`:
  - Admin: edit name, country (the **auth** `CountryPickerField`, imported from
    `features/auth/presentation/widgets/country_picker.dart`), currency and time zone. Changing the country switches to
    the new country's currency, unless another currency was chosen on purpose, and normalises the time zone. The
    country field shows the emergency number and consent age. Save is enabled only when something changed. Unsaved
    changes trigger the discard dialog.
  - Invite code card (`InviteCodeCard` / `InviteCodeCells`): the code in large equal-width cells, always LTR and spelled
    out for screen readers, with Copy (`Clipboard`) and a "New code" button that asks for confirmation first.
  - Member count card linking to `/members`.
  - Non-admins: a read-only summary and "Ask a family admin for the invite code".
  - A fresher `GET /family` result updates the session copy through `applyMe`, after the frame and only with settled
    data.

### Application (`application/`)
- [x] `familyProvider`: `FutureProvider<Family?>` for `GET /family`. It watches `sessionUserIdProvider`, the family id
      and `DataScope.family`, and uses `apiRetryPolicy`.
- [x] `MemberEditorController` (`memberEditorControllerProvider`, auto-dispose):
  - `add(MemberFormData)` sends `POST /family/members`, then a follow-up `PATCH` with `avatarUrl`, because the
    contract's add body has no photo. The result is `AddMemberResult(avatarSaved)`, so a failed photo save never makes
    the user submit twice.
  - `update(before, data, access)` sends only the allowed, changed fields and returns `before` when nothing changed. It
    calls `applyMe(null, member)` when you edit yourself.
  - Both ignore a second call while busy.
- [x] `MemberRemovalController`: `remove(member)` calls `DELETE /family/members/:id`.
- [x] `FamilySettingsController`: `save(before, …)` sends `FamilyPatch.diff`; `regenerateInviteCode()`. State is the
      action in flight, and the session is updated with `applyMe(null, null, family)`.
- [x] Data-change bus:
  - Every member mutation calls `markChanged({members, family})`.
  - A name or photo change also bumps `tasks`, `notices` and `sos` (they show denormalized names and avatars).
  - Removal also bumps `tasks`, `emergencyCards` and `sos` (the server cascade).
  - A currency or time-zone change bumps `ledger` and `goals`; a time-zone change also bumps `tasks`.
  - Collaborators are read before `await`, so a change is still announced when the screen closes mid-request.

### Domain (`domain/`)
- [x] `MemberFormData`: form values → `NewMemberRequest` / `MemberPatch` (via `MemberPatch.diff`). An unchanged
      calendar day of birth is not re-sent. Consent is only recorded when needed. Also provides
      `needsGuardianConsent(country)`, `ageOn`, `ageGroup`.
- [x] `MemberFormAccess` (`adminAdd`, `adminEdit`, `adminEditSelf`, `selfEdit`, `denied`) with `resolve(...)`,
      `canEditRole` and `canEditEmail(target)`. An account holder's email is read-only.
- [x] `DesignationSuggestion.forAgeGroup` (Head of Family, Finance Head (CFO), Operations Head (COO), Chief Health
      Officer, Tech Head (CTO), Chief Study Officer, Skill Builder, Chief Fun Officer, Junior Explorer, Family Advisor,
      Chief Mentor). Also `MemberAccountStatus` (`active`, `invited`, `managed`) and `FamilyLimits` (name 60,
      designation 80, avatar URL 1024; shared by the forms and the mock).

### Mock backend (`data/family_mock_handlers.dart`)
- [x] `registerFamilyMocks`: `POST /family`, `POST /family/join`, `GET/PATCH /family`, `POST /family/invite-code`, and
      `GET/POST /family/members` plus `GET/PATCH/DELETE /family/members/:id`. Contract rules covered:
  - Admin checks (403) and family scoping (another family's id → 404).
  - zod-like `VALIDATION_ERROR` with field details.
  - Invite codes: 8 characters from the alphabet without 0/O/1/I, rotated, matched case-insensitively (spaces and dashes
    are ignored), and shown only to admins.
  - `ALREADY_IN_FAMILY` and `INVALID_INVITE_CODE`. Join links a pre-added member with the same email.
  - `GUARDIAN_CONSENT_REQUIRED` by the family country's consent age (calendar-day age). `guardianConsentAt` and
    `guardianConsentById` are stored.
  - `MEMBER_EMAIL_EXISTS` (case-insensitive).
  - Self-limited `PATCH`: any other key → 403. Renaming yourself also renames the account.
  - `locationSharing` is not patchable here.
  - `avatarUrl` must be a Cloudinary URL or a local path (mock-mode uploads).
  - `LAST_ADMIN` on demote and on delete.
  - Delete cascade: unlink the user (`familyId` / `memberId` null, refresh tokens revoked, devices removed), delete
    pending tasks and the emergency card, resolve active SOS alerts, keep ledger entries with `memberName`.
- [x] `FamilyMockService` (public) with `validateNewFamily(prefix:)`, `createFamilyFor`, `joinFamilyFor`,
      `newInviteCode`, `requireUniqueEmail`, `requireGuardianConsent`, `requireAnotherAdmin`, `removeMember`, `ageOf`.
      Other mocks can reuse it (e.g. register in create or join mode).

### l10n
- [x] `l10n_parts/family.arb`: 100 keys, all prefixed `family…`. Each has a description, and plurals use ICU. Merged with
      `dart run tool/l10n.dart`.

### Tests (`test/features/family/`, 79 tests)
- [x] `member_form_data_test.dart`: Member parsing (contract JSON, unknown enums), access rules, the consent rule per
      country and calendar day, request / patch building (self-limited, no role for yourself, locked account email,
      clearing fields), designation suggestions.
- [x] `family_mock_handlers_test.dart`: every contract rule above, including the full delete cascade.
- [x] `family_mock_integration_test.dart`: the real `FamilyRepository` → `ApiClient` → mock interceptor → family mocks
      after a demo login.
- [x] `family_controllers_test.dart`: add (photo `PATCH`, photo failure, errors, double submit), update (self → session,
      scopes, empty patch, `LAST_ADMIN`), removal scopes and errors, settings diff / scopes / invite code,
      `familyProvider` refetch.
- [x] Widget tests with the real `familyRoutes` in a `GoRouter`:
  - `members_screen_test.dart`: admin list and FAB, member view with navigation, error then retry, plus RTL + 1.4× text
    + 360 dp no-overflow checks on all five screens.
  - `member_form_screen_test.dart`: the consent flow, adult edit, self edit, access denied, add flow with a suggestion
    chip, discard dialog.
  - `member_detail_screen_test.dart`: actions per role, mail and tel launch, remove with `LAST_ADMIN`, navigation,
    not found.
  - `family_settings_screen_test.dart`: invite cells, copy, regenerate, save diff, country switch, read-only view.

## Pending
- [ ] Real-device check of the flag emoji and the invite-code cells with Indic / Arabic system fonts. The golden renders
      in tests use a font without emoji.
- [ ] A share button for the invite code: there is no share package and adding packages is not allowed. Copy is there.
- [ ] Localized country names. `countries.dart` has English names only; this needs a shared source (f-core).

## Known issues / decisions
- `POST /family/members` has no `avatarUrl` in the contract, so the photo is saved with a follow-up `PATCH`. If that
  fails, the member still exists and the user sees "photo couldn't be saved, add it by editing".
- The contract does not require guardian consent on `PATCH` when the date of birth or country changes (GAP-05).
  - The mock does not enforce it there, to stay contract-exact.
  - The form still requires the checkbox when an admin edits a minor who has no consent.
  - A non-admin editing their own date of birth cannot give consent (not a self-patchable field).
- An admin cannot remove themselves or change their own role from these screens. Leaving the family belongs to
  Settings → Privacy (`LAST_ADMIN` handled there).
- An account holder's member email is shown read-only: it is their sign-in email, and the contract has no way to change
  the login email.
- SOS alerts resolved by the removal cascade get `resolution: null`, because no outcome is known ("safe" would be
  misleading).
- Invite code "large monospace": the characters sit in equal-width cells using the theme text style plus
  `AppTypography.tabularFigures`. No font is hard-coded; there is no monospace token.
- Non-admin `PATCH` with a disallowed key answers `403 FORBIDDEN` (per the shared repository doc) instead of silently
  stripping it.

## Hardening review (f-family-harden)
Full checklist: `docs/progress/f-family-harden.md`. Summary of the fixes:
- [x] Removed, unknown or malformed member ids (old notifications, a member removed while the screen is open) show
      `MemberGoneView` instead of "Something went wrong" with a useless Retry.
- [x] `DELETE` answering `NOT_FOUND` counts as "already removed", not an error.
- [x] Session sync (`FamilySessionSync`):
  - The signed-in member from `GET /family/members` and a fresher `GET /family` are merged into the session.
  - `NO_FAMILY` / `FORBIDDEN` re-read `/auth/me`.
  - So a demotion, promotion or removal made on another phone updates the admin actions, the forms and the router at
    once.
  - `familyProvider` refetches on a role change (the invite code is admin-only).
- [x] Failed mutations refetch what was stale (`NOT_FOUND`, `LAST_ADMIN`, `MEMBER_EMAIL_EXISTS`) or might have
      succeeded (offline, timeout, 5xx).
- [x] Add member:
  - A duplicate-name confirmation, which stops duplicates after a lost answer.
  - When the server answers `GUARDIAN_CONSENT_REQUIRED`, the consent checkbox appears; before, this was a dead end.
  - Inline field errors for `MEMBER_EMAIL_EXISTS` / `VALIDATION_ERROR` details.
  - Pickers are locked while saving.
- [x] Rapid repeated taps no longer open a screen or dialog twice (`pushIfTop` / `isTopRoute`).
- [x] Screens opened directly leave with `popOrGo` (a removal no longer throws "nothing to pop").
- [x] Mock:
  - `400 BAD_REQUEST` for malformed member ids.
  - Date-of-birth bounds checked by calendar day (1 Jan 1900 picked in India was rejected).
  - The age helper reuses the core `ageFrom`.
- [x] Tests: 79 → 126.
