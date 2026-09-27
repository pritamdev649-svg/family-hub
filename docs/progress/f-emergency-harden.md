# f-emergency-harden: review and hardening of the Flutter emergency card feature

Owner files (same as f-emergency): `family_hub_app/lib/features/emergency_card/**`,
`family_hub_app/l10n_parts/emergency_card.arb`, `family_hub_app/test/features/emergency_card/**`.

## 1. Contract conformance (docs/03-API_CONTRACT.md §6)
- [x] `GET` / `PUT /family/members/:id/emergency-card`. The path id is URL-encoded (`pathId`), and the JSON field names
      match the contract exactly.
- [x] Blood group wire names are `A+ A- B+ B- AB+ AB- O+ O- unknown`. The parser is lenient, and anything unknown
      becomes `unknown`.
- [x] The PUT body holds only the editable fields and always the whole card, because the backend replaces it.
- [x] Nothing here is paginated. The error codes handled are 400, 401, 403 `FORBIDDEN` / `NO_FAMILY`, 404, 422 and
      5xx.
- [x] The mock handlers now match `family_hub_backend/src/modules/emergencyCards` (see §4).

## 2. Guide conformance (docs/05-FLUTTER_GUIDE.md)
- [x] Design tokens only. A grep finds no `EdgeInsets` or `SizedBox` numbers, no `fontSize`, no `Color(0x…)` or
      `Colors.*`, and no left/right.
- [x] l10n: two strings were hard-coded: the list separator `', '` in "Missing: …" and `'$name · $detail'` in the
      responder view. Both now come from `emergencyCardListSeparator` and `emergencyCardPersonWithRelation`.
- [x] RTL: numbers, phone numbers and blood groups stay left-to-right. Everything else uses start/end.
- [x] Every async screen uses `AsyncValueView`. The "not available" state (NOT_FOUND) is picked before
      `AsyncValueView`, just as the existing permission state is, because `AsyncValueView` has no slot for a
      custom error (handoff below).
- [x] Mutations: the button shows a busy state, a second submit is blocked, errors are localized, `markChanged`
      runs after a save, and `context.mounted` / `mounted` is checked after every await.
- [x] DRY: the mock uses `EmergencyCardLimits`. `pushIfTop` lives in the family feature, so a small local copy is
      used here, with a TODO and a handoff to move it into core.

## 3. Edge-case sweep (23 cases)

| # | Case | Result |
|---|---|---|
| 1 | Offline / timeout / 5xx on open, with an offline copy | Already handled: the copy is shown with an "Offline copy from …" hint. Tested |
| 2 | Offline copy stays on screen after the connection returns | **Fixed**: refetches when the connection comes back online, and reopening retries (`refreshIfStale`). Tested |
| 3 | Slow cold start: opening a screen restarts the running request | **Fixed**: nothing is refreshed while a request is running (`_inFlight`). Tested |
| 4 | An old build (account switch / markChanged mid-request) writes state or an offline copy | **Fixed**: each build checks its own `Ref`. `ref.mounted` was always true, because Riverpod's `Notifier.ref` points at the newest build. Tested |
| 5 | A save that finishes after logout leaves health data in the keystore | **Fixed**: the store checks the live session at write time, and writes run one at a time (a save queued before a wipe gets wiped). Tested |
| 6 | 401 expiry mid-save | `AuthInterceptor` refreshes the token and retries. If the refresh fails, the session expires, the `mounted` checks prevent further UI work, and #5 prevents writes |
| 7 | 403 for a non-admin (or an admin demoted mid-edit) | **Fixed**: the session is re-read, so `canEdit` turns false and the form shows "no permission". A localized snackbar is shown. Tested |
| 8 | `NO_FAMILY` on save | **Fixed**: the session is re-read and the router sends the user to family setup |
| 9 | 404: an old link or notification opens a removed member | **Fixed**: `EmergencyCardUnavailable` with Back (or All emergency cards) and no pointless Retry. Edit is hidden. Tested |
| 10 | 404: member removed while the card or form is open, or while saving | **Fixed**: the same state appears after a refresh. A save that gets 404 calls `markChanged({members, emergencyCards})` and deletes the offline copy. Tested |
| 11 | 409 / 422 | The contract has no 409 for this endpoint. Client validation mirrors every server limit. A 422 shows the localized validation error and the form keeps the edits. Tested |
| 12 | Empty lists | No members shows an EmptyState. An empty card shows the "Fill in" button or a read-only message. Empty sections show "Not recorded" |
| 13 | Very long text (60-char name, 80-char unbreakable allergy, 100-char doctor, contact and policy fields, 500-char notes, 5 contacts) | No overflow at 1.4× in RTL on a 360 dp phone, in the list, card, responder view and form. Tested |
| 14 | Large text mode | Same as #13, plus the builder's test |
| 15 | Time zone / clock | Times are parsed as UTC and shown in local time through `Fmt`. **Fixed**: an offline copy whose time is in the future (device clock set back) is shown with the current time. Tested |
| 16 | Deleted or renamed members referenced by the card | The header uses the member directory, which refetches on `markChanged(members)`. Contacts are free text. **Fixed**: a contact without a name shows as "Contact N" and can still be called. Tested |
| 17 | Rapid repeated taps | Save was already guarded (controller plus busy button). **Fixed**: "Show to responder" is guarded by the route, and card and edit pushes are guarded with `isCurrent`. Tested |
| 18 | Stale data after another member edits the card | **Fixed**: the card screen and list tiles refresh cards older than 1 min, and the responder view follows the live card. Tested |
| 19 | Edit form opened on an offline copy, then the fresh card arrives | **Fixed**: the form takes the fresh card when nothing is edited yet. If the user already edited, it keeps the edits and shows "updated while you were editing". Tested |
| 20 | Pagination end | Not applicable: `/family/members` is not paginated and the card is a single object |
| 21 | Permission changes while a screen is open | `canEdit` watches `currentMember` / `isAdmin`, so Edit and the form react. A server 403 triggers a session re-read (#7) |
| 22 | Deep link straight to the edit form | **Fixed**: after a save the form goes on to the card instead of staying on the form. Tested |
| 23 | Account switch / logout | The builder's wipe on account change, the orphan purge and the per-user marker remain, plus #4 and #5 |

## 4. Mock handlers vs the backend (fixed)
- [x] Unknown and read-only keys (`memberId`, `updatedAt`, `updatedById`, `allergiesEnc`, …) are removed instead of
      rejected. A GET body can be sent back unchanged.
- [x] Order of checks: 401 → 403 `NO_FAMILY` → 400 malformed id → 422 → 404 → 403 `FORBIDDEN`. GET also returns 400
      for a malformed id.
- [x] `bloodGroup` is matched ignoring case, spaces and dash style. null or blank becomes `unknown`. A value that is
      not text is an error.
- [x] Lists: null becomes `[]`, at most 100 raw entries, items must be text, blank items are dropped,
      case-insensitive duplicates are removed (first spelling kept), then the 20 × 80 limits apply.
- [x] Contacts: more than 5 is reported before the items are checked. `name` is required (up to 100), `phone` is
      optional but must be valid, `relation` is up to 60.
- [x] Text: line breaks become a space (`notes` keeps `\n`), C0/C1 control characters and bidi embedding / override /
      isolate characters are removed, and text with only invisible characters becomes `null`. The phone separators
      are `[\s\-()]`, as in the backend.
- [x] PUT replaces the whole card: missing keys are reset to their empty values.

## 5. Tests
- [x] 71 → 104 tests.
  - New: `emergency_card_edge_cases_test.dart` (18 widget tests).
  - Extended: providers (connection returns, `refreshIfStale`, account switch mid-request, FORBIDDEN / NO_FAMILY /
    NOT_FOUND on save, save after logout), offline store (session check, write order, clock), mock handlers
    (400, order of checks, normalisation, dedupe before the limit, contacts, removed keys).
- [x] `emergency_card_test_utils.dart`: `SessionRefreshSpy`, `meBuilder` (a signed-in member that can change),
      and `pumpEmergencyApp(deepLink:)`.

## Verification
- `dart run tool/l10n.dart`: OK (merged, gen-l10n OK)
- `dart analyze lib/features/emergency_card test/features/emergency_card`: No issues found
- `flutter test test/features/emergency_card`: +104, all tests passed

## Pending / handoffs
- [ ] (f-core) Move `pushIfTop` / `popOrGo` from `features/family/presentation/family_navigation.dart` into
      `core/router`, then replace `pushFromEmergencyCard` in `emergency_card_actions.dart`.
- [ ] (f-core widgets) `AsyncValueView` could take an optional `errorBuilder` (or a `notFound` slot), so
      NOT_FOUND states would not need to be picked before it.
- [ ] (session owner) Optional: call `ref.read(emergencyCardOfflineStoreProvider).clearAll()` on logout or account
      deletion for an immediate wipe (still open from f-emergency). Late writes are already blocked.
- [ ] (f-sos) Embed `EmergencyCardView(card:, member:)` in the SOS alert screen.
- [ ] (translations) 6 new keys: `emergencyCardNotFoundTitle`, `emergencyCardNotFoundMessage`,
      `emergencyCardBackToList`, `emergencyCardChangedWhileEditing`, `emergencyCardListSeparator`,
      `emergencyCardPersonWithRelation`.
- [ ] (f-auth) `lib/features/auth/domain/auth_rules.dart:22` has raw bidi control characters (U+202A–U+202E,
      U+2066–U+2069) inside a string literal. `dart analyze lib` reports 4 `text_direction_code_point_in_literal`
      warnings. Write them as `‪`-style escapes.

## Known issues / notes
- The responder view cannot keep the screen awake: there is no wakelock package, and adding packages was out of
  scope.
- The client does not treat text made only of invisible characters (such as a zero-width space as a contact name)
  as blank. The server would answer 422 and the user sees the generic validation message. This is rare.
- The last save wins, because the contract has no optimistic locking. The form warns only when the newer version has
  already reached this device.
- `emergencyCardProvider` is deliberately not auto-disposed: cards show instantly from memory, and `refreshIfStale`
  keeps them fresh.
- The double-tap tile test passes with or without the `isCurrent` guard, because Flutter already cancels pointers on
  push. The guard is a cheap safety net for taps within the same frame.
