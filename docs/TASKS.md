# FamilyHub · Master Task List

> Module-wise task list for **Phase 1 (MVP)** plus the later-phase epics.
> Scope: [`01-PRODUCT_SCOPE.md`](01-PRODUCT_SCOPE.md) · API: [`03-API_CONTRACT.md`](03-API_CONTRACT.md) ·
> App rules: [`05-FLUTTER_GUIDE.md`](05-FLUTTER_GUIDE.md) · Backend rules: [`06-BACKEND_GUIDE.md`](06-BACKEND_GUIDE.md).

**How this file is maintained**

- Every task starts unchecked. Engineers report progress in `docs/progress/<label>.md`; the docs pass ticks items
  here (`- [x]`) from those reports. Do not tick items in this file directly from feature work.
- Tags: **[API]** backend (`family_hub_backend/`), **[App]** Flutter (`family_hub_app/`), **[Mock]** the app's
  in-memory mock backend, **[Test]** automated tests, **[Ops]** config / infrastructure / store work,
  **[Doc]** documentation, **[Legal]** non-engineering compliance work.
- "Done" for an [App] screen means: design tokens only, `AsyncValueView` (loading / error+retry / empty / data),
  busy state + no double submit on mutations, localized errors, `markChanged(...)` after success, all text via
  `context.l10n`, RTL-safe, works at 1.4× text scale.
- "Done" for an [API] endpoint means: routes → controller → service layering, zod validation, family scoping
  (other family → 404), contract error codes, tests for happy path + permissions + validation.

## Contents

1. [Foundation · Flutter](#1-foundation--flutter-ff)
2. [Foundation · Backend](#2-foundation--backend-fb)
3. [Auth](#3-auth-auth)
4. [Family & Members](#4-family--members-fam)
5. [Tasks](#5-tasks-task)
6. [Ledger & Goals](#6-ledger--goals-led)
7. [Notices](#7-notices-not)
8. [Emergency Card](#8-emergency-card-emc)
9. [SOS](#9-sos-sos)
10. [Settings & Privacy](#10-settings--privacy-set)
11. [Dashboard](#11-dashboard-dash)
12. [Push Notifications](#12-push-notifications-push)
13. [Uploads](#13-uploads-upl)
14. [i18n (15 languages)](#14-i18n-15-languages-i18n)
15. [Integration & QA](#15-integration--qa-qa)
16. [Docs](#16-docs-doc)
17. [Later phases](#later-phases)

---

## 1. Foundation · Flutter (FF)

- [ ] FF-01 [App] Design tokens in `lib/core/design/`: `AppSpacing` + `AppGap`, `AppRadius`, `AppDurations`, `AppColors` + `AppSemanticColors` (light/dark, `context.semanticColors`), `AppTypography`, `AppIcons`, barrel `design.dart`
- [ ] FF-02 [App] `AppTheme.light()` / `AppTheme.dark()` with all component themes (AppBar, Card, buttons, inputs, chips, NavigationBar, ListTile, SnackBar, Dialog, BottomSheet, FAB, SegmentedButton, progress) and the semantic colours extension
- [ ] FF-03 [App] Shared widgets in `lib/core/widgets/` (barrel `widgets.dart`): `AppButton`, `AppTextField`, `AsyncValueView`, `LoadingView`, `ErrorView`, `EmptyState`, `AppRefreshIndicator`, `AppCard`, `SectionHeader`, `MemberAvatar`, `AppNetworkImage`, `StatusChip`, `AppProgressBar`, `MoneyText`, `showConfirmDialog`, `SnackX`, `ImagePickerField`, `DatePickerField`, `AppDropdownField`, `ChoiceChipsField`, `ResponsiveCenter`, `PaginatedListView`, `OfflineBanner`
- [ ] FF-04 [App] `Fmt` formatter + `fmtProvider` (locale `<lang>_<COUNTRY>` fallback chain, family currency, `.toLocal()`)
- [ ] FF-05 [App] `Validators` (required, email, password, confirmPassword, min/maxLength, amount, phone, otp, inviteCode, compose) with native-digit normalisation
- [ ] FF-06 [App] `UrlActions` (call, openMap, openUrl, email) and `DateX` / `ageFrom`
- [ ] FF-07 [App] `lib/shared/json.dart` defensive parsing helpers
- [ ] FF-08 [App] l10n plumbing: `context.l10n`, `localizedErrorMessage` for every contract error code + network/timeout/unknown
- [ ] FF-09 [App] ARB fragment tooling: `tool/l10n.dart` + `tool/merge_arb.dart` (lock, duplicate-key detection) and shared fragments (`common`, `errors`, `validation`, `shared`, `widgets`, `services`, `home`)
- [ ] FF-10 [App] Networking: `ApiClient` (unwraps `data`, `getPaged`), `ApiException` + `ApiErrorCode`, `Paged<T>`, `dio_factory`, `LocaleInterceptor`, `AuthInterceptor` with single-flight refresh and `AuthEvents.sessionExpired`
- [ ] FF-11 [App] Storage: `TokenStorage` (flutter_secure_storage) and `LocalCache` (SharedPreferences session cache)
- [ ] FF-12 [App] `core_providers.dart` (prefs, token storage, cache, auth events, mock backend, dio, api client)
- [ ] FF-13 [Mock] Mock backend core: `MockBackend` (pattern routing), `MockDb` + `seedOnce`, `MockInterceptor` (envelope, 250–600 ms latency, error mapping), `mock_registry.dart`, core seed (Sharma Family, demo users, invite code `DEMO2345`, OTP `123456`)
- [ ] FF-14 [App] `SettingsController` (language, theme mode, text scale ≤ 1.4) persisted locally
- [ ] FF-15 [App] Router: `AppRoutes` (all paths + builders), `goRouterProvider` redirects (splash / public / verify-email / family-setup / home), `refreshListenable`, `StatefulShellRoute.indexedStack`
- [ ] FF-16 [App] `HomeShell` with NavigationBar (Home / Tasks / SOS / Money / More), `SosStatusBanner` slot, `SplashScreen`
- [ ] FF-17 [App] `main.dart` bootstrap (guarded Firebase init, prefs override, `ProviderScope`) and `app.dart` (`MaterialApp.router`, themes, locale, localization delegates, text-scale clamp, push route handling)
- [ ] FF-18 [App] Shared domain: `AuthUser`, `Family`, `Member` (+ enums, `GeoPoint`, age/ageGroup/isMinorIn), `AuthTokens`, `SessionState`
- [ ] FF-19 [App] Shared repositories: `AuthRepository`, `FamilyRepository`, `MeRepository` + `shared_providers.dart`
- [ ] FF-20 [App] `SessionController` (restore from tokens → `/auth/me`, offline fallback to cached session, login/register/logout/refreshMe/verifyEmail/applyMe/createFamily/joinFamily/handleSessionExpired) and derived providers (`currentUser/Member/Family`, `isAdmin`, `currentCountry`, `sessionUserId`, `membersProvider`, `memberByIdProvider`)
- [ ] FF-21 [App] Data-change bus `data_refresh.dart` (`DataScope`, `dataRefreshProvider`, `markChanged`)
- [ ] FF-22 [App] `shared_labels.dart` (role, gender, age group, location sharing mode + description)
- [ ] FF-23 [App] Config: `config/dev.example.json` and `config/dev.json` (mock mode by default), documented keys
- [ ] FF-24 [Ops] Android config: `INTERNET` in the main manifest, location permissions, `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_LOCATION`, `POST_NOTIFICATIONS`, notification icon, core library desugaring for `flutter_local_notifications`, app label "FamilyHub"
- [ ] FF-25 [Ops] iOS config: `Info.plist` usage strings (location when-in-use / always, camera, photo library), `UIBackgroundModes` (location, remote-notification), Push Notifications capability, `CFBundleLocalizations` for 15 languages, display name "FamilyHub"
- [ ] FF-26 [Ops] App icon and splash for Android and iOS
- [ ] FF-27 [Test] Unit tests: formatters, validators, json helpers, API client + interceptors (refresh single-flight), mock backend routing
- [ ] FF-28 [Test] `flutter analyze` reports zero issues with the project lints

## 2. Foundation · Backend (FB)

- [ ] FB-01 [API] `config/env.js` (zod-validated env, production guards) and `config/db.js`
- [ ] FB-02 [API] `app.js` `createApp()`: helmet, cors (allowlist), compression, json 100 kb, morgan (not in tests), locale middleware, rate limiters, `/api/v1` routes, 404, error handler; `trust proxy` for deployments behind a proxy
- [ ] FB-03 [API] `server.js`: connect DB → init push → listen, graceful shutdown (SIGINT/SIGTERM), exported `startServer`
- [ ] FB-04 [API] `lib/`: `ApiError` + codes, `response` (ok/created/paged), `validate` (zod blocks, `req.valid`), `crypto` (sha256, random tokens/digits, invite code, AES-256-GCM field encryption), `logger`
- [ ] FB-05 [API] `lib/`: `i18n` (t, pickLocale, normalizeLocale), `constants`, `countries` (identical to the app's `countries.dart`), `money`, `dates` (family timezone), `pagination`, `access` (findInFamily, assertAdmin, assertSelfOrAdmin), `mongoosePlugins` (`id`, no `_id`/`__v`)
- [ ] FB-06 [API] Middleware: `auth` (requireAuth / requireFamily / requireAdmin), `locale`, `error` (localized envelope, no internals), `rateLimit`
- [ ] FB-07 [API] Services: `serializers`, `memberDirectory`, `tokens` (issue, rotate with reuse detection, revoke), `mailer` (console fallback, test `outbox`), `push` (test `sentPushes`), `cloudinary`
- [ ] FB-08 [API] Models + indexes: User, RefreshToken (TTL), Otp (TTL), Family, Member, Device, Task, LedgerEntry, Goal, Notice, SosAlert, EmergencyCard
- [ ] FB-09 [API] `routes/index.js` mounting every module (emergency cards before family) and `GET /health` (`status`, `db`, `version`)
- [ ] FB-10 [API] `scripts/seed.js`: demo family and accounts identical to the app's mock seed
- [ ] FB-11 [API] `scripts/dev-memory.js` (in-memory MongoDB + seed + server) and the `npm run dev:memory` script in `package.json`
- [ ] FB-12 [API] `scripts/check-syntax.js` (`npm run check`)
- [ ] FB-13 [Test] `tests/helpers.js` (`setupTestApp`, `teardownTestApp`, `resetDb`, `registerFamilyAdmin`, `joinFamilyAs`, `addManagedMember`, `outbox`, `sentPushes`)
- [ ] FB-14 [API] `i18n/locales/en/common.json` (all `errors.*`, email layout)
- [ ] FB-15 [Test] Unit tests for money, dates (DST, month ranges, week start), crypto (encrypt/decrypt round trip), pickLocale, countries parity with the app list

## 3. Auth (AUTH)

**Backend**
- [ ] AUTH-01 [API] `POST /auth/register`: `create` mode (family + admin member) and `join` mode (member, or link to a pre-added member with the same email), consent required, locale, DOB, email normalisation, OTP email
- [ ] AUTH-02 [API] `POST /auth/login` with generic `INVALID_CREDENTIALS` and lockout (5 failures / 15 min → `429` with `retryAfterSeconds`)
- [ ] AUTH-03 [API] `POST /auth/refresh` with rotation and reuse detection (revoke all)
- [ ] AUTH-04 [API] `POST /auth/logout` (revoke refresh token, remove the optional device token)
- [ ] AUTH-05 [API] `POST /auth/verify-email` + `POST /auth/resend-verification` (10 min validity, 5 attempts, 60 s cooldown)
- [ ] AUTH-06 [API] `POST /auth/forgot-password` (no enumeration) + `POST /auth/reset-password` (revokes all refresh tokens)
- [ ] AUTH-07 [API] `POST /auth/change-password`
- [ ] AUTH-08 [API] `GET /auth/me` (`user`, `member|null`, `family|null`)
- [ ] AUTH-09 [API] `i18n/locales/en/auth.json`: verification and reset email subject/text
- [ ] AUTH-10 [Test] `tests/auth.test.js`: both register modes, linking, consent, duplicate email, lockout, refresh rotation + reuse, OTP expiry/attempts/cooldown, reset revokes sessions

**App**
- [ ] AUTH-11 [App] Welcome screen (create family / join with code / log in, language shortcut)
- [ ] AUTH-12 [App] Login screen (lockout message with remaining time, forgot-password link)
- [ ] AUTH-13 [App] Register screen: create & join modes (`?mode=` / `?code=`), country → currency/timezone defaults, DOB, password rules, consent checkbox with policy/terms links
- [ ] AUTH-14 [App] Verify-email screen: 6-digit OTP input, resend with cooldown timer, switch account / logout
- [ ] AUTH-15 [App] Forgot + reset password flow (OTP, new password, back to login)
- [ ] AUTH-16 [App] Family-setup screen for signed-in users without a family (create or join)
- [ ] AUTH-17 [App] Session-expired handling (message + redirect to login, cached data cleared)
- [ ] AUTH-18 [Mock] `auth_mock_handlers.dart` for every `/auth/*` endpoint (OTP `123456`)
- [ ] AUTH-19 [App] `l10n_parts/auth.arb`
- [ ] AUTH-20 [Test] SessionController + auth screens widget tests (validation, error mapping, redirects)

## 4. Family & Members (FAM)

**Backend**
- [ ] FAM-01 [API] `POST /family` and `POST /family/join` (`409 ALREADY_IN_FAMILY`, `400 INVALID_INVITE_CODE`, case-insensitive codes)
- [ ] FAM-02 [API] `GET /family`, `PATCH /family` (admin; country/currency/timezone validation), `POST /family/invite-code` (rotation); `inviteCode` only for admins
- [ ] FAM-03 [API] `GET /family/members` (admins first, then oldest → youngest, null DOB last), `GET /family/members/:id`
- [ ] FAM-04 [API] `POST /family/members`: guardian-consent rule by country, email uniqueness (`409 MEMBER_EMAIL_EXISTS`), invitation email in the creator's locale, managed profiles
- [ ] FAM-05 [API] `PATCH /family/members/:id`: admin (all fields incl. role) vs self (limited fields), `409 LAST_ADMIN`
- [ ] FAM-06 [API] `DELETE /family/members/:id` cascade: unlink user, revoke tokens, remove devices, delete pending tasks + emergency card, resolve active SOS, keep ledger entries
- [ ] FAM-07 [API] `member_joined` push + `i18n/locales/en/family.json` (invitation email, push)
- [ ] FAM-08 [Test] `tests/family.test.js`: permissions, other-family 404, consent rule per country, last-admin rules, cascade

**App**
- [ ] FAM-09 [App] Members list screen (role, designation, age group, "no account" badge)
- [ ] FAM-10 [App] Member detail (call/email actions, tasks, emergency card link, admin actions)
- [ ] FAM-11 [App] Add/edit member form: DOB → minor detection → mandatory guardian-consent checkbox, role, designation, email/phone, avatar
- [ ] FAM-12 [App] Family settings (admin): name, country, currency, timezone, invite code copy/share/regenerate
- [ ] FAM-13 [App] Remove member with confirmation; `LAST_ADMIN` handled with a clear message
- [ ] FAM-14 [Mock] `family_mock_handlers.dart` (all `/family*` endpoints)
- [ ] FAM-15 [App] `l10n_parts/family.arb`
- [ ] FAM-16 [Test] Member model/age tests, add-member form widget test (guardian consent)

## 5. Tasks (TASK)

**Backend**
- [ ] TASK-01 [API] `GET /tasks` with `assigneeId`, `status`, `due=overdue|today|week` (family timezone), contract sort orders, pagination
- [ ] TASK-02 [API] `POST /tasks` (admin → anyone, member → self), `task_assigned` push when assignee ≠ creator
- [ ] TASK-03 [API] `GET/PATCH/DELETE /tasks/:id` (admin or creator)
- [ ] TASK-04 [API] `POST /tasks/:id/complete` and `/reopen` (assignee or admin, idempotent), `task_completed` push
- [ ] TASK-05 [API] `i18n/locales/en/tasks.json` push texts
- [ ] TASK-06 [Test] `tests/tasks.test.js`: filters, sorting, permissions, idempotency, pushes

**App**
- [ ] TASK-07 [App] Tasks tab: mine / all / by member, pending / done, due filters, pagination, pull to refresh
- [ ] TASK-08 [App] Task detail with complete/reopen/edit/delete per permission
- [ ] TASK-09 [App] Create/edit form (assignee limited to self for members, category chips, priority, due date, `?assigneeId=`)
- [ ] TASK-10 [App] `TaskTile` public widget (overdue highlight, category icon, assignee avatar)
- [ ] TASK-11 [Mock] `tasks_mock_handlers.dart` + seeded tasks
- [ ] TASK-12 [App] `l10n_parts/tasks.arb` (+ `TaskCategory/TaskPriority/TaskStatus` labels)
- [ ] TASK-13 [Test] `FamilyTask` model tests, tasks screen/form widget tests

## 6. Ledger & Goals (LED)

**Backend**
- [ ] LED-01 [API] `GET /ledger/entries` (`month` in family timezone, type/member/goal filters, admin vs member visibility, `date` desc, pagination)
- [ ] LED-02 [API] `POST /ledger/entries` (category valid for type, amount > 0 ≤ 1e12, date ≤ today + 1 day, member only for self)
- [ ] LED-03 [API] `PATCH/DELETE /ledger/entries/:id` (goal-linked amount locked; delete decrements goal and reopens it below target)
- [ ] LED-04 [API] `GET /ledger/summary` (family scope for admins, personal for members, `byCategory`)
- [ ] LED-05 [API] Goals: `GET/POST/PATCH/DELETE /goals` (admin writes; delete detaches entries)
- [ ] LED-06 [API] `POST /goals/:id/contributions` (creates `expense/savings` entry, achieves goal, `goal_achieved` push, rejects archived goals)
- [ ] LED-07 [API] Minor-unit storage via `money.js` everywhere; `i18n/locales/en/ledger.json`
- [ ] LED-08 [Test] `tests/ledger.test.js` + `tests/goals.test.js`: visibility, summaries across month boundaries/timezones, rounding, goal transitions

**App**
- [ ] LED-09 [App] Money tab: month switcher, `MonthSummaryCard`, active goals, recent entries, add income/expense actions
- [ ] LED-10 [App] Entries list with filters and pagination
- [ ] LED-11 [App] Add/edit entry form (type, locale-tolerant amount input, category chips per type, date, member picker for admins)
- [ ] LED-12 [App] Goals: create/edit, detail with contributions list, contribute sheet, archive, achieved state
- [ ] LED-13 [App] Public widgets `GoalProgressCard` and `MonthSummaryCard`
- [ ] LED-14 [Mock] `ledger_mock_handlers.dart` (entries, summary, goals, contributions) + seed
- [ ] LED-15 [App] `l10n_parts/ledger.arb` (+ category labels and icons)
- [ ] LED-16 [Test] Ledger/goal model tests, amount parsing tests, form widget tests

## 7. Notices (NOT)

**Backend**
- [ ] NOT-01 [API] `GET /notices` (pinned first, newest first, pagination)
- [ ] NOT-02 [API] `POST /notices` (`pinned` only for admins, Cloudinary-only `imageUrl`), `notice` push to other members
- [ ] NOT-03 [API] `PATCH/DELETE /notices/:id` (author or admin; pin only admin)
- [ ] NOT-04 [API] `i18n/locales/en/notices.json`
- [ ] NOT-05 [Test] `tests/notices.test.js`

**App**
- [ ] NOT-06 [App] Notice board screen (pinned section, images, pagination)
- [ ] NOT-07 [App] Create/edit notice with optional image (`ImagePickerField`, folder `notices`) and pin toggle for admins
- [ ] NOT-08 [App] `NoticeCard` public widget
- [ ] NOT-09 [Mock] `notices_mock_handlers.dart` + seed
- [ ] NOT-10 [App] `l10n_parts/notices.arb`
- [ ] NOT-11 [Test] Notice model + screen tests

## 8. Emergency Card (EMC)

**Backend**
- [ ] EMC-01 [API] `GET /family/members/:memberId/emergency-card` (empty card with `updatedAt: null` when none)
- [ ] EMC-02 [API] `PUT …/emergency-card` (self or admin; list/length limits; AES-256-GCM for allergies, medications, conditions, insurance policy number, notes)
- [ ] EMC-03 [Test] `tests/emergencyCards.test.js` (encryption at rest verified in the raw document, permissions, limits)

**App**
- [ ] EMC-04 [App] Emergency cards list (every member, reachable within two taps from home and from SOS)
- [ ] EMC-05 [App] Card view: large, high-contrast layout, one-tap call for doctor and contacts, blood group prominent
- [ ] EMC-06 [App] Edit form: blood group, list editors (allergies, medications, conditions ≤ 20 × 80), doctor, insurance, contacts ≤ 5, notes ≤ 500
- [ ] EMC-07 [App] `EmergencyCardView` public widget + `emergencyCardProvider(memberId)`
- [ ] EMC-08 [Mock] `emergency_card_mock_handlers.dart` + seed
- [ ] EMC-09 [App] `l10n_parts/emergency_card.arb` (+ blood group labels)
- [ ] EMC-10 [Test] Card model + form tests
- [ ] EMC-11 [App] (decision) Offline copy of the family's cards in secure storage for no-network emergencies

## 9. SOS (SOS)

**Backend**
- [ ] SOS-01 [API] `POST /sos` (idempotent when already active, 15 min expiry, drop location when mode is `never`, high-priority `sos` push)
- [ ] SOS-02 [API] `GET /sos/active`, `GET /sos/history` (pagination), `GET /sos/:id` (trail ≤ 100, oldest first)
- [ ] SOS-03 [API] `POST /sos/:id/location` (owner only, 3 s store throttle, `$push` + `$slice: -100`, `409 SOS_NOT_ACTIVE`, `403 LOCATION_SHARING_DISABLED`)
- [ ] SOS-04 [API] `POST /sos/:id/resolve` (owner or admin, idempotent, `sos_resolved` push)
- [ ] SOS-05 [API] Lazy expiry (active past `expiresAt` → persisted/returned as `expired`)
- [ ] SOS-06 [API] `i18n/locales/en/sos.json`
- [ ] SOS-07 [Test] `tests/sos.test.js` (idempotency, throttling, trail cap, expiry, permissions, pushes)

**App**
- [ ] SOS-08 [App] SOS tab: large SOS button, 3 s countdown with cancel, country emergency number + call button, "alerts your family, not emergency services" text, location-mode hint
- [ ] SOS-09 [App] Sender active-alert screen: sharing indicator, "I'm okay" with resolution choice, time left
- [ ] SOS-10 [App] Live tracking via `LocationService.track` (Android foreground service notification, iOS indicator), uploads every ≥ 5 s, stops on resolve / expiry / `409`
- [ ] SOS-11 [App] Receiver alert screen `/sos/alert/:id`: poll every 5 s, map link, call member, trail, resolve (admins)
- [ ] SOS-12 [App] `SosStatusBanner` in the home shell (poll `GET /sos/active` every 15 s)
- [ ] SOS-13 [App] SOS history screen + `SosAlertTile`, `activeSosAlertsProvider`
- [ ] SOS-14 [Mock] `sos_mock_handlers.dart` (incl. lazy expiry)
- [ ] SOS-15 [App] `l10n_parts/sos.arb`
- [ ] SOS-16 [Test] SOS model tests, countdown/cancel widget test, tracker stop conditions

## 10. Settings & Privacy (SET)

**Backend**
- [ ] SET-01 [API] `PATCH /me` (profile, locale, location sharing, Cloudinary-only avatar)
- [ ] SET-02 [API] `PUT /me/location` (`always` only)
- [ ] SET-03 [API] `POST /me/devices` (upsert, token moves to latest user) and `DELETE /me/devices/:token`
- [ ] SET-04 [API] `GET /me/export` (personal data JSON)
- [ ] SET-05 [API] `DELETE /me` (password check, cascade, last-admin rule, delete family when last member)
- [ ] SET-06 [API] `POST /me/leave-family`
- [ ] SET-07 [Test] `tests/me.test.js`

**App**
- [ ] SET-08 [App] More screen (profile header, family, emergency cards, notices, settings sections)
- [ ] SET-09 [App] Profile edit (name, phone, gender, DOB, avatar)
- [ ] SET-10 [App] Language screen (15 languages in native names; updates UI, `Accept-Language` and `PATCH /me`)
- [ ] SET-11 [App] Appearance screen (theme mode, text size up to 1.4× with preview)
- [ ] SET-12 [App] Location sharing screen (never / SOS only / always, OS permission flow, "who can see" explanation, indicator explanation)
- [ ] SET-13 [App] Privacy screen: export my data (share JSON), delete account (password + explanation + `LAST_ADMIN`), leave family
- [ ] SET-14 [App] Change password screen
- [ ] SET-15 [App] About screen (version, privacy policy, terms, SOS disclaimer, open-source licences, privacy contact)
- [ ] SET-16 [App] `backgroundSyncProvider`: refresh location on resume when mode is `always`, re-register push token
- [ ] SET-17 [Mock] `settings_mock_handlers.dart` (all `/me*` + `/uploads/signature`)
- [ ] SET-18 [App] `l10n_parts/settings.arb`
- [ ] SET-19 [Test] Settings controller + screens tests
- [ ] SET-20 [Doc] Resolve the compliance gaps in [`08-COMPLIANCE.md` §9](08-COMPLIANCE.md) (GAP-01…GAP-12): contract change first, then [API]/[App] tasks

## 11. Dashboard (DASH)

- [ ] DASH-01 [API] `GET /dashboard` (family, me, per-member counts in family timezone, my tasks ≤ 5, goals ≤ 3, notices ≤ 3, active SOS, month summary) with few queries
- [ ] DASH-02 [Test] `tests/dashboard.test.js` (counts, limits, member vs admin summary scope)
- [ ] DASH-03 [App] `DashboardScreen`: active SOS on top, my tasks, members' progress, goals, notices, month summary, quick actions
- [ ] DASH-04 [App] `dashboardProvider` watching every `DataScope`
- [ ] DASH-05 [App] New-family empty states / onboarding hints (add members, first task, first goal)
- [ ] DASH-06 [Mock] `dashboard_mock_handlers.dart` (computed from the mock collections)
- [ ] DASH-07 [App] `l10n_parts/dashboard.arb`
- [ ] DASH-08 [Test] Dashboard widget test with overridden provider

## 12. Push Notifications (PUSH)

- [ ] PUSH-01 [API] `services/push.js`: `initPush` from service account path/base64, `sendToMembers` (members → users → devices, per-device locale, channels `sos_alerts`/`general`, batches of 500, invalid-token cleanup, never throws, fire-and-forget)
- [ ] PUSH-02 [API] Push texts for every type in the `en` namespaces (`sos`, `sos_resolved`, `task_assigned`, `task_completed`, `notice`, `goal_achieved`, `member_joined`); no sensitive data in texts
- [ ] PUSH-03 [Test] Push service tests (locale selection, exclusions, invalid tokens) using `sentPushes`
- [ ] PUSH-04 [App] `PushNotificationService`: init, permission request, token registration + refresh, Android channels, foreground display, tap routing incl. cold start (`routeTaps`), unregister on logout; no-op without Firebase
- [ ] PUSH-05 [App] Route handling in `app.dart` for every contract route (`/sos/alert/:id`, `/tasks/:id`, `/notices`, `/money`, `/members/:id`)
- [ ] PUSH-06 [Ops] Firebase projects (dev/prod), `flutterfire configure`, APNs key, service account in backend env ([`09-SETUP_AND_RUN.md` §6](09-SETUP_AND_RUN.md))
- [ ] PUSH-07 [Test] Manual push matrix on a real Android and a real iPhone (foreground, background, killed; SOS channel sound)

## 13. Uploads (UPL)

- [ ] UPL-01 [API] `POST /uploads/signature` (`avatars|notices`, folder `familyhub/<familyId>/<folder>`, error when Cloudinary is not configured)
- [ ] UPL-02 [API] Shared validator: only `https://res.cloudinary.com/...` for `avatarUrl` / `imageUrl`
- [ ] UPL-03 [Test] `tests/uploads.test.js`
- [ ] UPL-04 [App] `CloudinaryService`: signed upload (default), unsigned preset (dev), mock local path, progress callback, localized errors
- [ ] UPL-05 [App] `ImagePickerField` (camera/gallery sheet, resize 1600 px / quality 80, progress, remove)
- [ ] UPL-06 [Ops] Cloudinary account: upload restrictions (formats, max size), per-environment credentials

## 14. i18n (15 languages) (I18N)

**App translations** (`family_hub_app/lib/l10n/app_<code>.arb`, every key of `app_en.arb`, correct plural categories)
- [ ] I18N-01 [App] `hi` Hindi
- [ ] I18N-02 [App] `bn` Bengali
- [ ] I18N-03 [App] `ta` Tamil
- [ ] I18N-04 [App] `te` Telugu
- [ ] I18N-05 [App] `mr` Marathi
- [ ] I18N-06 [App] `gu` Gujarati
- [ ] I18N-07 [App] `kn` Kannada
- [ ] I18N-08 [App] `ml` Malayalam
- [ ] I18N-09 [App] `pa` Punjabi
- [ ] I18N-10 [App] `ar` Arabic (RTL)
- [ ] I18N-11 [App] `es` Spanish
- [ ] I18N-12 [App] `fr` French
- [ ] I18N-13 [App] `pt` Portuguese
- [ ] I18N-14 [App] `de` German

**Backend translations** (`family_hub_backend/src/i18n/locales/<code>/*.json`, same files and keys as `en/`)
- [ ] I18N-15 [API] `hi`
- [ ] I18N-16 [API] `bn`
- [ ] I18N-17 [API] `ta`
- [ ] I18N-18 [API] `te`
- [ ] I18N-19 [API] `mr`
- [ ] I18N-20 [API] `gu`
- [ ] I18N-21 [API] `kn`
- [ ] I18N-22 [API] `ml`
- [ ] I18N-23 [API] `pa`
- [ ] I18N-24 [API] `ar`
- [ ] I18N-25 [API] `es`
- [ ] I18N-26 [API] `fr`
- [ ] I18N-27 [API] `pt`
- [ ] I18N-28 [API] `de`

**Cross-cutting**
- [ ] I18N-29 [Test] Key-parity checks: every app ARB has every template key with valid placeholders; every backend locale has every `en` key
- [ ] I18N-30 [Test] RTL audit in Arabic (checklist in [`07-I18N_AND_COUNTRIES.md` §8](07-I18N_AND_COUNTRIES.md))
- [ ] I18N-31 [Test] Script rendering + 1.4× text scale audit for Indic languages on a low-end Android device
- [ ] I18N-32 [App] Locale resolution (settings → device → en) and `Accept-Language` on every request
- [ ] I18N-33 [Ops] Localized store listings and iOS permission strings (`InfoPlist.strings`) for the 15 languages
- [ ] I18N-34 [API] (later) Several emergency numbers per country (police / ambulance / fire): contract + both country lists

## 15. Integration & QA (QA)

- [ ] QA-01 [Test] Contract conformance: the same request/response fixtures pass against the mock backend and the Node API
- [ ] QA-02 [Test] Cross-family isolation: every family-scoped endpoint returns `404` for another family's ids
- [ ] QA-03 [Test] End-to-end happy path on Android emulator + iOS simulator against the real API: register (create) → verify → add managed child with guardian consent → second member joins by code → tasks → ledger + goal → notice with image → SOS on device A seen live on device B → resolve → emergency card → export → delete account
- [ ] QA-04 [Test] Offline behaviour: start offline (cached session), offline banner, failed mutation keeps form input, retry works
- [ ] QA-05 [Test] Token expiry: access token expiry mid-session (silent refresh), refresh reuse (forced logout)
- [ ] QA-06 [Test] Accessibility: TalkBack and VoiceOver labels, 48 dp targets, contrast in light/dark
- [ ] QA-07 [Test] Low-end device pass (2 GB RAM Android): startup time, list scrolling, image memory
- [ ] QA-08 [Test] Small screen (360 × 640 dp) and tablet (`ResponsiveCenter`) layouts
- [ ] QA-09 [Test] Timezone checks: family in `Asia/Kolkata` and `America/New_York`, month boundaries, DST change week
- [ ] QA-10 [Test] Location permission matrix: denied, denied forever, services off, "while using" only; SOS still sends without location
- [ ] QA-11 [Test] Mock mode demo script works end to end with `demo@familyhub.app`
- [ ] QA-12 [Test] `flutter analyze`, `flutter test`, `npm test`, `npm run check` all green
- [ ] QA-13 [Ops] Release builds: `flutter build appbundle` and `flutter build ipa` with production config (HTTPS API, real Firebase)
- [ ] QA-14 [Ops] Staging deployment (API + MongoDB Atlas + SMTP + Cloudinary + FCM) with health check monitoring
- [ ] QA-15 [Test] Security review: rate limits, lockout, no PII in logs, secrets not in the app bundle, dependency audit (`npm audit`)

## 16. Docs (DOC)

- [ ] DOC-01 [Doc] Root `README.md` (overview, repo layout, quick start, links)
- [ ] DOC-02 [Doc] `docs/README.md` index
- [ ] DOC-03 [Doc] `01-PRODUCT_SCOPE.md`
- [ ] DOC-04 [Doc] `02-ARCHITECTURE.md` (system, auth, push, SOS, upload, i18n, offline, mock, security diagrams)
- [ ] DOC-05 [Doc] `07-I18N_AND_COUNTRIES.md`
- [ ] DOC-06 [Doc] `08-COMPLIANCE.md` (checklists with status, gaps, breach runbook draft)
- [ ] DOC-07 [Doc] `09-SETUP_AND_RUN.md` (mock mode, backend, devices, Firebase, Cloudinary, SMTP, troubleshooting)
- [ ] DOC-08 [Doc] `TASKS.md` (this file)
- [ ] DOC-09 [Doc] Final pass: tick this file from `docs/progress/*.md`, update statuses in `08-COMPLIANCE.md`, fix drift between docs and code
- [ ] DOC-10 [Legal] Privacy policy, terms of service, children's notice and SOS disclaimer (reviewed by counsel), translated into the 15 languages
- [ ] DOC-11 [Legal] Google Play Data safety form, target-audience declaration, foreground-service (location) declaration; Apple privacy nutrition labels
- [ ] DOC-12 [Doc] Breach response runbook finalised (owners, contacts, templates) from the draft in `08-COMPLIANCE.md` §8
- [ ] DOC-13 [Doc] Pilot guide for families (how to start, what to try, how to give feedback)

---

## Later phases

Epics from the concept roadmap ([`00-CONCEPT.md` §4](00-CONCEPT.md)); rationale in
[`01-PRODUCT_SCOPE.md` §4](01-PRODUCT_SCOPE.md). Each epic will be broken into [API]/[App] tasks when it is scheduled.

### Phase 2: accountability, money & engagement
- [ ] P2-01 Sub-wallets per member with parent-set spending limits (ledger only; licensed payment partner review before any real money)
- [ ] P2-02 Savings goal visualisation (history charts, projections)
- [ ] P2-03 Monthly family review: auto-generated summary of tasks done/missed and spending (needs a scheduled job runner)
- [ ] P2-04 Recurring expenses (bills, subscriptions) with reminders
- [ ] P2-05 Fine-grained permission tiers (custom roles, per-module visibility)
- [ ] P2-06 Documents & Records Vault, metadata only (category, owners, expiry reminders; DigiLocker research for India)
- [ ] P2-07 Family Feed / Moments (photo posts, reactions)
- [ ] P2-08 Suggestions Box (upvotes, admin status)
- [ ] P2-09 Requests module (peer-to-peer asks: open → accepted → done)
- [ ] P2-10 Household logistics: shared shopping list and inventory
- [ ] P2-11 Audit log of admin actions on children's data (GAP-09) and family deletion (GAP-11)

### Phase 3: health, growth & unified view
- [ ] P3-01 Health profile per member (height/weight logs, doctor visit reminders; encrypted, wellness only)
- [ ] P3-02 Nutrition guidance: weekly meal plans by age/activity
- [ ] P3-03 Education and skill tracking for kids
- [ ] P3-04 Personal growth goals for adults
- [ ] P3-05 Vaccination and medicine schedule reminders (country schedules, not medical advice)
- [ ] P3-06 Shared family calendar (tasks, health, documents, meetings, birthdays)
- [ ] P3-07 Domestic help / staff management (schedule, pay via ledger, attendance, contacts)
- [ ] P3-08 Full document storage in the Vault (encrypted object storage, per-document access)

### Phase 4: governance & polish
- [ ] P4-01 Family meeting scheduler with logged decisions
- [ ] P4-02 "Family concern" log (private issues to parents, child-safety design)
- [ ] P4-03 Unified notification feed across modules
- [ ] P4-04 Exportable monthly family report (PDF, all scripts)
- [ ] P4-05 Family chat and sub-groups (real-time infrastructure)
- [ ] P4-06 Multi-family support (product for clients)

### Cross-cutting improvements (unscheduled)
- [ ] X-01 Simplified large-text mode for elderly members
- [ ] X-02 Voice input for logging tasks and entries
- [ ] X-03 Offline write queue
- [ ] X-04 Real-time channel (WebSocket/SSE) for SOS and dashboards
- [ ] X-05 Background location for "always share" (with store policy review)
- [ ] X-06 Date-only fields as `YYYY-MM-DD` strings (timezone edge case, see `07-I18N_AND_COUNTRIES.md` §10)
- [ ] X-07 Admin web console, privacy-preserving analytics, crash reporting
