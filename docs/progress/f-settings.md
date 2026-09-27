# f-settings — Flutter "settings" feature (progress)

Owner: f-settings · Scope: `family_hub_app/lib/features/settings/**`, `l10n_parts/settings.arb`,
`test/features/settings/**` · Tasks SET-08 … SET-19 (docs/TASKS.md §10).

## Built

### Screens (`presentation/screens/`)
- [x] `MoreScreen` (tab): profile header (avatar, name, designation or role, family name) → `/settings/profile`;
      **Family** (Members, Family settings (admins only), Notice board, Emergency cards, SOS history);
      **Preferences** (Language with native name, Appearance with theme label, Location sharing with current mode,
      Notifications status: on / off / not asked / unavailable, tap opens the phone settings); **Account** (Change
      password, Privacy & data, About); Log out with confirmation + busy state; app version at the bottom.
      Pull-to-refresh → `session.refreshMe()`; notification status re-read on app resume.
- [x] `ProfileScreen`: `ImagePickerField` (avatars, circular), name (required, ≤ 60), phone (`Validators.phone`), DOB
      (`DatePickerField`, not in the future), gender chips incl. "Prefer not to say"; read-only email / designation /
      role. Save enabled only when dirty, sends `MePatch.diff` only, `applyMe` + `markChanged({members})`,
      discard-changes guard on back.
- [x] `LanguageScreen`: "Phone language" + all 15 `AppLanguages` (native + English name, check mark). Sets the device
      locale, then best-effort `PATCH /me {locale}` (serialised so the last pick wins).
- [x] `AppearanceScreen`: theme mode (phone / light / dark radio group), Large text switch, live preview rendered with
      `AppTextScale.resolve` (correct even before the app-wide scale rebuilds).
- [x] `LocationSharingScreen`: 3 radio options with explanations; "Always" asks permission first (nothing changes
      without it), saves, uploads a first fix (`PUT /me/location`); "Your family can see your location" indicator with
      "last shared …" and "Share now"; permission notice (prompt again / open phone settings) that finishes the action
      automatically when the member returns from the settings with permission; "How it works" notes.
- [x] `PrivacyScreen`: consent text + Privacy Policy / Terms links; Export my data; Leave family (confirm,
      `LAST_ADMIN` dialog with "Go to members", then `session.leaveFamily()` + background `refreshMe()` → router sends
      to `/family-setup`); Delete account (password dialog; wrong password / network errors inline; `LAST_ADMIN` dialog;
      success signs out).
- [x] `DataExportScreen`: `GET /me/export` via `AsyncValueView` (loading / error+retry / empty / data), section
      summary with counts, selectable pretty JSON, "Copy all" to the clipboard.
- [x] `ChangePasswordScreen`: current / new / confirm, rules text, "must differ" check, `INVALID_CREDENTIALS` shown on
      the current-password field, autofill group.
- [x] `AboutScreen`: app name, version, mission line, SOS disclaimer with the family country's emergency number + call
      button, not-medical-advice, ledger-only note, Privacy Policy / Terms / privacy contact email / open-source licences.

### Application / data / domain
- [x] `application/settings_actions.dart` — `SettingsActions` (`settingsActionsProvider`): `saveProfile`, `setLanguage`,
      `syncAccountLocale`, `setLocationSharing` → `LocationSharingResult` (`saved | shared | noFix | permissionDenied`),
      `shareLocationNow`, `changePassword`, `leaveFamily`, `deleteAccount`, `logout`.
- [x] `application/background_sync.dart` — public `backgroundSyncProvider` (auto-dispose, watched by `HomeShell`) →
      `BackgroundLocationSync.syncIfDue()`: when the member's mode is `always`, uploads a fix on shell start and on every
      `AppLifecycleState.resumed`, at most every 10 minutes; never prompts, never tracks in the background, errors
      ignored, concurrent triggers share one run.
- [x] `application/location_upload_clock.dart` — shared throttle clock (`locationUploadClockProvider`, reset on
      account switch) + `settingsClockProvider` (test seam).
- [x] `application/settings_providers.dart` — `dataExportProvider`, `notificationStatusProvider`.
- [x] `data/system_settings.dart` — `SystemSettingsGateway` / `DeviceSystemSettings` (notification permission via
      FCM `getNotificationSettings` only when `PushNotificationService.isAvailable`; `Geolocator.openAppSettings`).
- [x] `domain/`: `DataExport` (+ section summaries, pretty JSON), `NotificationStatus`, `AppInfo` (version via
      `--dart-define=APP_VERSION / APP_BUILD_NUMBER`, `PRIVACY_CONTACT_EMAIL`).
- [x] `settings_routes.dart` — `settingsRoutes` for all 7 `AppRoutes.settings*` paths.

### Mock backend (`data/settings_mock_handlers.dart`)
- [x] `registerMeMocks`: `PATCH /me` (strict fields, validation, name → user + member, member fields without family →
      `NO_FAMILY`, Cloudinary-only avatar + local paths in mock mode, leaving `always` clears `lastLocation`),
      `PUT /me/location` (validation first, then `LOCATION_SHARING_DISABLED`), `POST /me/devices` (upsert, token moves
      to latest user), `DELETE /me/devices/:token` (own tokens only), `GET /me/export`, `DELETE /me` (password check,
      `LAST_ADMIN`, only member → whole family deleted), `POST /me/leave-family` (same rules; removes the profile,
      card, pending tasks; resolves active SOS; user stays signed in).
- [x] `registerUploadMocks`: `POST /uploads/signature` (folder validation, fake signature, `familyhub/<familyId>/<folder>`).

### l10n
- [x] `l10n_parts/settings.arb` — 121 keys, all prefixed `settings`, with descriptions / placeholders / plurals.

### Tests (`test/features/settings/`, 90 tests)
- [x] `settings_models_test.dart` — `DataExport` parsing, labels, `AppInfo`, FCM status mapping, throttle clock.
- [x] `settings_actions_test.dart` — every action with overridden API / location / session (diff bodies, applyMe,
      markChanged, best-effort locale, ordering, permission flow, LAST_ADMIN, wrong password, logout, export provider).
- [x] `background_sync_test.dart` — 10-minute throttle, modes, no prompt, errors, concurrency, lifecycle resume.
- [x] `settings_mock_handlers_test.dart` — all `/me*` + `/uploads/signature` routes against the seeded `MockDb`.
- [x] `more_screen_test.dart` — sections, admin-only entry, navigation, notifications link, log out, large text + RTL.
- [x] `settings_screens_test.dart` — profile, language, appearance, location (incl. resume after settings), change
      password, privacy (leave / delete / export + retry), about.

## Decisions (documented in code)
- The data export opens as a full-screen dialog (`DataExportScreen.open`) because `AppRoutes` has no export path.
- Leave family uses `SessionController.leaveFamily()` (applies the returned user), then a best-effort `refreshMe()`.
- "Phone language" sends the effective (resolved) language to the account.
- Background sync does not bump `DataScope.members` (it only updates what *others* see); a manual "Share now" does.
- Snackbars after leave / delete are shown through the root navigator context (the screen is gone by then).

## Pending / handoffs
- [ ] `AppRoutes.settingsDataExport` (`/settings/privacy/export`) — router owner; then register it in `settingsRoutes`.
- [ ] Push service API for permission status / opening notification settings (f-services); settings then drops its
      direct `FirebaseMessaging` / `Geolocator.openAppSettings` calls.
- [ ] App version from `package_info_plus` or `AppConfig` (core owner); today `AppInfo` reads `--dart-define`s.
- [ ] Translations of the 121 `settings*` keys into the 14 other languages (translation agents).
- [ ] Backend `/me` module should match the mock choices above (strict PATCH fields, GAP-04 clearing, leave-family
      cascade, `exportedAt` in the export) — or the contract should say otherwise.

## Known issues
- Saving the profile while a photo is still uploading saves without the new photo (the picker reports the URL later).
  Still open: needs an upload-state callback on `ImagePickerField` (handoff, see below).
- ~~`SelectableText` with a very large export may be slow on low-end phones~~ — fixed by f-settings-harden (lazy lines).
- ~~The current-password error stays visible until the next submit~~ — fixed by f-settings-harden (re-validation
  after the first submit).

## Hardening review (f-settings-harden)

Reviewed against docs/03 (contract), docs/05 (Flutter guide) and the backend module
`family_hub_backend/src/modules/me` (+ `uploads`). Everything below is covered by tests (130 in total).

### Contract / backend parity fixes (mock backend)
- [x] `PATCH /me`: blank strings clear nullable fields (backend `nullableField`); date of birth must be an ISO date
      (date-only = UTC midnight, date-time with zone, calendar-checked), ≤ now + 1 day, UTC year ≥ 1900;
      `422 GUARDIAN_CONSENT_REQUIRED` for a below-consent-age date without recorded consent (GAP-05).
- [x] `PUT /me/location`: `accuracy` ≤ 100 000 m, `null` allowed.
- [x] `POST /me/devices`: token trimmed + printable-ASCII check, `locale` stored as `null` when absent, at most 10
      devices per account; `DELETE /me/devices/:token` validates the token.
- [x] `GET /me/export`: backend shape (`formatVersion`, `family` without invite code, `currency`, `devices` with a
      masked `tokenSuffix`, `sessions`), contract objects via the feature serializers (ledger `amount` instead of the
      internal `amountMinor`, tasks also when completed by the caller, SOS lazily `expired`).
- [x] `POST /me/leave-family` / `DELETE /me` share one `removeSelfFromFamily`: only admins **with an account**
      count as "another admin" (`LAST_ADMIN`), the admin-removal cascade is reused (`FamilyMockService.removeMember`:
      pending tasks, card, active SOS resolved with `resolution: null`, ledger names), family ownership moves to the
      longest-standing remaining admin; leaving keeps sessions/devices, deleting ends them. Password ≤ 128 chars.
- [x] `POST /uploads/signature`: backend error text for the folder.

### App fixes
- [x] Stale session: `NO_FAMILY` / `LOCATION_SHARING_DISABLED` from settings actions or the background sync re-read
      `GET /auth/me` (router moves on / the real mode shows). `leaveFamily` treats `NO_FAMILY` as done when the
      refreshed session has no family.
- [x] `backgroundSyncProvider` also refreshes the session on app resume (at most every 2 minutes), so role changes,
      removal from the family, family settings and sharing-mode changes made elsewhere arrive without a restart.
- [x] Location: an old OS-cached position (> 10 min, `isShareableFix`) is never uploaded as "current"; unexpected
      first-upload errors keep the saved mode (`noFix`); the location screen checks the permission on open and on
      resume while "Always" is on and explains a revoked permission (then shares once it is back).
- [x] Profile: server field errors inline (name / phone / date of birth, photo rejected snackbar), local consent-age
      check on the date of birth, first selectable date 2 Jan 1900 (UTC-safe), re-validation after the first save.
- [x] Change password / delete-account dialog: errors clear as soon as the field is edited.
- [x] Privacy: the only member is told that leaving deletes the family.
- [x] Data export: summary rows for family, notification phones and sign-ins; JSON rendered lazily line by line
      inside a `SelectionArea` (tens of thousands of lines stay smooth); "Copy all" copies everything.
- [x] More tab: screen-reader label on the notifications "open settings" icon (previously unused key).
- [x] 8 new `settings*` keys (129 in `l10n_parts/settings.arb`).

See `docs/progress/f-settings-harden.md` for the edge-case matrix, remaining issues and handoffs.
