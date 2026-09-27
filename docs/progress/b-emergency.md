# Progress · b-emergency (backend module `emergencyCards`)

Owner files: `family_hub_backend/src/modules/emergencyCards/**`, `family_hub_backend/tests/emergencyCards.test.js`.
Contract: docs/03-API_CONTRACT.md §6 (`GET|PUT /family/members/:memberId/emergency-card`).

## Built
- [x] `emergencyCards.routes.js`: `Router({ mergeParams: true })`, `GET /` and `PUT /` behind `familyMember`
      (`requireAuth` + `requireFamily`) and `validate({ params, body })`. The mount in `src/routes/index.js` was already correct.
- [x] `emergencyCards.controller.js`: HTTP only. Sends `Cache-Control: private, no-store` because the card holds health data.
- [x] `emergencyCards.service.js`:
  - [x] `getCard(actor, memberId)`: any member of the family can read it. A member of another family or an unknown member → 404.
        With no saved card it returns the contract empty card (`updatedAt: null`, `updatedById: null`).
  - [x] `saveCard(actor, memberId, body)`: checks run in this order: 404 (not in the family), then 403 (not self or admin).
        PUT replaces the whole card. Encryption goes through the model's virtuals (`crypto.encryptField` / `decryptField`).
        `updatedById` is set to the caller. `updatedAt` changes on every save, even when nothing else changed.
  - [x] Race handling: the whole card is written with **one atomic upsert** (`findOneAndUpdate` + `$set` of every stored path,
        built from a validated draft card so the model still encrypts). When two first saves hit a duplicate key on the unique
        `memberId`, the service retries once. When the member is deleted while a save is in flight, the service deletes the card
        again and returns 404, so no health data is left orphaned. *(Changed by b-emergency-harden. The earlier read-then-`save()`
        could store a mix of two racing PUTs; see below.)*
  - [x] Helpers for other modules: `plainCardFor(familyId, memberId)` returns the plaintext card or the empty card.
        `deleteCardForMember(familyId, memberId)` returns the count deleted and is idempotent.
- [x] `emergencyCards.schemas.js`: the contract limits (lists ≤ 20 × 80, contacts ≤ 5, notes ≤ 500), the model backstops
      (doctorName / insuranceProvider / contact name ≤ 100, relation ≤ 60, policy number ≤ 100), phone validation (shared `phone`
      block), and normalisation (see decisions). Unknown and read-only keys are stripped.
- [x] `tests/emergencyCards.test.js`: 45 tests. They cover:
  - the empty card
  - create, replace and clear
  - normalisation
  - encryption at rest, checked on the raw Mongo document (no plaintext, `enc:v1:` format, a fresh IV on every save)
  - the permission matrix: self, admin, second admin, demoted admin, member → other member or managed profile (403),
    other family's admin or member (404), unknown or removed member (404), no token (401), no family (403 NO_FAMILY)
  - 400 for a malformed id or malformed JSON
  - every limit with boundaries, and 422 `details` paths (`allergies.1`, `emergencyContacts.0.phone`, …)
  - several errors reported at once
  - a non-object body
  - forged keys ignored (`allergiesEnc`, `familyId`, `memberId`, …)
  - Unicode round trip
  - concurrent first saves
  - the retry path and the orphan-cleanup path, both deterministic
  - a decryption failure returning 500 instead of an empty card
  - the envelope shape and the `no-store` header

## Decisions
- **PUT = full replacement.** A field missing from the body goes back to its empty value (`bloodGroup: "unknown"`, `[]`, `null`).
  The app should always send the complete card. A GET response sent straight back is accepted: `memberId`, `updatedAt` and
  `updatedById` are ignored.
- **Normalisation:**
  - `bloodGroup` is case- and space-insensitive (`" ab - "` → `AB-`). null or blank → `unknown`.
  - List items are trimmed, blank items are dropped, and case-insensitive duplicates are removed before the 20-item limit applies.
  - Phones have spaces, dashes and brackets stripped (`+91 (987) 654-3210` → `+919876543210`).
  - Blank text → `null`.
- **Emergency contact `phone` is optional** (nullable, validated when present), as in the model. `name` is required (1–100).
- **Validation runs before the access checks** (422 comes before 404/403). This leaks nothing, because a validation error
  does not depend on whether the target exists.
- Lengths are UTF-16 code units after clean-up (`String#length`), the same as the app's `Validators.maxLength` and the Mongoose
  `maxlength` backstops. This is now enforced with an explicit check, because zod 4's `.max()` counts code points *(fixed by
  b-emergency-harden)*.
- There is no push or e-mail for card edits: the contract defines none.

## Pending / not in scope
- [ ] Cascades in other modules should call `deleteCardForMember` (see handoffs). This module can't enforce them.
- [ ] `enc:v2` key rotation / re-encryption (docs/08-COMPLIANCE.md TODO).

## Known issues
- A card that can't be decrypted (wrong `FIELD_ENCRYPTION_KEY` or a corrupted blob) makes GET and PUT return `500 INTERNAL_ERROR`.
  This is intentional: an emergency screen must never show "no allergies" when the data is actually unreadable.
- Two concurrent PUTs on an existing card: the last write wins (normal PUT semantics), and the stored card is always one
  complete body, never a mix. There is no optimistic locking (the contract defines no `If-Match` / version field).

## Hardening review (b-emergency-harden, 2026-09-27)

An adversarial pass over the module. Every finding has a test in `tests/emergencyCards.test.js`
(`describe('PUT …: hardening')`). The suite now has 67 tests, up from 45.

### Findings, fixed
- [x] **A PUT without a JSON body wiped the card (data loss).** The shared `validate()` reads a missing body as `{}`, and
      PUT replaces the whole card. So no body, an empty body, JSON sent as `text/plain` or a form post returned 200 and
      erased every field. Fix: the `requireJsonBody` guard in `emergencyCards.routes.js` returns 422 with `details.body`
      and changes nothing. It runs after the id check, so the order stays 401 → 403 NO_FAMILY → 400 → 422. An explicit `{}`
      still clears the card.
- [x] **Racing PUTs could store a torn card.** `findOne()` + `save()` only `$set`s the paths that differ from the copy it
      read. When PUT B landed between A's read and A's write, the result mixed both, e.g. B's blood group and doctor with A's
      allergies. This was reproduced deterministically. Fix: one atomic upsert that `$set`s every stored path (see above).
- [x] **Malformed UTF-16 was silently corrupted.** A lone surrogate in a plaintext field (doctorName, insurer, contacts)
      was echoed back in the PUT response but stored by MongoDB as U+FFFD. Fix: 422 "Contains characters that are not
      allowed".
- [x] **Control and bidi-override characters were stored** (NUL, ESC, U+202A–U+202E, U+2066–U+2069). Fix: they are
      removed. Line breaks and tabs become one space in single-line fields. In `notes`, line breaks are normalised to `\n`
      and tabs kept.
- [x] **Invisible-only text counted as content.** A ZWSP-only allergy, contact name or doctor name produced an empty-looking
      chip or name. Fix: text with no visible character (only whitespace, format characters, variation selectors,
      Hangul fillers or Braille blank) counts as blank. ZWJ / ZWNJ / LRM / RLM inside real text are kept (Indic, Persian,
      emoji sequences).
- [x] **Length unit mismatch.** zod 4.6 `.max()` counts code points, while Mongoose `maxlength` and the app count UTF-16
      units. A doctorName of 51 emoji passed zod, then failed the model with a message that **echoed the value**.
      Fix: an explicit UTF-16 length check. The app's limit and the server's are now identical.
- [x] **Unbounded work and error amplification from huge arrays.** zod validates every element before the array `.max()`.
      A 100 kb body with about 1 000 bad items returned 2 200 `details` keys (112 kB), and 30 000 blank items were accepted.
      Fix: at most `RAW_LIST_MAX` = 100 raw entries per list and 5 raw contacts, checked **before** any item is validated.
      Blanks and duplicates within that bound are still cleaned before the 20-item limit.
- [x] Text is stored in NFC, so the same word typed with composed or decomposed accents is stored and deduplicated identically.
- [x] Blood group also accepts the typographic minus, dashes and full-width characters (`ab−` → `AB-`, `Ｏ＋` → `O+`).

### Probed, already safe (regression tests added)
- [x] NoSQL operator objects in every body field → 422. Operator-shaped `:memberId` → 400. Query-string `familyId` /
      `memberId[$ne]` → ignored (the family scope always comes from the token).
- [x] `__proto__` / `constructor` keys: no prototype pollution; nothing reaches the card.
- [x] Extra keys inside contacts (`_id`, `familyId`, …) are stripped, in the response and in the raw document.
- [x] Numbers and booleans (0, −1, 1e13, 0.1+0.2, `true`) are never coerced to text or phone numbers.
- [x] Body over 100 kb → 413 `PAYLOAD_TOO_LARGE` with the card untouched. Deeply nested junk under an unknown key → ignored.
- [x] A card last edited by a member who was later removed still reads fine, and the removed member's token gets 403 NO_FAMILY.
- [x] Responses never contain ciphertext, `_id`, `__v`, `familyId` or another family's data.
- [x] No push or e-mail is sent by this module (the contract defines none), so there are no recipient or locale concerns.

### Known issues / pending (not fixable inside this module)
- [ ] AES-GCM fields have no associated data (AAD). Someone with **write** access to the database could move a ciphertext
      between fields or cards and it would still decrypt. Needs `enc:v2` with AAD = card or member id + field (owners of
      `lib/crypto.js` and `models/EmergencyCard.js`, together with key rotation in docs/08-COMPLIANCE.md).
- [ ] A chunked request with an empty JSON body (no `Content-Length`) is still read as `{}`. Detecting it needs the raw body
      length from `express.json({ verify })` in `app.js`.
- [ ] Member removal (`DELETE /family/members/:id`) must call `deleteCardForMember`. The family module isn't built yet.
      `DELETE /me` and family deletion already delete cards (`modules/me/memberCascade.js`).

