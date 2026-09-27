# b-core — Backend core (progress)

Owner: b-core · Scope: docs/06-BACKEND_GUIDE.md §1–3, §5, §6 · Backend: `family_hub_backend/`

## Built

### App / process
- [x] `src/app.js` — `createApp()`: helmet, CORS (`CORS_ORIGINS`, `*` → any origin, no credentials), compression,
      morgan (not in test; device tokens redacted from access logs), locale middleware, global limiter,
      `express.json({ limit: "100kb" })`, `/api/v1` router, 404 handler, error handler. Also exports `API_PREFIX`, `redactUrl`.
- [x] `src/server.js` — `startServer({ port, mongoUri, onShutdown })`: connectDb → initPush → listen; graceful shutdown on
      SIGINT/SIGTERM (close server, flush pushes, close SMTP, disconnect DB, 10 s forced exit); auto-runs only when executed directly.
- [x] `src/routes/index.js` — `GET /health` (`{ status, db, version }` in the envelope, always 200) + all module mounts in the
      guide order (emergency-card router before the family router).
- [x] Placeholder routers (`export default Router()`) for every module in the guide table — module owners replace them.

### config / lib
- [x] `config/env.js` — adds `TRUST_PROXY`, `RATE_LIMIT_IN_TEST`, `env.version`, `env.trustProxy`, `env.isDev`; `.env` not loaded in
      test mode; `node --test` without NODE_ENV is detected as test; validates `FIELD_ENCRYPTION_KEY` length; rejects example JWT secret in prod.
- [x] `config/db.js` — idempotent `connectDb`, `disconnectDb`, `isDbUp` + connection event logging.
- [x] `lib/ApiError.js` — default `messageKey` is now `common.errors.<CODE>`; helpers `tokenExpired`, `invalidCredentials`,
      `invalidRefreshToken`, `noFamily`, `internal`, `serviceUnavailable`; `conflict(code = 'CONFLICT')`; new codes
      `CONFLICT`, `PAYLOAD_TOO_LARGE`, `SERVICE_UNAVAILABLE`.
- [x] `lib/validate.js` — invalid **params** → `400 BAD_REQUEST` (contract: invalid id format), query/body → `422`; `req.valid` merges
      across several `validate()`; new blocks `locale`, `countryCode`, `currencyCode`, `timeZone`, `nullableEmail`,
      `nullableObjectId`, `paginationQuery`, `zodIssuesToDetails`. Password letter check is Unicode-aware.
- [x] `lib/logger.js` — `LOG_LEVEL` support (silent in tests unless `DEBUG_TESTS=1`).
- [x] `lib/i18n.js` — loads every `src/i18n/locales/<lang>/*.json` at startup (namespace = file name); `t`, `tOr`,
      `hasTranslation`, `pickLocale` (q-values), `normalizeLocale`, `isSupportedLocale`, `SUPPORTED_LOCALES`, `loadTranslations`, `loadErrors`.
      A broken JSON file is skipped + logged (English fallback) instead of crashing the API.
- [x] `lib/constants.js` — re-exports `src/models/enums.js` (single source for persisted enums) + API constants
      (pagination, OTP/login rules, rate limits, push types/channels/routes, upload folders, dashboard limits, defaults).
- [x] `lib/countries.js` — mirrors `countries.dart` (28 countries): `COUNTRIES`, `COUNTRY_CODES`, `CURRENCIES`, `isCountry`,
      `isCurrency`, `getCountry`, `consentAge` (unknown → 18, strictest), `emergencyNumber`, `currencyOf`.
- [x] `lib/money.js` — `toMinor` (decimal-correct rounding: 1.005 → 101), `fromMinor`, `roundMoney`, `sumMinor`, `isValidAmount`.
- [x] `lib/dates.js` — Intl-only TZ math, DST-safe, half-open ranges: `monthRange`, `currentMonth`, `startOfDay`, `startOfNextDay`,
      `startOfWeek` (Monday), `dayRange`, `weekRange`, `ageFrom(dob, now, timeZone?)`, `zonedParts`, `zonedTimeToUtc`,
      `isValidTimeZone`, `toIso`, `addDays`, `addMs`.
- [x] `lib/pagination.js` — `paginate` (hydrated docs by default, `lean: true` optional), `paginateAggregate` ($facet, for
      "nulls last" sorts), `paginateArray`, `normalizePage`.
- [x] `lib/access.js` — `findInFamily` (other family / bad id → 404), `familyFilter`, `isAdmin`, `isSelf`, `assertFamily`,
      `assertAdmin`, `assertSelfOrAdmin`, `toId`, `sameId`, `isObjectId`.
- [x] `lib/mongoosePlugins.js` — `toJsonPlugin` (composes with per-schema transforms, idempotent).

### middleware
- [x] `auth.js` — `requireAuth` (Bearer JWT; `TOKEN_EXPIRED` vs `UNAUTHORIZED`; `req.user` exact shape; `req.member`; stale
      member row → treated as no family; falls back to the user's locale when no Accept-Language), `requireFamily`,
      `requireAdmin`, plus `familyMember` / `familyAdmin` chains.
- [x] `error.js` — `notFoundHandler`, `errorHandler`, `toApiError`, `localizeError`. ApiError / ZodError(422) / CastError(400) /
      mongoose ValidationError(422) / E11000 → 409 (`users.email` → EMAIL_TAKEN, `members.email` → MEMBER_EMAIL_EXISTS,
      `members.userId` → ALREADY_IN_FAMILY, else CONFLICT; values never leaked) / malformed JSON 400 / body too large 413 /
      other → 500 INTERNAL_ERROR (stack logged, never returned). Sets `Retry-After` on 429.
- [x] `locale.js` — `localeMiddleware` (`req.locale`, `Content-Language`, `Vary`), `setRequestLocale`.
- [x] `rateLimit.js` — `globalLimiter` (300/min/IP, health exempt), `authLimiter` (20/min/IP), `createRateLimiter` factory;
      skipped in test unless `RATE_LIMIT_IN_TEST=true`; 429 uses the standard envelope with `details.retryAfterSeconds`.

### services
- [x] `tokens.js` — HS256 JWT with iss/aud + pinned algorithm; `signAccessToken`, `verifyAccessToken`, `issueTokens`,
      `rotateRefreshToken` (atomic claim; reuse or lost race → revoke all + 401), `revokeRefreshToken(raw, { userId })`,
      `revokeAllUserTokens`.
- [x] `serializers.js` — `serializeUser(user, memberOrRole)`, `serializeFamily`, `serializeMember`, `serializeMembers`
      (contract order: admins, oldest → youngest, null DOB last), `sortMembers`, `serializeLocation`, `idOf`, `iso`.
- [x] `memberDirectory.js` — `getMemberMap`, `nameOf`, `memberOf`, `avatarOf`, `countMembers`, `countAdmins`.
- [x] `mailer.js` — nodemailer 10 SMTP pool / dev console / prod warning / test `outbox` (pushed synchronously);
      `sendMail`, `sendTemplate`, `renderTemplate` (greeting/signature/footer layout, RTL html for `ar`), `closeMailer`. Never throws.
- [x] `push.js` — firebase-admin v14 modular API; creds from BASE64 or PATH; per-device locale; channel `sos_alerts` / `general`;
      android priority high + channelId; apns-priority 10 for sos/high (5 otherwise), SOS TTL 15 min; batches of 500;
      invalid tokens deleted; never throws; test `sentPushes` + `flushPushes()`.
- [x] `cloudinary.js` — `isCloudinaryConfigured`, `signUpload` (→ `familyhub/<familyId>/<folder>`; 503 when not configured,
      fake creds in tests), `familyFolder`, `isCloudinaryUrl`, `isFamilyAssetUrl`.

### i18n / scripts / tests / config files
- [x] `src/i18n/locales/en/common.json` — one message per error code + `email.greeting|signature|footer`.
- [x] `scripts/check-syntax.js` — `node --check` on all .js in src/ scripts/ tests/ (parallel) + JSON parse of src/i18n.
- [x] `scripts/dev-memory.js` — MongoMemoryServer → `MONGODB_URI` → optional `scripts/seed.js` (dynamic import; calls exported
      `seed`/`default` if any; contains `process.exit`) → `startServer`; stops MongoDB on shutdown.
- [x] `tests/helpers.js` — `setupTestApp`, `teardownTestApp`, `resetDb`, `registerFamilyAdmin`, `joinFamilyAs`, `addManagedMember`,
      `outbox`, `sentPushes`, `flushPushes`, `authHeader`, `uniqueEmail`, `lastMailTo`, `lastOtpFor`, `API`, `DEFAULT_PASSWORD`.
- [x] `tests/health.test.js` — 53 tests: health/404/CORS/413/400/locale, error mapping, core helpers, tokens rotation & reuse,
      requireAuth/requireFamily/requireAdmin, push fan-out, mailer, serializers privacy, pagination/scoping, cloudinary,
      guide §3 export contract, common.json completeness.
- [x] `package.json` scripts — `dev:memory`; `test` now uses a quoted glob (`"tests/**/*.test.js"`) because Node ≥ 21 treats
      `tests/` as a module path (the old script failed on Node 25).
- [x] `.env.example` — documented all variables incl. `TRUST_PROXY`, `LOG_LEVEL`, `RATE_LIMIT_IN_TEST`, `DEV_MEMORY_DB_PORT`.

## Pending / not in scope
- [ ] Translations of `common.json` for the other 14 locales (translation agents).
- [ ] Module routers are placeholders until module agents replace them.
- [ ] `scripts/seed.js` (owned by another agent) — see handoff about exporting `seed()`.

## Known issues / decisions
- Rate limiting uses the in-memory store (single instance). Multi-instance deployments need a shared store (e.g. Redis).
- Refresh-token rotation is strict per contract: two parallel refreshes with the same token → the loser triggers "reuse"
  and all sessions are revoked. The app must single-flight its refresh call.
- Money uses a fixed 2-decimal minor unit for every currency (contract), including zero-decimal currencies.
- `GET /health` always returns 200 (liveness); use `data.db` for readiness.
- `validate()` returns 400 BAD_REQUEST for invalid path params (contract: "invalid id format"), 422 for query/body.
- Extra error codes not yet in the contract: `CONFLICT` (409), `PAYLOAD_TOO_LARGE` (413), `SERVICE_UNAVAILABLE` (503).
