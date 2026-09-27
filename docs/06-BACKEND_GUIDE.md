# 06 · Backend Guide (binding conventions)

Backend: `family_hub_backend/` · Node.js ≥ 20 (dev machine: 25) · **JavaScript ES modules** (`"type": "module"`,
always `import … from './x.js'` with the `.js` extension) · Express 5 · Mongoose 9 · Zod 4 · JWT · bcryptjs ·
Nodemailer · firebase-admin (FCM) · Cloudinary SDK · tests with `node:test` + `supertest` + `mongodb-memory-server`.
Installed packages: see `package.json` — **do not add dependencies** unless you are the owner named in the task.

> Every endpoint implements `docs/03-API_CONTRACT.md` exactly.

## 1. Golden rules

1. **Layers:** `routes` (wiring + `validate()` + auth middleware) → `controller` (HTTP only: read `req.valid`, call
   service, respond with `ok/created/paged`) → `service` (business rules, DB access, throws `ApiError`) → `models`.
   No business logic in routes/controllers; no `res` in services.
2. **DRY:** shared helpers live in `src/lib/` and `src/services/`; serialisers for User/Family/Member live in
   `src/services/serializers.js`; family-scoped lookups via `src/lib/access.js`. Never re-implement them in a module.
3. **Family scoping = security.** Every query on family data filters by `familyId: req.user.familyId`. A document
   from another family → `ApiError.notFound()` (never 403, never leak existence).
4. **Validation with zod** in `<module>.schemas.js`, applied by `validate({ body, query, params })`; controllers read
   `req.valid.body|query|params` (Express 5: `req.query` is read-only).
5. **Errors:** throw `ApiError` (or the static helpers). Unknown errors become `500 INTERNAL_ERROR` without leaking
   internals. Error messages are localized by the error middleware from `errors.<CODE>` keys.
6. **Express 5** forwards rejected promises from async handlers to the error middleware — no `asyncHandler` needed.
7. **Money:** store integer minor units (`amountMinor`, `targetMinor`, `savedMinor`); convert with `src/lib/money.js`
   (`toMinor`, `fromMinor`). API always exposes decimal major units.
8. **Dates:** store `Date` (UTC). Month ranges and "today/this week" use the **family timezone** via `src/lib/dates.js`.
9. **Idempotency & races:** state transitions (`complete`, `resolve`, SOS create) are idempotent; counters use atomic
   `$inc`; uniqueness enforced by indexes (handle duplicate-key `11000` → `409`).
10. **Privacy:** never return `passwordHash`, token hashes, OTP hashes, raw encrypted blobs. `inviteCode` only to admins.
    `lastLocation` only when that member shares `always`. Log no personal data.

## 2. Structure

```
src/
  server.js                 connect DB → init push → listen; graceful shutdown (SIGINT/SIGTERM)
  app.js                    export function createApp(): helmet, cors, compression, json(100kb), morgan (not in test),
                            locale middleware, rate limiters, /api/v1 routes, 404, error handler
  config/env.js · config/db.js
  lib/
    ApiError.js · response.js (ok, created, paged) · validate.js (validate + zod blocks) · crypto.js · logger.js
    i18n.js                 t(locale, key, vars) · pickLocale(header) · SUPPORTED_LOCALES
    constants.js            all enums (roles, categories, statuses, blood groups, push types, upload folders, locales)
    countries.js            COUNTRIES map (code → { currency, consentAge, emergencyNumber }) · consentAge(code) · isCountry(code) · CURRENCIES
    money.js · dates.js · pagination.js · access.js · mongoosePlugins.js
  middleware/  auth.js (requireAuth, requireFamily, requireAdmin) · locale.js · error.js · rateLimit.js
  services/    mailer.js · push.js · cloudinary.js · tokens.js · serializers.js · memberDirectory.js
  models/      User · RefreshToken · Otp · Family · Member · Device · Task · LedgerEntry · Goal · Notice · SosAlert · EmergencyCard · index.js
  modules/<module>/  <module>.routes.js (default export Router) · <module>.controller.js · <module>.service.js · <module>.schemas.js
  routes/index.js   mounts all module routers under /api/v1
  i18n/locales/<lang>/<namespace>.json   (namespace = file name; key "tasks.push.assigned.title" → file tasks.json { "push": { "assigned": { "title": … }}})
tests/  helpers.js · <module>.test.js
scripts/ seed.js · dev-memory.js (runs the API on an in-memory MongoDB) · check-syntax.js
```

Module folders and mount points (`src/routes/index.js`):

| Module | Mount | File |
|---|---|---|
| health | `/health` | inline |
| auth | `/auth` | `modules/auth/auth.routes.js` |
| me | `/me` | `modules/me/me.routes.js` |
| family | `/family` | `modules/family/family.routes.js` |
| emergencyCards | `/family/members/:memberId/emergency-card` (`Router({ mergeParams: true })`) | `modules/emergencyCards/emergencyCards.routes.js` — **mounted before** the family router |
| tasks | `/tasks` | `modules/tasks/tasks.routes.js` |
| ledger | `/ledger` | `modules/ledger/ledger.routes.js` |
| goals | `/goals` | `modules/ledger/goals.routes.js` |
| notices | `/notices` | `modules/notices/notices.routes.js` |
| sos | `/sos` | `modules/sos/sos.routes.js` |
| dashboard | `/dashboard` | `modules/dashboard/dashboard.routes.js` |
| uploads | `/uploads` | `modules/uploads/uploads.routes.js` |

## 3. Shared services (exact exports)

- `middleware/auth.js`: `requireAuth` (Bearer JWT → `401 TOKEN_EXPIRED` if expired, `401 UNAUTHORIZED` otherwise; loads
  user + member; sets `req.user = { id, email, name, locale, emailVerified, familyId, memberId, role }` — ids as strings,
  `familyId/memberId/role` null when no family), `requireFamily` (`403 NO_FAMILY`), `requireAdmin` (`403 FORBIDDEN`).
- `services/tokens.js`: `signAccessToken(user)`, `issueTokens(user, { ip, userAgent })` → `{ accessToken, refreshToken, expiresIn }`,
  `rotateRefreshToken(rawToken, meta)` (reuse detection → revoke all + `401 INVALID_REFRESH_TOKEN`), `revokeRefreshToken(raw)`, `revokeAllUserTokens(userId)`.
- `services/serializers.js`: `serializeUser(user)`, `serializeFamily(family, { isAdmin, memberCount })`, `serializeMember(member)`
  (applies the `lastLocation` privacy rule), `serializeMembers(list)`.
- `services/memberDirectory.js`: `getMemberMap(familyId)` → `Map<memberIdString, memberDoc>` (families are small; one query
  per request) and `nameOf(map, id)` — used to fill `assigneeName`, `createdByName`, `authorName`, `memberName`.
- `services/mailer.js`: `sendMail({ to, subject, text, html })`, `sendTemplate({ to, locale, template, vars })` where `template`
  = `"<namespace>.<name>"` → i18n keys `<namespace>.email.<name>.subject|text`. No SMTP configured → logs to console. In
  tests every mail is pushed to the exported `outbox` array.
- `services/push.js`: `initPush()`, `isPushEnabled()`, `sendToMembers({ familyId, memberIds /* optional: default all */, excludeMemberIds = [], type, id, route, titleKey, bodyKey, vars = {}, highPriority = false })`
  — resolves members → users → devices, localizes title/body **per device locale** (fallback user locale → `en`), uses
  channel `sos_alerts` for `type === 'sos'` else `general`, deletes tokens FCM reports as invalid, never throws (logs).
  In tests every push is appended to the exported `sentPushes` array. Push sending is fire-and-forget (`void sendToMembers(...)`)
  so API latency doesn't depend on FCM.
- `services/cloudinary.js`: `isCloudinaryConfigured()`, `signUpload({ familyId, folder })` → `{ cloudName, apiKey, timestamp, signature, folder }`.
- `lib/access.js`: `findInFamily(Model, id, familyId, { lean })` → doc or throw `NOT_FOUND`; `isAdmin(req)`; `assertAdmin(req)`; `assertSelfOrAdmin(req, memberId)`.
- `lib/pagination.js`: `paginate(Model, filter, { page, limit, sort, projection })` → `{ items, page, limit, total }`.
- `lib/dates.js`: `monthRange(month /*YYYY-MM*/, timeZone)` → `{ start, end }`, `currentMonth(timeZone)`, `startOfDay(date, timeZone)`, `startOfWeek(date, timeZone)` (Monday), `ageFrom(dob, now)`.
- `lib/money.js`: `toMinor(amount)`, `fromMinor(minor)`.
- `lib/i18n.js`: `t(locale, key, vars)` (`{name}` placeholders), `pickLocale(acceptLanguage)`, `SUPPORTED_LOCALES`.
- `lib/mongoosePlugins.js`: `toJsonPlugin` — adds `id`, removes `_id`, `__v`; applied globally in `models/index.js`.

## 4. Models (collections)

| Model | Key fields | Indexes |
|---|---|---|
| `User` | email (lowercase, unique), passwordHash, name, locale, emailVerified, familyId, memberId, failedLoginCount, lockUntil, lastLoginAt, consentAcceptedAt | email unique |
| `RefreshToken` | userId, tokenHash (unique), expiresAt, revokedAt, replacedByHash, ip, userAgent | TTL on expiresAt, userId |
| `Otp` | email, purpose (`verify_email`/`reset_password`), codeHash, expiresAt, attempts, lastSentAt, userId | {email,purpose} unique, TTL |
| `Family` | name, inviteCode (unique), country, currency, timezone, ownerId | inviteCode unique |
| `Member` | familyId, userId, name, email, phone, avatarUrl, dateOfBirth, gender, designation, role, locationSharing (default `never`), lastLocation {lat,lng,accuracy,recordedAt}, guardianConsent, guardianConsentAt, guardianConsentById | familyId; {familyId,email} unique partial (email string); userId unique partial |
| `Device` | userId, token (unique), platform, locale, lastSeenAt | token unique, userId |
| `Task` | familyId, title, description, assigneeId, createdById, dueDate, category, priority, status, completedAt, completedById | {familyId,status,dueDate}, {familyId,assigneeId,status} |
| `LedgerEntry` | familyId, type, amountMinor, category, note, date, memberId, memberName, createdById, goalId | {familyId,date:-1}, {familyId,memberId,date:-1}, goalId |
| `Goal` | familyId, title, description, targetMinor, savedMinor, targetDate, status, createdById, achievedAt | {familyId,status} |
| `Notice` | familyId, title, body, imageUrl, pinned, authorId | {familyId,pinned:-1,createdAt:-1} |
| `SosAlert` | familyId, memberId, status, message, locationShared, lastLocation, trail[] (≤100 via `$push` + `$slice: -100`), lastLocationAt, startedAt, expiresAt, resolvedAt, resolvedById, resolution | {familyId,status}, {memberId,status} |
| `EmergencyCard` | familyId, memberId (unique), bloodGroup, allergiesEnc, medicationsEnc, conditionsEnc, doctorName, doctorPhone, insuranceProvider, insurancePolicyNumberEnc, emergencyContacts[{name,phone,relation}], notesEnc, updatedById | memberId unique |

## 5. i18n

Supported locales: `en hi bn ta te mr gu kn ml pa ar es fr pt de`. English files are the source; translation agents
create the same file set per language. Missing key in a language → English → the key itself.
Namespaces: `common.json` (errors.*, email layout), `auth.json`, `family.json`, `tasks.json`, `ledger.json`,
`notices.json`, `sos.json`. Push keys: `<ns>.push.<event>.title|body`; email keys: `<ns>.email.<name>.subject|text`.

## 6. Tests

`npm test` runs `node --test tests/`. `tests/helpers.js` exports `setupTestApp()` (starts `MongoMemoryServer` once per
file, connects mongoose, returns `{ app, request }`), `teardownTestApp()`, `resetDb()`, `registerFamilyAdmin(overrides)` →
`{ user, member, family, tokens, auth: { Authorization } }`, `joinFamilyAs(inviteCode, overrides)`, `addManagedMember(adminAuth, body)`,
`outbox` (emails) and `sentPushes`. Each module has `tests/<module>.test.js` covering happy paths, permissions (admin vs
member vs other family), validation errors, and the edge cases listed in the contract.
