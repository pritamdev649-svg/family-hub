# 03 · API Contract (single source of truth)

The Flutter app (`family_hub_app`) and the Node.js backend (`family_hub_backend`) **both** implement
this document. The Flutter in-memory mock backend (`lib/core/network/mock/`) implements it too.
If code and this document disagree, fix the code — or update this document first and then both sides.

- Base URL: `{API_BASE_URL}` = `http(s)://host/api/v1`
- Content type: `application/json; charset=utf-8`
- Auth: `Authorization: Bearer <accessToken>` on every endpoint marked 🔒
- Language: the app sends `Accept-Language: <code>` (e.g. `hi`, `ta`, `ar`, `es`). The backend uses it for
  error `message` text. Push notifications & emails use the **recipient's** stored `locale`.
- Time: all timestamps are ISO-8601 UTC strings (`2026-09-26T10:15:00.000Z`). Date-only fields
  (`dueDate`, ledger `date`, `dateOfBirth`, `targetDate`) are also sent as ISO strings; the app sends
  local midnight converted to UTC and displays in local time.
- IDs: MongoDB ObjectId hex strings, always exposed as `id` (never `_id`, never `__v`).
- Money: decimal numbers in major units (`1250.5` = ₹1,250.50) rounded to 2 decimals. The backend stores
  integer minor units internally. Currency is a family setting (`family.currency`, ISO-4217).

## 1. Envelope

Success:
```json
{ "success": true, "data": <payload>, "meta": { "page": 1, "limit": 20, "total": 57, "hasMore": true } }
```
`meta` is present only on paginated list endpoints.

Error:
```json
{ "success": false, "error": { "code": "VALIDATION_ERROR", "message": "Human readable (localized)", "details": { "email": "Invalid email" } } }
```
`details` is optional; for `VALIDATION_ERROR` it maps field path → message.

### Pagination
Query `?page=1&limit=20` (page ≥ 1, 1 ≤ limit ≤ 100, default 20). Response `data` is an array and `meta` is set.

### Error codes

| HTTP | code | When |
|---|---|---|
| 400 | `BAD_REQUEST` | Malformed JSON / invalid id format |
| 400 | `INVALID_OTP` | Wrong OTP |
| 400 | `OTP_EXPIRED` | OTP expired or too many attempts (must request a new one) |
| 400 | `INVALID_INVITE_CODE` | Invite code unknown |
| 401 | `UNAUTHORIZED` | Missing/invalid token |
| 401 | `TOKEN_EXPIRED` | Access token expired → client must call `/auth/refresh` |
| 401 | `INVALID_CREDENTIALS` | Wrong email/password (never reveal which) |
| 401 | `INVALID_REFRESH_TOKEN` | Refresh token unknown/revoked/expired → client logs out |
| 403 | `FORBIDDEN` | Authenticated but not allowed (e.g. non-admin) |
| 403 | `NO_FAMILY` | User has no family (removed or not yet joined) → app shows create/join |
| 403 | `LOCATION_SHARING_DISABLED` | Location update while member's sharing mode forbids it |
| 404 | `NOT_FOUND` | Resource missing **or belongs to another family** (never leak existence) |
| 409 | `EMAIL_TAKEN` | Register with existing email |
| 409 | `ALREADY_IN_FAMILY` | Join/create family while already in one |
| 409 | `MEMBER_EMAIL_EXISTS` | Adding a member whose email already exists in the family |
| 409 | `LAST_ADMIN` | Would leave the family with zero admins (demote/delete/leave) |
| 409 | `SOS_NOT_ACTIVE` | Location/resolve on an SOS that is resolved/expired |
| 422 | `VALIDATION_ERROR` | Body/query validation failed |
| 422 | `GUARDIAN_CONSENT_REQUIRED` | Adding a member younger than the country consent age without `guardianConsent: true` |
| 429 | `TOO_MANY_REQUESTS` | Rate limit / login lockout / OTP resend cooldown. `details.retryAfterSeconds` |
| 500 | `INTERNAL_ERROR` | Anything unexpected (message is generic, never a stack trace) |

## 2. Shared objects

### User (account)
```json
{ "id": "…", "email": "amit@example.com", "name": "Amit Sharma", "emailVerified": true,
  "locale": "hi", "familyId": "…|null", "memberId": "…|null", "role": "admin|member|null",
  "createdAt": "…" }
```

### Tokens
```json
{ "accessToken": "jwt…", "refreshToken": "opaque…", "expiresIn": 900 }
```
Access token = JWT (HS256, 15 min, claims `sub`=userId). Refresh token = random 48-byte base64url string,
stored **hashed** (sha256) server-side, valid 30 days, **rotated** on every refresh (old one revoked). Reusing a
revoked refresh token revokes all of that user's refresh tokens.

### Family
```json
{ "id": "…", "name": "Sharma Family", "inviteCode": "K7Q2M9XD", "country": "IN", "currency": "INR",
  "timezone": "Asia/Kolkata", "ownerId": "<userId>", "memberCount": 5, "createdAt": "…" }
```
`inviteCode`: 8 chars from `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` (no 0/O/1/I). Matching is case-insensitive.
`inviteCode` is only returned to admins (members get `null`).

### Member
```json
{ "id": "…", "familyId": "…", "userId": "…|null", "name": "Aarav", "email": "…|null", "phone": "+919…|null",
  "avatarUrl": "https://res.cloudinary.com/…|null", "dateOfBirth": "2010-05-14T00:00:00.000Z|null",
  "gender": "male|female|other|null", "designation": "Chief Study Officer|null",
  "role": "admin|member", "hasAccount": true, "locationSharing": "never|sos_only|always",
  "lastLocation": { "lat": 28.61, "lng": 77.2, "accuracy": 12.5, "recordedAt": "…" } ,
  "guardianConsent": true, "createdAt": "…", "updatedAt": "…" }
```
- `lastLocation` is only returned when that member's `locationSharing` is `always` (otherwise `null`).
- `locationSharing` default is `never` (privacy by default).
- `designation` is free text — the "company title" (e.g. *Head of Family*, *Finance Head*).
- Age / age group are computed client-side from `dateOfBirth`.

## 3. Health
`GET /health` → `{ "status": "ok", "db": "up|down", "version": "1.0.0" }` (no envelope requirement; wrap in envelope anyway).

## 4. Auth (`/auth`)

| Method | Path | Auth | Body | Response `data` |
|---|---|---|---|---|
| POST | `/auth/register` | – | see below | `201 { user, tokens, family, member }` |
| POST | `/auth/login` | – | `{ email, password }` | `{ user, tokens }` |
| POST | `/auth/refresh` | – | `{ refreshToken }` | `{ tokens }` |
| POST | `/auth/logout` | 🔒 | `{ refreshToken, deviceToken? }` | `null` |
| POST | `/auth/verify-email` | 🔒 | `{ otp }` | `{ user }` |
| POST | `/auth/resend-verification` | 🔒 | – | `{ sent: true, retryAfterSeconds: 60 }` |
| POST | `/auth/forgot-password` | – | `{ email }` | `{ sent: true }` (always, even if email unknown) |
| POST | `/auth/reset-password` | – | `{ email, otp, newPassword }` | `{ reset: true }` |
| POST | `/auth/change-password` | 🔒 | `{ currentPassword, newPassword }` | `{ changed: true }` |
| GET | `/auth/me` | 🔒 | – | `{ user, member|null, family|null }` |

### Register body
```json
{
  "name": "Amit Sharma", "email": "amit@example.com", "password": "min 8 chars, ≥1 letter & ≥1 digit",
  "locale": "hi", "consentAccepted": true, "dateOfBirth": "1985-02-01T00:00:00.000Z",
  "mode": "create",
  "family": { "name": "Sharma Family", "country": "IN", "currency": "INR", "timezone": "Asia/Kolkata" },
  "inviteCode": null
}
```
- `mode: "create"` → requires `family`; creates Family + admin Member (designation "Head of Family" unless provided later).
- `mode: "join"` → requires `inviteCode`; creates a `member` role Member — **or links** to an existing
  member of that family with the same email and `hasAccount=false` (admin pre-added them).
- `consentAccepted` must be `true` (privacy policy + terms) → else `VALIDATION_ERROR`.
- Email is trimmed + lower-cased everywhere. Name 1–60 chars. Family name 1–60 chars.
- Sends a 6-digit email verification OTP (valid 10 min, max 5 attempts, resend cooldown 60 s).
- Unverified users **can** log in; the app forces the verify screen until `emailVerified=true`.

### Login
- 5 failed attempts for an email within 15 min → `429 TOO_MANY_REQUESTS` (`details.retryAfterSeconds`).
- Response user may have `familyId: null` (removed from family) → app shows create/join-family screen.

### Password reset
- `forgot-password` sends a 6-digit OTP (10 min). Unknown email → still `{ sent: true }` (no enumeration).
- `reset-password` success revokes **all** refresh tokens of that user.

## 5. Me (`/me`) 🔒

| Method | Path | Body | Response `data` |
|---|---|---|---|
| PATCH | `/me` | `{ name?, phone?, avatarUrl?, locale?, locationSharing?, gender?, dateOfBirth? }` | `{ user, member }` |
| PUT | `/me/location` | `{ lat, lng, accuracy? }` | `{ recordedAt }` — only when `locationSharing=always`, else `403 LOCATION_SHARING_DISABLED` |
| POST | `/me/devices` | `{ token, platform: "android"|"ios", locale? }` | `{ registered: true }` (upsert by token; a token moves to the latest user) |
| DELETE | `/me/devices/:token` | – | `null` |
| GET | `/me/export` | – | JSON dump of the caller's personal data (user, member, tasks, ledger entries they created/own, notices authored, emergency card, sos alerts) — DPDP/GDPR right of access |
| DELETE | `/me` | `{ password }` | `null` — deletes account + member + card + devices + tokens. If caller is the **last admin** and other members exist → `409 LAST_ADMIN`. If caller is the only member → whole family is deleted. |
| POST | `/me/leave-family` | – | `{ user }` — member leaves family (same LAST_ADMIN rule). |

Validation: `lat` −90..90, `lng` −180..180, `accuracy` ≥ 0. `locale` must be one of the supported language codes:
`en hi bn ta te mr gu kn ml pa ar es fr pt de`.

## 6. Family (`/family`) 🔒

| Method | Path | Who | Body | Response `data` |
|---|---|---|---|---|
| POST | `/family` | user **without** family | `{ name, country, currency, timezone }` | `201 { user, family, member }` (`409 ALREADY_IN_FAMILY`) |
| POST | `/family/join` | user **without** family | `{ inviteCode }` | `{ user, family, member }` |
| GET | `/family` | member | – | `{ family }` |
| PATCH | `/family` | admin | `{ name?, country?, currency?, timezone? }` | `{ family }` |
| POST | `/family/invite-code` | admin | – | `{ family }` (new code, old one stops working) |
| GET | `/family/members` | member | – | `Member[]` admins first, then oldest → youngest (null DOB last) |
| POST | `/family/members` | admin | see below | `201 Member` |
| GET | `/family/members/:id` | member | – | `Member` |
| PATCH | `/family/members/:id` | admin (any) / self (limited) | see below | `Member` |
| DELETE | `/family/members/:id` | admin | – | `null` |
| GET | `/family/members/:id/emergency-card` | member | – | `EmergencyCard` (empty card object when none saved, `updatedAt: null`) |
| PUT | `/family/members/:id/emergency-card` | self or admin | `EmergencyCard` fields | `EmergencyCard` |

Add member body:
```json
{ "name": "Anaya", "email": null, "phone": null, "dateOfBirth": "2016-08-01T00:00:00.000Z", "gender": "female",
  "designation": "Junior Explorer", "role": "member", "guardianConsent": true }
```
- If computed age < `consentAge(family.country)` → `guardianConsent` must be `true` else `422 GUARDIAN_CONSENT_REQUIRED`.
- If `email` given: must be unique among the family's members (`409 MEMBER_EMAIL_EXISTS`); backend emails an
  invitation with the family invite code (in the family creator's locale).
- Members without email are "managed profiles" (young kids / elders without phones): `hasAccount=false`.

PATCH member: admin may change everything incl. `role`; a non-admin may patch **only themselves** and only
`name, phone, avatarUrl, gender, dateOfBirth`. Demoting/deleting the last admin → `409 LAST_ADMIN`.
Deleting a member: unlinks its user (`familyId=null`, `memberId=null`, refresh tokens revoked, devices removed),
deletes its **pending** tasks, its emergency card, resolves its active SOS. Ledger entries remain (they keep `memberName`).

### EmergencyCard
```json
{ "memberId": "…", "bloodGroup": "A+|A-|B+|B-|AB+|AB-|O+|O-|unknown",
  "allergies": ["Peanuts"], "medications": ["Metformin 500mg"], "conditions": ["Asthma"],
  "doctorName": "Dr. Rao", "doctorPhone": "+91…", "insuranceProvider": "Star Health",
  "insurancePolicyNumber": "P-123", "emergencyContacts": [{ "name": "Ravi", "phone": "+91…", "relation": "Uncle" }],
  "notes": "…", "updatedAt": "…|null", "updatedById": "…|null" }
```
Limits: lists ≤ 20 items × 80 chars, `emergencyContacts` ≤ 5, `notes` ≤ 500. Backend encrypts `allergies`,
`medications`, `conditions`, `insurancePolicyNumber`, `notes` at rest (AES-256-GCM).

## 7. Tasks (`/tasks`) 🔒

`Task`:
```json
{ "id": "…", "title": "Finish maths homework", "description": "Ch. 4", "assigneeId": "…", "assigneeName": "Aarav",
  "createdById": "…", "createdByName": "Amit", "dueDate": "…|null", "category": "study|chore|skill|health|errand|other",
  "priority": "low|medium|high", "status": "pending|done", "completedAt": "…|null", "completedById": "…|null",
  "createdAt": "…", "updatedAt": "…" }
```
`*Id` fields are **member** ids.

| Method | Path | Who | Notes |
|---|---|---|---|
| GET | `/tasks?assigneeId=&status=pending|done|all&due=overdue|today|week&page&limit` | member | paginated. pending → `dueDate` asc (nulls last) then `createdAt`; done → `completedAt` desc; all → pending first |
| POST | `/tasks` | admin → any assignee; member → only self | `{ title(1–120), description?(≤1000), assigneeId, dueDate?, category, priority }` → `201 Task`. Push `task_assigned` to assignee if ≠ creator |
| GET | `/tasks/:id` | member | |
| PATCH | `/tasks/:id` | admin or creator | same fields as POST (all optional) |
| POST | `/tasks/:id/complete` | assignee or admin | idempotent; push `task_completed` to creator if ≠ completer |
| POST | `/tasks/:id/reopen` | assignee or admin | idempotent |
| DELETE | `/tasks/:id` | admin or creator | |

## 8. Ledger & goals 🔒

`LedgerEntry`:
```json
{ "id": "…", "type": "income|expense", "amount": 1250.5, "category": "groceries", "note": "Weekly veggies",
  "date": "…", "memberId": "…", "memberName": "Priya", "createdById": "…", "goalId": "…|null", "createdAt": "…" }
```
Categories — income: `salary business allowance gift interest other_income`; expense:
`groceries utilities rent education health transport dining shopping entertainment household_help savings other_expense`.
(`savings` entries are created by goal contributions.)

| Method | Path | Who | Notes |
|---|---|---|---|
| GET | `/ledger/entries?month=YYYY-MM&type=&memberId=&goalId=&page&limit` | member | admin sees all; member sees entries with `memberId=self` or `createdById=self`. Sorted `date` desc |
| POST | `/ledger/entries` | member | `{ type, amount(>0, ≤1e12), category(valid for type), note?(≤200), date(≤ today+1 day), memberId? }` member may only use `memberId=self`; admin any |
| PATCH | `/ledger/entries/:id` | admin or creator | cannot edit goal-linked entries' `amount` (`VALIDATION_ERROR`) — delete & re-add instead |
| DELETE | `/ledger/entries/:id` | admin or creator | if `goalId` → decrement goal `savedAmount` (not below 0) and reopen it if it drops below target |
| GET | `/ledger/summary?month=YYYY-MM` | member | `{ month, currency, scope: "family"|"personal", income, expense, net, byCategory: [{type, category, amount}] }` admin → family, member → personal |

`SavingsGoal`:
```json
{ "id": "…", "title": "Goa vacation", "description": "…", "targetAmount": 60000, "savedAmount": 12500,
  "targetDate": "…|null", "status": "active|achieved|archived", "progress": 0.2083, "createdById": "…", "createdAt": "…", "updatedAt": "…" }
```
| Method | Path | Who | Notes |
|---|---|---|---|
| GET | `/goals?status=active|achieved|archived|all` | member | default `all`, active first |
| POST | `/goals` | admin | `{ title(1–80), description?, targetAmount>0, targetDate? }` |
| PATCH | `/goals/:id` | admin | `{ title?, description?, targetAmount?, targetDate?, status? }` |
| DELETE | `/goals/:id` | admin | linked ledger entries keep existing but `goalId` → null |
| POST | `/goals/:id/contributions` | member | `{ amount>0, note?, date? }` → `{ goal, entry }`; creates `expense/savings` entry; if saved ≥ target → `achieved` + push `goal_achieved` to family. Contributions to `archived` goals → `409 CONFLICT`-style `VALIDATION_ERROR` |

## 9. Notices (`/notices`) 🔒

`Notice`: `{ id, title, body, imageUrl|null, pinned, authorId, authorName, authorAvatarUrl|null, createdAt, updatedAt }`

| Method | Path | Who | Notes |
|---|---|---|---|
| GET | `/notices?page&limit` | member | pinned first, then `createdAt` desc |
| POST | `/notices` | member | `{ title(1–100), body(1–2000), imageUrl?, pinned? }` — `pinned` ignored unless admin. Push `notice` to all other members |
| PATCH | `/notices/:id` | author or admin | `pinned` only by admin |
| DELETE | `/notices/:id` | author or admin | |

## 10. SOS (`/sos`) 🔒

`SosAlert`:
```json
{ "id": "…", "memberId": "…", "memberName": "Priya", "memberPhone": "+91…|null", "memberAvatarUrl": null,
  "status": "active|resolved|expired", "message": "…|null", "locationShared": true,
  "lastLocation": { "lat": 28.6, "lng": 77.2, "accuracy": 10, "recordedAt": "…" } ,
  "trail": [ { "lat": 0, "lng": 0, "accuracy": 0, "recordedAt": "…" } ],
  "startedAt": "…", "expiresAt": "…", "resolvedAt": "…|null", "resolvedById": "…|null",
  "resolution": "safe|false_alarm|helped|null" }
```
`trail` is included only by `GET /sos/:id` (max 100 newest points, oldest first); lists return `trail: []`.
Status is computed lazily: an `active` alert past `expiresAt` is persisted/returned as `expired`.

| Method | Path | Who | Notes |
|---|---|---|---|
| POST | `/sos` | member | `{ location?: {lat,lng,accuracy?}, message?(≤140) }`. If caller already has an active alert → returns it (200, idempotent). Else `201`. `expiresAt = startedAt + 15 min`. If caller's `locationSharing = never` the location is dropped and `locationShared=false`. Push **high priority** `sos` to all other members with devices |
| GET | `/sos/active` | member | active alerts of the family (includes caller's own) |
| GET | `/sos/history?page&limit` | member | resolved/expired, newest first |
| GET | `/sos/:id` | member | includes `trail` |
| POST | `/sos/:id/location` | alert owner | `{ lat, lng, accuracy? }` → `SosAlert`. `409 SOS_NOT_ACTIVE` if not active. Updates arriving < 3 s after the previous one are accepted but not stored (returns current alert). `403 LOCATION_SHARING_DISABLED` if mode is `never` |
| POST | `/sos/:id/resolve` | owner or admin | `{ resolution: "safe"|"false_alarm"|"helped" }` → `SosAlert`; idempotent on already resolved; push `sos_resolved` to others |

The SOS feature alerts **family members only** — it never contacts emergency services. The app always shows
the country emergency number (see `docs/07-I18N_AND_COUNTRIES.md`) next to the SOS button.

## 11. Dashboard 🔒
`GET /dashboard` →
```json
{ "family": Family, "me": Member,
  "members": [ { "member": Member, "pendingTasks": 3, "overdueTasks": 1, "completedThisWeek": 4 } ],
  "myTasks": [Task],            // caller's pending tasks, dueDate asc, max 5
  "goals": [SavingsGoal],       // active goals, max 3
  "latestNotices": [Notice],    // max 3, pinned first
  "activeSos": [SosAlert],
  "monthSummary": { same shape as /ledger/summary for current month in family timezone } }
```

## 12. Uploads (Cloudinary) 🔒
`POST /uploads/signature` `{ folder: "avatars"|"notices" }` →
```json
{ "cloudName": "demo", "apiKey": "1234", "timestamp": 1790000000, "signature": "sha1hex",
  "folder": "familyhub/<familyId>/avatars" }
```
The app then uploads directly: `POST https://api.cloudinary.com/v1_1/<cloudName>/image/upload` (multipart:
`file, api_key, timestamp, signature, folder`) and stores the returned `secure_url` (e.g. as `avatarUrl`).
The backend only accepts image URLs whose host is `res.cloudinary.com` for `avatarUrl` / `imageUrl`.

## 13. Push notifications (FCM data payload)
Every push carries a `notification` (localized title/body) **and** `data`:
```json
{ "type": "sos|sos_resolved|task_assigned|task_completed|notice|goal_achieved|member_joined",
  "id": "<resource id>", "route": "/sos/alert/<id>" }
```
Android channel: `sos_alerts` for `sos` (high priority, sound), `general` for everything else.
Routes used: `/sos/alert/:id`, `/tasks/:id`, `/notices`, `/money`, `/members/:id`.
Invalid/unregistered tokens returned by FCM are deleted from the `devices` collection.
