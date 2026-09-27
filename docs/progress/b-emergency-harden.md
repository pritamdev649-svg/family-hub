# Progress · b-emergency-harden (adversarial review of backend module `emergencyCards`)

Scope: `family_hub_backend/src/modules/emergencyCards/**`, `family_hub_backend/tests/emergencyCards.test.js`.
The full findings list is appended to `docs/progress/b-emergency.md` ("Hardening review").

## Done
- [x] Probed authz (self / admin / member / managed profile / other family / removed member), NoSQL operators in the body,
      params and query, `__proto__` / mass assignment, invalid ids, huge payloads and arrays, Unicode (emoji, RTL, ZWJ,
      lone surrogates, control and bidi characters), numeric junk, races, deleted members referenced, envelope and leak checks.
- [x] Fix: a PUT without a JSON body (none, empty, `text/plain`, form) → 422 `details.body`. It used to wipe the card
      (`requireJsonBody` in `emergencyCards.routes.js`).
- [x] Fix: atomic full replacement. One `findOneAndUpdate` upsert with `$set` of every stored path, built from a validated
      draft card so the model still encrypts. Racing PUTs used to store a mix of both cards (`emergencyCards.service.js`).
- [x] Fix: text clean-up in `emergencyCards.schemas.js`:
  - NFC
  - control and bidi-override characters removed
  - line breaks → spaces in single-line fields, `\n` in notes
  - invisible-only text counts as blank
  - lone surrogates → 422
- [x] Fix: lengths are counted in UTF-16 units, the same as the app and the Mongoose backstops. zod 4 counts code points,
      and the model backstop then answered with a message that echoed the value.
- [x] Fix: raw array bounds (100 per list, 5 contacts) are checked before items are validated. This bounds work and the size
      of `details`.
- [x] Blood group also accepts typographic dashes and full-width characters.
- [x] 22 new tests, one per finding plus regression guards for the attacks that were already handled. They are
      implementation-agnostic where it matters: the torn-write test fails on the old read-modify-save code and passes on the
      atomic upsert. Two old tests that patched `EmergencyCard.findOne` were rewritten for the new write path.
- [x] `docs/progress/b-emergency.md`: stale statements corrected (length unit, race handling) and findings appended.

## Pending / known issues (need other owners)
- [ ] `enc:v1` has no AAD, so ciphertext can be swapped between fields or cards by anyone who can write to the DB
      (crypto + model owners, `enc:v2`).
- [ ] A chunked empty JSON body is still read as `{}`; needs the raw length from `express.json({ verify })` (app.js owner).
- [ ] `DELETE /family/members/:id` must call `deleteCardForMember` (family module not built yet).
- [ ] The Flutter mock handler should mirror the new server rules (see handoffs in the final report).

## Verification
- `node scripts/check-syntax.js` → all OK
- `node --test tests/emergencyCards.test.js` → 67 / 67 pass
- Regression: `tests/health.test.js` 9/9, `tests/core.test.js` 94/94, `tests/me.test.js` 59/59
