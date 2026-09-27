# Progress · b-models (backend data models)

Owner files: `family_hub_backend/src/models/**`, `docs/04-DATA_MODELS.md`.

## Built
- [x] `models/enums.js`: every persisted enum from the contract (locales, roles, location sharing, gender, task
      category/priority/status, ledger types and per-type categories, goal status, SOS status/resolution, blood groups,
      device platforms, OTP purposes), invite-code alphabet/regex, SOS constants (15 min, 100-point trail, 3 s throttle),
      `MAX_AMOUNT_MINOR`, `LIMITS`, `ledgerCategoriesFor()` / `isLedgerCategoryFor()`. Re-exported by `lib/constants.js`.
- [x] `models/schemaUtils.js`: `defineModel` (safe re-compile), `applyToJson` (id string, no `_id`/`__v`, flattened
      ObjectIds, hidden secrets), setters (`emptyToNull`, `truncate`), validators (`isValidTimeZone`, integer minor units),
      field factories, and the shared `locationPointSchema()`.
- [x] `User`: unique lowercase email, hidden passwordHash/lockout fields, `isLocked` virtual, consent timestamp.
- [x] `RefreshToken`: unique tokenHash, TTL on expiresAt, `isActive()`, rotation fields, truncated ip/UA.
- [x] `Otp`: unique {email,purpose}, TTL (1 h grace after expiry), `isExpired()`.
- [x] `Family`: unique uppercase inviteCode with random default, ISO country/currency, IANA timezone validation.
- [x] `Member`: partial unique {familyId,email} and {userId}, `locationSharing` default `never`, `lastLocation`
      sub-document, guardian-consent fields, `hasAccount` virtual.
- [x] `Device`: unique token, TTL after 270 idle days, `lastSeenAt` bumped automatically on save/updateOne/findOneAndUpdate.
- [x] `Task`, `LedgerEntry` (category-for-type validation on docs **and** update validators), `Goal` (`progress`
      virtual), `Notice`.
- [x] `SosAlert`: `expiresAt` default = startedAt + 15 min, trail ≤ 100, `effectiveStatus()`, `isActive()`, static
      `expireStale()`.
- [x] `EmergencyCard`: AES-256-GCM encrypted fields behind plaintext virtuals, `toPlainCard()`, static `emptyCard()`,
      `*Enc` hidden from JSON, ≤ 5 contacts, unique memberId.
- [x] `models/index.js`: named and default exports of all 12 models, enums re-export, `models` map, `initModels()`,
      `syncAllIndexes()`.
- [x] `docs/04-DATA_MODELS.md`: tables per collection, indexes, mermaid ER diagram, cascades, privacy/TTL notes, decisions.

## Verified
- [x] `node --check` on all 15 files in `src/models/`.
- [x] `node -e "import('./src/models/index.js').then(m=>console.log(Object.keys(m)))"` lists all models, enums and helpers (no DB needed).
- [x] DB-free assertion script: defaults, enums, limits, setters, toJSON shape, ledger category validation (doc and query
      context), goal progress, SOS expiry, card encryption. It was a temporary script and was deleted.
- [x] mongodb-memory-server (mongod 8.2.6) assertion script: unique, partial unique and TTL indexes exist and are enforced,
      the device upsert/touch hook works, `$push`/`$slice` trims the SOS trail to 100, `expireStale`, the emergency card is
      encrypted at rest and round-trips, and ledger update validators work. It was a temporary script and was deleted.

## Pending / not in scope
- [ ] Unit tests in `tests/models.test.js`: not in my ownership. The assertions above could be ported by the tests owner.
- [ ] DB-level "one active SOS per member" guard: intentionally not added (see decision 4 in 04-DATA_MODELS.md).

## Known issues / notes for other agents
- Call `await initModels()` after `mongoose.connect()` in `tests/helpers.js` and `scripts/seed.js`. Otherwise duplicate-key
  tests can race the background index build.
- `Family.inviteCode` has a random default. The family service must still retry on an 11000 error, and must uppercase the
  user input for look-ups.
- `Goal.savedMinor` changes via `$inc`, which bypasses validators. Clamp at 0 in the service.
- SOS lists should use `.select('-trail')`. Call `SosAlert.expireStale({ familyId })` before reading active alerts.
- EmergencyCard virtuals are unavailable on `.lean()`; use `decryptField` or a hydrated document with `toPlainCard()`.
