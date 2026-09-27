# f-core: Flutter core / networking (progress)

Owner: f-core · Scope: docs/05-FLUTTER_GUIDE.md §5 (Fmt, Validators, UrlActions, DateX) and §7 (networking, errors, mock backend)
· App: `family_hub_app/`

## Built

### Networking (`lib/core/network/`)
- [x] `api_client.dart`: `ApiClient` get/post/patch/put/delete return the unwrapped `data`; `getPaged<T>(path, fromJson, {query, page, limit})`
      reads `meta`, skips non-object items and clamps page ≥ 1 and limit 1..100. Only throws `ApiException`. Null query values and
      empty strings are dropped, `DateTime` values are sent as UTC ISO, and enums as snake_case wire names (`ApiClient.wireName`). Exports `api_exception.dart` and `paged.dart`.
- [x] `api_exception.dart`: `ApiException {code, message, statusCode, details}` with `isNetwork`, `isUnauthorized` (UNAUTHORIZED/TOKEN_EXPIRED/
      INVALID_REFRESH_TOKEN/SESSION_EXPIRED, **not** INVALID_CREDENTIALS), `isForbidden/isNotFound/isValidation/isCancelled/isServer`,
      `retryAfterSeconds`, `fieldErrors`. Factories: `from(Object)`, `fromDio`, `fromResponse` (envelope, else by status) and `codeOf`.
      `ApiErrorCode` covers every contract code plus the client codes `NETWORK_ERROR TIMEOUT UNKNOWN CANCELLED SESSION_EXPIRED`
      and the backend extras `CONFLICT PAYLOAD_TOO_LARGE SERVICE_UNAVAILABLE`.
- [x] `paged.dart`: `Paged<T>` with `empty()`, `append(next, {identity})` (optional de-dupe), `map`, `copyWith`, `nextPage` and ==.
- [x] `auth_events.dart`: `AuthEvents { Stream<void> sessionExpired; emitSessionExpired(); dispose() }`, re-exported from core_providers.
- [x] `locale_interceptor.dart`: `Accept-Language: <languageCode>` is read on every request. It falls back to the platform locale and respects per-request overrides.
- [x] `auth_interceptor.dart`: adds the bearer token only when the request goes to the API host, never to third-party absolute URLs.
      On 401 `TOKEN_EXPIRED` (or `UNAUTHORIZED` for a request that sent a token) it does a **single-flight** `POST /auth/refresh` through a bare Dio,
      saves the rotated tokens and **retries once**. New requests wait while a refresh is in flight.
      Refresh rejected (4xx) → tokens cleared, `emitSessionExpired()`, and the error carries `SESSION_EXPIRED`. Transient refresh failures
      (offline, timeout, 5xx, 408/429) keep the session and report that error. `extra['skipAuth']=true` opts a request out.
- [x] `dio_factory.dart`: `createDio(...)`. Interceptor order is reachability → locale → auth → debug log (kDebugMode; method, path, status and ms,
      **no bodies or headers**) → mock. The refresh Dio gets locale + mock only. Also `ReachabilityInterceptor` and `DebugLogInterceptor`.
- [x] Mock backend (`mock/`):
  - `mock_backend.dart`: `MockBackend.on(method, '/x/:id', handler)` and `handle(RequestOptions)`. Params are URL-decoded. Routes with more literal segments
    win (`/sos/active` beats `/sos/:id` whatever the registration order). An unknown path or method throws `404 NOT_FOUND`. The body is JSON round-tripped (malformed → 400).
    `MockRequest`: method, path, pathParams, query (strings), body, headers, db, `accessToken`, `userId`, `param()`, `q()`, `page`/`limit`
    (invalid → 422), `requireUser()` (401 UNAUTHORIZED when the header is missing, malformed or the user is unknown), `requireMember()` (403 NO_FAMILY),
    `requireAdmin()` (403 FORBIDDEN), `requireFamily()`, `isAdmin`, `familyId`, `memberId`, `familyDocs(col)`, `findInFamily(col, id)`
    (another family's document → 404), plus token helpers `accessTokenFor`, `refreshTokenFor` and `userIdFromRefreshToken`.
    `MockResponse.ok/created/paged(items, req)`. `MockException` with `.badRequest .unauthorized([code]) .forbidden .noFamily .notFound
    .conflict(code) .validation(details) .tooManyRequests(seconds)`.
  - `mock_db.dart`: `MockDb`: `collections`, collection-name constants, `newId()` (24-hex, ObjectId layout), `nowIso()` (ms + Z),
    `iso()`, `parse()`, `randomHex()`, `seedOnce()`, `col()` / `where()` / `findById()` / `findOne()` return **deep copies**,
    `insert` (auto id plus createdAt/updatedAt), `update` (merge, bumps updatedAt, id immutable), `updateWhere`, `replace`, `remove`, `removeWhere`,
    `count`, `exists`, `reset()`.
  - `mock_seed.dart`: `MockSeed` with stable ids and the core seed: Sharma Family (IN / INR / Asia/Kolkata / `DEMO2345`), users
    `demo@familyhub.app` / `demo1234` (Amit, verified) and `priya@familyhub.app` / `demo1234` (Priya, verified), and members Amit (admin, Head of
    Family, 1985, sharing `always` with a location), Priya (admin, Finance Head, 1987, `sos_only`), Aarav (member, 2010, pre-added with
    `aarav@familyhub.app`, no account yet, so joining with that email links him), Anaya (2016, no account) and Kamla (1952, Advisor, no account).
    `MockSeed.otp = '123456'`.
  - `mock_serializers.dart`: `MockSerializers.user/family(isAdmin)/member/members(sorted like the API)/compareMembers/memberName/session`.
    It applies the contract privacy rules (no password, inviteCode only for admins, lastLocation only for `always`).
  - `mock_tokens.dart`: `MockTokens.issue/rotate/revoke/revokeAll`, which follow the server (rotation, reuse detection revoking every token, 30-day validity).
  - `mock_interceptor.dart`: wraps results in the envelope, adds 250–600 ms latency (configurable), turns `MockException` into the error envelope with its status,
    turns handler crashes into 500 INTERNAL_ERROR (logged), JSON round-trips responses, honours cancellation and passes non-mock hosts through.
  - `mock_registry.dart`: `registerAllMocks(b)` calls `registerCoreMocks` (GET /health) plus the ten feature `register*Mocks`.

### Storage (`lib/core/storage/`)
- [x] `auth_tokens.dart`: `AuthTokens {accessToken, refreshToken, expiresIn}` with `tryParse`, `fromJson`, `toJson`, `copyWith`, ==, and a toString that hides the secrets.
      (f-domain re-exports it from `shared/models/auth_tokens.dart`.)
- [x] `token_storage.dart`: `TokenStorage` on flutter_secure_storage (iOS/macOS `first_unlock_this_device`, so background SOS can still read tokens while the phone is locked)
      with an in-memory cache. Concurrent first reads share one load. A corrupt payload or keystore failure means signed out and never crashes. `cached`,
      `read`, `accessToken`, `refreshToken`, `hasTokens`, `save`, `clear`.
- [x] `local_cache.dart`: `LocalCache` on SharedPreferences (`cache.<key>` → `{t, v}`). `write` / `readJson({maxAge})` / `read(key, decode)`
      (drops an entry that fails to decode) / `readMap` / `savedAt` / `contains` / `remove` / `clear` (only `cache.*` keys; settings are kept).

### Providers (`lib/core/providers/core_providers.dart`)
- [x] `sharedPreferencesProvider` (throws unless overridden), `tokenStorageProvider`, `localCacheProvider`, `authEventsProvider`,
      `mockBackendProvider` (null when a real API is used), `dioProvider` (reads `resolvedLocaleProvider` lazily per request),
      `apiClientProvider`, and **`connectivityStatusProvider`** (`ConnectivityStatus.online|offline`, `.isOffline`) for `OfflineBanner`.

### Utilities (`lib/core/utils/`)
- [x] `fmt.dart` + `formatters.dart`: the `Fmt` class lives in `fmt.dart` (no Riverpod deps, so it's testable). `formatters.dart` re-exports it and
      defines `fmtProvider` (resolvedLocale + family currency/country, falling back to the country currency).
      The intl locale is `<lang>_<COUNTRY>` when it exists, else `<lang>`, else `en` (numbers and dates are resolved separately). API: `money({signed})`
      (true minus `−`, fraction digits only when needed, rounded to 2 dp), `compactMoney`, `currencySymbol`, `number`, `percent`, `date`,
      `shortDate`, `dateTime`, `time`, `monthYear`, `weekdayDate` (adds the year when it isn't the current one), `relative(d, l10n, {now})` (`common*` keys,
      covering future dates too). Every DateTime is converted with `.toLocal()`.
- [x] `validators.dart`: `Validators.required/email({optional})/password/confirmPassword(l10n, ctrl)/minLength(l10n, n)/maxLength(l10n, n)/
      amount({optional})/phone({isRequired})/otp/inviteCode/compose`. Helpers: `parseAmount(text, {decimalSeparator})`,
      `amountValue(l10n, text)`, `decimalSeparatorFor(localeName)`, `normalizeDigits` (Arabic-Indic, Persian, Devanagari, Bengali,
      Gurmukhi, Gujarati, Tamil, Telugu, Kannada, Malayalam, full-width), `normalizePhone`, `normalizeOtp`, `normalizeInviteCode`.
      Amount parsing is locale-aware and validates grouping (including lakh style), so `1.234` means 1.234 in `en` (rejected: 3 decimals) and 1234 in `de`.
- [x] `url_actions.dart`: `UrlActions.call/openMap/openUrl/email` return false instead of throwing. Builders `telUri`, `mapUri` (Google Maps
      search URL), `webUri` (http/https/mailto/tel only; `javascript:` is rejected). `launcherOverride` is available for tests.
- [x] `date_x.dart`: `startOfDay`, `endOfDay`, `isSameDay`, `isToday`, `isBeforeToday`, `monthKey`, `startOfMonth`, `addMonths` (clamps the day),
      `toApiDate()` (local midnight → UTC ISO), `parseMonthKey`, `ageFrom(dob, {now})`.

### Errors and l10n
- [x] `lib/core/l10n/error_messages.dart`: `localizedErrorMessage(error, l10n)` maps every code to `error*`, plus the upload codes
      (`UPLOAD_FAILED`, `FILE_TOO_LARGE`, `UPLOAD_CANCELLED`) to `servicesError*`. Unknown codes fall back to the server message, then the status, then `errorUnknown`.
- [x] `l10n_parts/errors.arb` (23 keys; `errorTooManyRequests` is an ICU plural on `seconds`, where 0 means "wait a moment") and `l10n_parts/validation.arb`
      (13 keys; `validationMinLength`/`MaxLength` are plurals). Every key has an `@` description. Both are already merged into `lib/l10n/app_en.arb`.
- [x] `lib/core/config/timezones.dart`: `Timezones.forCountry`, `defaultFor`, `all` (sorted, unique, includes UTC), `byCountry`, `isKnown`,
      `normalizeFor(country, current)`, `cityName`. Covers every country in `countries.dart` and falls back to `UTC` for unknown ones.

### Tests (`test/core/network/`, `test/core/utils/`): 98 tests, all passing
- [x] `mock_backend_test.dart`: route matching, params, 404 for an unknown path or method, specificity, body and query parsing, auth helpers, family scoping,
      paging, MockDb copy semantics, seed contents, serializers and MockTokens.
- [x] `api_client_test.dart`: the full stack through Dio and the mock. Covers the envelope, error mapping, paging, Accept-Language, single-flight refresh with 3 concurrent
      requests, retry once, rejected refresh → session expired (emitted once), transient refresh failure keeps the session,
      INVALID_CREDENTIALS doesn't trigger a refresh, and no token is sent to other hosts.
- [x] `storage_test.dart`: AuthTokens, TokenStorage, LocalCache.
- [x] `validators_test.dart`, `date_x_test.dart`, `fmt_test.dart`, `timezones_test.dart`, `url_actions_test.dart`.

## Pending / known issues
- [ ] `mock_registry.dart` and `core_providers.dart` (so **everything that imports core_providers**) won't compile until all nine
      `lib/features/<f>/data/<f>_mock_handlers.dart` files exist with the exact function names below. I checked this in a scratch copy
      with stub handlers: all 100 tests passed (including a provider wiring test for `/health` and `fmtProvider`) and `dart analyze` on the core folders was clean.
- [ ] The mock DB is in memory only. Accounts registered in mock mode disappear on restart; their stored token then gets 401, the refresh fails,
      and the app signs out cleanly. Seed users survive restarts because their ids are stable.
- [ ] The mock never produces `TOKEN_EXPIRED` by itself (mock access tokens don't expire), so the refresh path is covered by unit tests.
- [ ] Decision: `Validators.inviteCode` accepts any 8 letters/digits instead of only the invite alphabet, because the guide's seed code `DEMO2345`
      contains an `O`, which the alphabet excludes. The server stays the authority (`INVALID_INVITE_CODE`).
- [ ] Decision: `AuthInterceptor` also refreshes on 401 `UNAUTHORIZED` when a token was sent (e.g. after JWT secret rotation), not only on `TOKEN_EXPIRED`.
