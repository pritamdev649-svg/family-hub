# f-settings-harden — review + hardening of the Flutter "settings" feature

Owner: f-settings-harden · Scope (same as f-settings): `family_hub_app/lib/features/settings/**`,
`l10n_parts/settings.arb`, `test/features/settings/**`. Builder notes: `docs/progress/f-settings.md`.

## Done
- [x] Contract conformance: every repository call (`MeRepository`, `AuthRepository.changePassword`) and every `/me`
      and `/uploads` mock handler checked against docs/03 **and** the backend module `src/modules/me` / `uploads`.
- [x] Guide conformance: tokens only (no raw sizes / colours / fonts), no user-visible literals, RTL-safe paddings,
      `AsyncValueView` for the export, `markChanged` after mutations, `mounted` checks after awaits, double-submit
      guards. The one unused key (`settingsNotificationsOpenSettings`) is now the icon's screen-reader label.
- [x] Mock backend mirrors the backend rules (details in `f-settings.md` → "Hardening review").
- [x] Edge-case fixes in actions, background sync and screens (matrix below).
- [x] Tests: 90 → 130 (`settings_mock_handlers_test` +12, `settings_actions_test` +8, `background_sync_test` +5,
      `settings_screens_test` +12, `settings_models_test` +3).
- [x] l10n: 8 new keys (`settingsProfileNameInvalid`, `settingsProfileDateOfBirthInvalid`,
      `settingsProfileGuardianConsentNeeded`, `settingsProfilePhotoRejected`, `settingsLeaveFamilyOnlyMemberMessage`,
      `settingsExportSectionFamily`, `settingsExportSectionDevices`, `settingsExportSectionSessions`).

## Edge-case matrix
| # | Case | Handling | Test |
|---|---|---|---|
| 1 | Offline / timeout on save | localized snackbar, edits kept, screen stays open | screens: network error keeps the edits |
| 2 | 401 expiry mid-action | `AuthInterceptor` refresh → retry, else `sessionExpired` → login; screens check `mounted` (no change needed) | existing interceptor tests |
| 3 | Removed from the family while in settings (`403 NO_FAMILY`) | session re-read → router opens family setup | actions: NO_FAMILY on save |
| 4 | Leave retried after a lost response (`NO_FAMILY`) | counts as done once the refreshed session has no family, else reported | actions: 2 tests |
| 5 | Sharing mode changed on another phone (`403 LOCATION_SHARING_DISABLED`) | share now / background sync resync the session | actions + background sync |
| 6 | Demoted / family changed by an admin (stale role, admin-only tiles) | session refreshed on app resume (≤ every 2 min) | background sync: 3 tests |
| 7 | `409 LAST_ADMIN` on leave / delete | dialog with "Go to members"; mock counts only admins **with an account** | screens + mock |
| 8 | `422` from `PATCH /me` | inline name / phone / date-of-birth messages, photo-rejected snackbar | screens: phone rejected |
| 9 | `422 GUARDIAN_CONSENT_REQUIRED` (date of birth under the consent age) | inline on the date field + local pre-check; mock enforces it | screens + mock |
| 10 | Only member leaves | confirmation says the family is deleted | screens: only member warned |
| 11 | Very long names / large text / RTL | wrapping layouts | screens: long name large text + RTL; existing More test |
| 12 | Time-zone boundaries for the date of birth | date-only parsed as UTC in the mock, first selectable date 2 Jan 1900, unchanged DOB never re-sent | mock + existing screen test |
| 13 | Rapid repeated taps | location modes, leave, save, submit all single-flight | screens: rapid taps, leaving twice |
| 14 | Location permission revoked while "Always" is on | explained on open / resume, shares automatically once granted | screens: 2 tests |
| 15 | Old cached GPS position | never uploaded as current (> 10 min, `isShareableFix`) | models + actions + background sync |
| 16 | Unexpected first-upload error | mode stays saved, `noFix` info | actions |
| 17 | Very large data export | lazy line list in a `SelectionArea`, "Copy all" copies everything | screens: large export; models |
| 18 | Wrong password shown after the user already fixed it | re-validation after first submit clears it on edit | screens: 2 tests |
| 19 | Empty export / export error | `AsyncValueView` empty state / retry (existing) | existing tests |
| 20 | Device token hygiene (mock) | trimmed, validated, ≤ 10 per account | mock |
| 21 | Export leaking internals (mock) | contract objects only, masked device tokens, no password / tokens / invite code | mock |
| 22 | Pagination end | not applicable: settings has no paginated lists | – |

## Pending / known issues
- [ ] Saving the profile while a photo is still uploading saves without it (needs `ImagePickerField` upload state).
- [ ] After changing the password on the real backend the app is signed out ~15 min later: the backend ends all
      sessions and returns fresh `tokens`, which `AuthRepository.changePassword` ignores (handoff below).
- [ ] Wrong `DELETE /me` passwords do not count towards the mock login lockout (the lockout is private to the auth mock).
- [ ] "Last shared …" on the location screen does not tick while the screen stays open.
- [ ] A resume can upload the location twice when the location screen's "finish after permission" and the background
      sync fire together (harmless; server keeps the newest).
- [ ] Translations of the 8 new keys (translation agents).

## Handoffs (files not owned here)
- **f-domain** `lib/shared/data/auth_repository.dart`: save the `tokens` returned by `POST /auth/change-password`
  (backend `endAllSessions` + `issueTokens`; also listed by b-auth).
- **core widgets** `lib/core/widgets/image_picker_field.dart`: add `ValueChanged<bool>? onUploadingChanged` so the
  profile screen can disable Save while a photo uploads.
- **f-family** `lib/features/family/data/family_mock_handlers.dart`: `FamilyMockService.requireAnotherAdmin` should
  count only admins with an account (backend `assertNotLastAdmin`); `removeMember` should move `family.ownerId` and
  expire stale SOS alerts first (backend `removeMemberCascade`); an `endSessions` flag would let the `/me` mocks drop
  their `userId: null` workaround.
- **f-sos** `lib/features/sos/data/sos_mock_handlers.dart`: expose a shared `SosAlert` serializer so the export can
  reuse it (settings has a small local one).
- **f-auth** `lib/features/auth/data/auth_mock_handlers.dart`: expose the lockout helper so `DELETE /me` wrong
  passwords count like the backend.
- **router owner**: `AppRoutes.settingsDataExport` (still opened as a full-screen dialog).
- **docs owner** `docs/03-API_CONTRACT.md`: change-password returns `{ changed, tokens }`; `GET /me/export` shape
  (`formatVersion`, `family`, `currency`, `devices`, `sessions`); `PATCH /me` may answer `422 GUARDIAN_CONSENT_REQUIRED`.
- **f-shell / home**: no extra resume refresh needed in `HomeShell` — `backgroundSyncProvider` now refreshes the
  session on resume.
