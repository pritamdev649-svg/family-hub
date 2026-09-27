# Progress · b-sos (backend module `sos`)

Owner files: `family_hub_backend/src/modules/sos/**`, `family_hub_backend/src/i18n/locales/en/sos.json`,
`family_hub_backend/tests/sos.test.js`.
Contract: docs/03-API_CONTRACT.md §10 (+ push payloads §13). Tasks SOS-01 … SOS-07 in docs/TASKS.md.

## Built
- [x] `sos.routes.js`: all 6 endpoints behind `familyMember` (`requireAuth` + `requireFamily`). `/active` and `/history` are
      declared before `/:id`. The mount in `src/routes/index.js` (`/sos`) was already correct.
- [x] `sos.controller.js`: HTTP only. 201 for a new alert, 200 for the idempotent repeat. Every response sends
      `Cache-Control: private, no-store` because alerts contain live locations.
- [x] `sos.schemas.js`: built from the shared blocks (`latLng`, `idParams`, `pagination`) plus the SOS `message` rule
      (clean-up + UTF-16 length, see "Hardening review"). Bodies strip unknown keys (they are never rejected), so an
      SOS can't fail because the app sent an extra field.
- [x] `sos.serializer.js`: `serializeSosAlert` / `serializeSosAlerts` (exact contract shape; `memberName/Phone/AvatarUrl`
      come from `memberDirectory`), `sosStatusOf` and `isSosActive` (lazy status for lean objects).
- [x] SOS-01 `POST /sos`:
  - The "find active alert or insert one" step is a single upsert. If the caller already has an active alert it is
    returned **unchanged** with 200, and no second push is sent.
  - `expiresAt = startedAt + 15 min`. `message` is cleaned (controls / bidi overrides removed, NFC, trimmed),
    blank or invisible-only → null, at most 140 UTF-16 code units.
  - Sharing mode `never` → the location is dropped and `locationShared: false`. For `sos_only` / `always`,
    `locationShared: true`, and a first fix is stored as `lastLocation` + the first trail point (server time).
  - Race safety: the upsert matches an existing alert, and a post-insert check keeps the oldest active alert (the
    server assigns the `_id`) and deletes any newer duplicate. The service also handles E11000 (answer with the winner,
    retry once), which prepares it for the unique index in the handoffs.
  - If the caller was removed from the family during the request, the insert is undone and the response is
    `403 NO_FAMILY`.
  - Push: `sos` (high priority, channel `sos_alerts`, route `/sos/alert/<id>`) to every other member with an account.
    The body names the sender; there is a separate text for alerts without a location.
- [x] SOS-02:
  - `GET /sos/active`: active alerts of the family (the caller's own included), newest first, `trail: []`.
  - `GET /sos/history?page&limit`: resolved / expired alerts, newest first, with `meta`.
  - `GET /sos/:id`: includes `trail` (at most 100 newest points, oldest first).
- [x] SOS-03 `POST /sos/:id/location`:
  - The error checks run in this order: 404 (other family / unknown) → 403 `FORBIDDEN` (not the owner; admins
    included) → 409 `SOS_NOT_ACTIVE` → 403 `LOCATION_SHARING_DISABLED` (the owner's **current** mode is `never`).
  - The 3 s throttle, the active check and `$push` + `$slice: -100` run as **one atomic** `findOneAndUpdate`, so
    concurrent updates store at most one point per window. A throttled update → 200 with the current alert.
  - Switching from `never` to `sos_only` / `always` during an alert starts sharing (`locationShared` → true).
- [x] SOS-04 `POST /sos/:id/resolve`:
  - The owner or an admin (another member → 403, other family → 404).
  - Idempotent on an already resolved alert: 200, unchanged, the first resolution wins, no second push.
  - An expired alert → 409 `SOS_NOT_ACTIVE`.
  - The transition is atomic, so concurrent resolves send one push.
  - `sos_resolved` push (route `/sos/alert/<id>`) to everyone but the resolver. There are separate texts for "the
    owner ended it" and "an admin ended it".
- [x] SOS-05 lazy expiry: every endpoint first persists `active` → `expired` for the family (`SosAlert.expireStale`), and
      every response recomputes the status.
- [x] SOS-06 `src/i18n/locales/en/sos.json`:
  - `push.alert.title|body|bodyNoLocation`
  - `push.resolved.title`
  - `push.resolved.body|bodyByOther.{safe,false_alarm,helped,closed}`
  - `errors.notOwner|resolveNotAllowed|notActive|locationSharingDisabled`
- [x] SOS-07 `tests/sos.test.js`: 67 tests (55 by b-sos, 12 added by the hardening review). They cover:
  - 401 / 403 NO_FAMILY on every route
  - create: 201 vs 200, the 15 min window, the location dropped for `never`, first fix, empty body, unknown keys stripped
  - concurrency of 6 parallel creates, and a stubbed E11000 (winner found / retry / give up)
  - pushes and their recipients (managed profile and sender excluded, localized texts, the message never in a push)
  - phone and avatar from the profile
  - family isolation
  - the validation matrix with 422 `details` paths and the boundaries, plus 400 for malformed JSON
  - active / history: order, pagination, lazy expiry persisted, a removed member → `memberName: null`, invalid
    pagination
  - `GET /:id`: trail order, privacy, 404 / 400
  - location: storing, the throttle, concurrent updates, the 100-point cap, the permission matrix, 409 after resolve and
    after expiry, 403 when sharing is `never`, check order, mode switches, validation
  - resolve: owner and admin resolving, push recipients and texts, idempotency, concurrent resolves, 403 / 404, 409 on
    expiry, validation
  - serializer unit tests, the exported helpers, and i18n key completeness

## Exported for other modules
- `sos.service.js`:
  - `activeAlertsForFamily(familyId, { members?, now? })`: runs the lazy expiry and returns the serialized active
    alerts. It is meant for the dashboard's `activeSos`.
  - `expireStaleAlerts(familyId, now?)`.
  - `notifySosResolved({ familyId, alertId, ownerMemberId, resolverMemberId?, resolution?, members? })`: sends the
    `sos_resolved` push. It never throws, and `resolution: null` → the "closed" text.
- `sos.serializer.js`: `serializeSosAlert`, `serializeSosAlerts`, `sosStatusOf`, `isSosActive`.

## Decisions
- **Resolve**: resolving an already resolved alert returns 200 unchanged, and an expired alert gets 409. The contract's
  error table lists "resolve on resolved/expired → 409", but §10 and the task say "idempotent on already resolved", so
  the more specific rule wins.
- **Only `GET /sos/:id` returns the trail.** `POST /sos`, `POST /:id/location` and `/:id/resolve` return `trail: []`
  (contract: "trail is included only by GET /sos/:id"). This also keeps the 5 s update loop light.
- **Idempotent create is strict**: the repeat's `message` and `location` are ignored. The client sends later fixes to
  `POST /:id/location`.
- **The push never contains the free-text `message`.** It may hold health details, and lock screens are visible to others
  (docs/08-COMPLIANCE.md §3 row 20). The app shows the message on the alert screen.
- **`sos_resolved` is sent with high priority**, so worried relatives learn quickly (channel `general`, as the contract says).
- **The owner's current sharing mode governs location updates and reads.** The mode stored at create time does not.
  While the owner shares `never`, no response shows the location of any of their alerts (see "Hardening review").
- **Admins cannot post locations for someone else's alert** (owner only, per the contract); they get 403 `FORBIDDEN`.
- **History "newest first" = `startedAt` desc, then `_id` desc.** `/active` uses the same order.
- **Location points use server time** (`recordedAt`); the contract body has no client timestamp.
- **The managed child in the tests is written through the `Member` model**, because `POST /family/members` belongs to
  b-family and is still a placeholder.

## Pending / not in scope
- [ ] Translations of `sos.json` for the other 14 locales (translation agents). Until then the SOS error messages fall
      back to English even when `common.errors.*` is translated, because the module-specific `messageKey` wins.
- [ ] GAP-03 retention (delete the trail 30 days after the end, keep the summary for 12 months): needs a job/TTL owner.
- [ ] The dashboard `activeSos` should reuse `activeAlertsForFamily` (b-dashboard).

## Known issues
- There is no unique index on active alerts (the model is owned by b-models). The create race is closed by the upsert,
  plus the post-insert "oldest wins" check that relies on server-assigned `_id` order. A microsecond window inside
  MongoDB (id assigned, commit visible later) could in theory still leave two active alerts. The partial unique index in
  the handoffs closes it completely, and the service already handles the resulting E11000.
- Switching to `never` hides the stored points of the owner's alerts (fixed by the hardening review), but they are
  only deleted once the retention rule (GAP-03) exists.
- `memberName`, `memberPhone` and `memberAvatarUrl` are `null` for alerts of a removed member (tasks do the same for
  `assigneeName`).

## Hardening review (b-sos-harden)

An adversarial pass over authz, injection, mass assignment, ids, payload size, Unicode, numbers, pagination, races,
removed members, the envelope, leaks and push recipients / locales. Probes ran against the real API on an in-memory
MongoDB. Every finding got a test. The five tests for fixed issues were checked to fail on the previous code.

### Fixed
- [x] **H1 (high) Emoji messages failed the SOS and echoed the text.** zod 4's `.max(140)` counts code points, but the
      SosAlert `maxlength` and the app (Dart `String.length`) count UTF-16 units. A message of 71–140 emoji passed
      zod, then failed in Mongoose with 422 and a `details.message` that quoted the (possibly health-related) text.
      Now the schema counts UTF-16 units and answers `Message must be at most 140 characters` without echoing
      anything.
- [x] **H2 (medium) Message hygiene.** NUL / BEL / ESC and other controls, bidi override / isolate characters
      ("Trojan Source" spoofing on relatives' screens), CRLF, and zero-width-only "blank" messages were stored as sent.
      Now `cleanSosMessage`:
  - makes the text well-formed (a lone surrogate → U+FFFD, the same as MongoDB, so the response equals the stored
    value);
  - turns line breaks into `\n` and tabs into a space, and removes the other controls and the bidi controls;
  - applies NFC and trims (including a leading / trailing ZWSP, word joiner or BOM);
  - turns invisible-only text into `null`;
  - keeps RTL and Indic scripts, ZWJ / ZWNJ, LRM / RLM and emoji sequences.
- [x] **H3 (medium, privacy) Location visible after consent was withdrawn.** When the owner switched to `never`,
      their active alert kept showing `lastLocation` to the whole family (`/sos/active`, `/sos/:id`, the dashboard
      helper, history). The serializer now shows a location only when all three hold:
  - the alert was shared;
  - the owner is still a member of the family;
  - the owner's **current** mode is not `never`.

  The rule fails closed: a member entry without `locationSharing` counts as `never`. Nothing is deleted, so
  switching back shows the points again, and retention stays GAP-03.
- [x] **H4 (low) Read-side ordering.** `/active`, `/history` and `GET /:id` loaded the member map in parallel with the
      alerts. An alert raised by someone who joined between the two queries came back with `memberName: null`, and
      with H3 also without its location. Now the alerts load first and the members after them, with no member
      query when the list is empty.

### Verified, already safe (regression tests added)
- NoSQL operators: `{ "$ne": null }` in `message`, `lat`, `lng` or `resolution` → 422. In the query (`page[$gt]`,
  `status`, `familyId`) they are ignored. Operator-like ids → 400.
- Mass assignment in all three bodies is stripped: `_id`, `familyId`, `memberId`, `status`, `startedAt`,
  `expiresAt`, `trail`, `resolvedById`, `resolvedAt`, `recordedAt`, `$set`, and `__proto__` / `constructor` (no
  prototype pollution). Location points always carry server time.
- Numbers:
  - `1e400` (Infinity), `1e13`, strings, arrays and out-of-range values → 422.
  - `0.1 + 0.2` and `-0` round-trip exactly.
  - accuracy is capped at 100 000 m.
- Pagination: `page=MAX_SAFE_INTEGER` gives an empty page (no 500). Unsafe integers, `1e16`, negative values,
  duplicated params and `Infinity` → 422.
- Races:
  - 25 parallel creates × 15 rounds: always one alert and one push.
  - Two members raising at once: two alerts, each pushed to the others.
  - Location updates racing a resolve never write after `resolvedAt`.
- Push: localized per recipient device (device → account locale → `en`). It never reaches the sender, the resolver
  or another family.
- A 200 KB body → 413 (`PAYLOAD_TOO_LARGE`); malformed / non-object JSON → 400 / 422.

### Open (other owners, see the b-sos-harden handoffs)
- [ ] Member-removal race: the cascade closes active alerts **before** deleting the member row, so an SOS inserted in
      between survives as an orphan (active, `memberName: null`, no location since H3). Deleting the member row
      first (after loading the names for the push) closes it completely, because `settleCreateRace` already undoes
      inserts once the member is gone. File: `src/modules/me/memberCascade.js`.
- [ ] `src/middleware/error.js`: Mongoose `ValidationError` details quote the rejected value, and a module
      `messageKey` translated only in English beats a translated `common.errors.<CODE>`.
- [ ] Partial unique index on active alerts (b-models, unchanged from above).
- [ ] Notification flooding: a member can cycle create → resolve and send a high-priority `sos` push each time. This
      is bounded only by the global rate limit (300/min/IP). Not throttled on purpose, because suppressing a push
      after a false alarm could hide a real emergency. Needs a product decision (e.g. a per-member push budget that
      never blocks the alert itself).

