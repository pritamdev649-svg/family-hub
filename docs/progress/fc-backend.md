# fc-backend: backend foundation integration (progress)

Owner: fc-backend. Scope: make b-core (`lib/ config/ middleware/ services/ app server routes tests scripts`) and
b-models (`src/models/**`) consistent with each other, docs/06-BACKEND_GUIDE.md §3–§4 and docs/03-API_CONTRACT.md.

## Built / fixed
- [x] Syntax check is clean (`node scripts/check-syntax.js`: 59 JS files and 1 JSON file).
- [x] The export names in guide §3 are verified by a test. Models match guide §4: every field and index is checked by a
      test, including the indexes actually built in MongoDB.
- [x] **Single source for shared values (DRY):**
  - The invite code alphabet and length now live only in `models/enums.js`. `lib/crypto.js#randomInviteCode` uses them.
  - `models/schemaUtils.js#isValidTimeZone` re-exports `lib/dates.js#isValidTimeZone`. The duplicate is gone.
  - `models/schemaUtils.js#applyToJson` now applies `lib/mongoosePlugins.js#toJsonPlugin` for the id rules
    (`id` string, no `_id`/`__v`). The duplicate transform is gone. The plugin comment now says not to register it
    globally, and explains why.
  - `EMERGENCY_CARD_ENCRYPTED_FIELDS` (and the new `EMERGENCY_CARD_LIST_FIELDS`) moved to `models/enums.js`.
    `EmergencyCard.ENCRYPTED_CARD_FIELDS` and the `*Enc` schema paths are built from that list.
    `lib/constants.js` re-exports it.
  - `lib/money.js#MAX_AMOUNT` is derived from `MAX_AMOUNT_MINOR`.
  - `validate.js` limits and pagination come from `LIMITS` / `DEFAULT_PAGE_LIMIT` / `MAX_PAGE_LIMIT`.
  - `cloudinary.isCloudinaryUrl` equals `validate.isCloudinaryHostUrl`.
- [x] **Invite code `O` conflict (DEMO2345):** generated codes still use the strict alphabet (`INVITE_CODE_REGEX`).
      Stored codes and user input accept any 8 letters or digits (`INVITE_CODE_INPUT_REGEX`), so the documented demo seed
      code works. There is a new zod block `inviteCode`: case-insensitive, spaces and dashes are ignored.
- [x] **`validate.js` building blocks:**
  - The nullable blocks are now PATCH-safe. An absent key stays absent, and `null` or a blank value becomes `null`.
    Before, `optionalText`, `nullableIsoDate` and `nullableObjectId` turned an absent key into `null`, so a PATCH would
    have cleared fields the client didn't send.
  - New generic `nullableField(schema)`.
  - `isoDate` is now strict. It accepts calendar-checked `YYYY-MM-DD` or ISO date-times that include `Z` or an offset.
    V8 used to accept `2026-02-31`, and it read `2026-09-26 10:00` in the server's own time zone.
  - `latLng` no longer coerces values (`null` used to become latitude 0).
  - New blocks: `personName`, `nullableGender`, `moneyAmount`, `isIsoDateString`, `isCloudinaryHostUrl`.
- [x] `lib/crypto.js`: the GCM IV and tag lengths are now fixed, and malformed ciphertext throws a clear error.
- [x] `middleware/auth.js`: a token whose `sub` is not an ObjectId now returns 401 UNAUTHORIZED. Before, it caused a
      CastError that became a 400.
- [x] `tests/health.test.js` now covers only health and app wiring: the envelope, the version from package.json,
      no-store, security headers, CORS, 404, locale, JSON parsing, every mount point, and `db: down`. 9 tests.
- [x] New `tests/core.test.js` with 94 tests:
  - requireAuth: missing token, malformed headers, expired token → TOKEN_EXPIRED, forged token, alg=none, wrong
    audience or issuer, bad `sub`, deleted user; the shape of `req.user`; locale fallback; the family and admin chains.
  - Error middleware: malformed JSON → 400 envelope. With `Accept-Language: hi` the message falls back to English when
    there is no Hindi file (tested against fixture catalogs, so translation agents can add files later). Also: Hindi is
    used when present, messageKey handling, Zod/Mongoose → 422, CastError → 400, 500 without internals, and validate()
    (params → 400, query/body → 422, results merge).
  - Real E11000 errors from the models map to EMAIL_TAKEN, MEMBER_EMAIL_EXISTS and ALREADY_IN_FAMILY, and every other
    unique key maps to CONFLICT.
  - Crypto: round trip with Unicode, random IV, rejection of tampered or malformed data.
  - Money: 0.1+0.2 cases, rounding, range limits, `moneyAmount`.
  - `monthRange` in Asia/Kolkata, America/Los_Angeles (DST start and end months), Kathmandu, Sydney, London and a leap
    year; also that consecutive months connect without gaps in 8 zones; `currentMonth`; week and age helpers.
  - i18n `t()`: placeholders, fallback chain, broken files; also `pickLocale`.
  - The zod building blocks.
  - Tokens: rotation, reuse, expiry, races.
  - Push, mailer, serializers, pagination, access, cloudinary.
  - Models against guide §4 (fields, indexes, enums, toJSON, invite codes, emergency card encrypted at rest, SOS, goal,
    ledger, device and task rules).
  - The full export list in guide §3.
- [x] `scripts/dev-memory.js` checked: it starts in-memory MongoDB and the API, `/api/v1/health` returns 200 with
      `db: "up"`, and SIGTERM shuts down cleanly (exit 0, MongoDB stopped).

## Pending / not in scope
- [ ] `scripts/seed.js` does not exist yet (owned by the seed agent). dev-memory starts with an empty database until it
      exists. The seed agent should export `seed()`, call `initModels()`, and never exit on import.
- [ ] Module routers are still placeholders (module agents replace them).
- [ ] Translations of `common.json` for the other 14 locales (translation agents).

## Known issues / decisions
- Invite codes: decision recorded above. The docs (contract §2, 04-DATA_MODELS Family table) should say "generated
  from the alphabet; any 8 letters/digits accepted on input". This is a handoff.
- The nullable zod blocks no longer set absent fields to `null`. Create services rely on model defaults (null) or `?? null`.
- `serializeUser(user)` only returns a `role` when the member (or role) is passed as the 2nd argument: `serializeUser(user, member)`.
- `npm test` uses a quoted glob, which needs Node ≥ 21. package.json `engines` still says `>=20.11` (not my file).
- Tests run one file at a time (`--test-concurrency=1`), and each file starts its own MongoMemoryServer.
