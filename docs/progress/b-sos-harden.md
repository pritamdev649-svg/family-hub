# Progress · b-sos-harden (adversarial review of backend module `sos`)

Scope: `family_hub_backend/src/modules/sos/**`, `family_hub_backend/src/i18n/locales/en/sos.json`,
`family_hub_backend/tests/sos.test.js`. The full list of findings is appended to `docs/progress/b-sos.md`
("Hardening review").

## Done
- [x] Probed against the real API (supertest + in-memory MongoDB):
  - authz: member vs admin vs owner, other family by id, removed members
  - NoSQL operators in the body, the id and the query
  - mass assignment and `__proto__`
  - invalid, operator-like and uppercase ids
  - 200 KB bodies
  - Unicode: emoji, ZWJ, RTL, Indic, controls, bidi controls, zero-width, lone surrogates
  - numbers: Infinity, 1e13, `-0`, 0.1 + 0.2, strings
  - pagination at and beyond `MAX_SAFE_INTEGER`
  - races: 25 parallel creates × 15 rounds, two members at once, location vs resolve, create vs resolve
  - push recipients and per-device locales
  - envelope, status codes and leaked fields
- [x] Fix H1: the SOS `message` length is counted in UTF-16 units (model + app unit). Before, 71–140 emoji passed zod,
      then failed in Mongoose with a 422 that quoted the text (`sos.schemas.js`).
- [x] Fix H2: `cleanSosMessage` (`sos.schemas.js`):
  - well-formed UTF-16 and NFC
  - controls removed, bidi override / isolate characters removed
  - CRLF → LF, tab → space
  - invisible-only text → null
  - scripts, ZWJ / ZWNJ, LRM / RLM and emoji kept
- [x] Fix H3 (privacy): locations are hidden while the owner's current mode is `never`, or once they left the family.
      This applies to every read and to the dashboard helper, and fails closed (`sos.serializer.js#locationVisible`).
      Nothing is deleted.
- [x] Fix H4: read paths load the member map after the alerts, not in parallel, and skip it for empty lists
      (`sos.service.js`).
- [x] 12 new tests (55 → 67): one per finding, plus regression guards for the attacks that were already handled. The
      5 tests for fixed issues fail on the previous code; that was checked by temporarily restoring it.
- [x] `docs/progress/b-sos.md`: stale statements corrected (message rule, current-mode rule, known issue) and findings
      appended.

## Pending / known issues (need other owners)
- [ ] `src/modules/me/memberCascade.js`: delete the member row before closing their active SOS alerts. Load the names
      for the push first. This closes the orphan-alert race completely.
- [ ] `src/middleware/error.js`:
  - the Mongoose `ValidationError` details quote the value;
  - a `messageKey` that exists only in English beats a translated `common.errors.<CODE>`.
- [ ] `src/models/SosAlert.js`: partial unique index `{ memberId: 1 }`, unique, where `status: 'active'` (b-sos
      handoff, still open).
- [ ] Flutter SOS screen / mock: limit the message to 140 UTF-16 units and mirror the clean-up and the privacy rule.
- [ ] Product decision: a push budget against create → resolve notification floods.
- [ ] Translations of `sos.json` (14 locales) and GAP-03 retention (unchanged from b-sos).

## Verification
- `node scripts/check-syntax.js` → all OK (112 JS, 7 JSON)
- `node --test tests/sos.test.js` → 67 / 67 pass, 3 runs in a row
- `node --test --test-concurrency=1 "tests/**/*.test.js"` → 697 tests, 696 pass. The 1 failure was a race test in
  `tests/ledger.test.js` (another module). It passes on its own (74 / 74, twice).
