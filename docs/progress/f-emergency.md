# f-emergency: Flutter emergency card feature

Owner files: `family_hub_app/lib/features/emergency_card/**`, `family_hub_app/l10n_parts/emergency_card.arb`,
`family_hub_app/test/features/emergency_card/**`.

## Built
- [x] Domain (`domain/emergency_card.dart`): `EmergencyCard`, `BloodGroup` (wire `A+ … O- unknown`, lenient parser),
      `EmergencyContact`, `EmergencyCardLimits` (20 × 80, 5 contacts, notes 500, text 100, relation 60, phone 32),
      `EmergencyCardSection` + `EmergencyCardCompleteness`. Defensive `fromJson`; `toUpdateJson()` sends only the
      editable fields (trimmed, deduplicated, blank contacts dropped); `sameContentAs` for unsaved-change checks.
      `toString` contains no health data.
- [x] Repository (`data/emergency_card_repository.dart`): `GET` / `PUT /family/members/:id/emergency-card` +
      `emergencyCardRepositoryProvider`.
- [x] Offline copy (`data/emergency_card_offline_store.dart`): see the decision below. Also caches a minimal member
      directory so the list works offline, and wipes everything when the signed-in account changes during a run.
- [x] `emergencyCardProvider(memberId)` (`application/emergency_card_providers.dart`, `AsyncNotifierProvider.family`):
      caches every loaded card; on network / timeout / 5xx it returns the offline copy (`card.isOfflineCopy`,
      `card.offlineSavedAt`). On a cold start with a slow network the copy appears after 3 s and is replaced when the
      fresh card arrives. A fresh in-memory card is never downgraded to the copy. `NOT_FOUND` deletes the copy.
      Watches `sessionUserIdProvider` + `DataScope.emergencyCards`, retry = `apiRetryPolicy`.
- [x] `emergencyCardMembersProvider` (members with offline fallback), `emergencyCardMemberProvider(id)`,
      `canEditEmergencyCardProvider(id)` (self or admin), `EmergencyCardSaveController` (busy state, double-submit
      guard, phone normalisation incl. native digits, refreshes the offline copy, `markChanged({DataScope.emergencyCards})`).
- [x] `EmergencyCardsScreen` (`/emergency-cards`): every member with avatar, "Me" chip, blood group badge,
      completeness bar ("3 of 4 key details" / "Missing: …"), offline-copy chip, per-tile loading / error, pull to
      refresh, and a call button for the country emergency number.
- [x] `EmergencyCardScreen` (`/emergency-cards/:memberId`): `EmergencyCardView` + "Show to responder" + Edit
      (self / admin) + pull to refresh + `OfflineBanner`.
- [x] `EmergencyCardView(card:, member:, onEdit:)` (public, `presentation/widgets/emergency_card_view.dart`): large
      blood group badge, allergies as warning chips, medications, conditions, contacts and doctor with Call buttons,
      insurance with Copy for the policy number, notes, last updated, the disclaimer and the offline hint.
      Empty cards show a "Fill in card" call to action when `onEdit` is given.
- [x] `EmergencyCardResponderScreen`: full-screen maximum-contrast view (`ColorScheme.fromSeed(sos, contrastLevel: 1)`),
      large type, full-width call buttons. Opened as a full-screen dialog (a view mode of the card, not an `AppRoutes`
      location).
- [x] `EmergencyCardFormScreen` (`/emergency-cards/:memberId/edit`): disclaimer + privacy note, blood group dropdown,
      `ChipListField` for allergies / medications / conditions (add / remove, max 20 × 80, duplicates rejected, typed
      but unadded text is kept on save), doctor, insurance, up to 5 contacts (name, phone, relation) with add / remove
      and the "let them know" hint (compliance GAP-12), notes ≤ 500 with a counter, pinned Save button with busy state,
      discard-changes confirmation, permission empty state, offline-copy warning.
- [x] Routes `emergencyCardRoutes` (3 top-level `GoRoute`s using `AppRoutes` constants).
- [x] Mock (`data/emergency_card_mock_handlers.dart`): GET returns the contract empty card when none is saved; PUT is
      self or admin, validates every limit, rejects unknown fields (strict like zod), normalises phones and replaces the
      card. Other family → 404. Seeds: Amit (B+, peanut allergy, Priya as contact) and Kamla (O+, Metformin,
      type 2 diabetes, Dr. Rao, Star Health, two contacts). `serializeMockCard` / `emptyMockCard` are public for reuse.
- [x] `l10n_parts/emergency_card.arb`: 70 `emergencyCard*` keys with descriptions and placeholders.
- [x] Tests (71): model parsing and serialisation, mock handlers (seeds, empty card, 404, 401, 403, limits, strict
      fields), offline store (secure vs. LocalCache split, account isolation, logout invalidation, orphan purge, corrupt
      data, broken keystore), providers (offline fallback, 5xx, cold-start slow network, slow refresh, NOT_FOUND,
      markChanged, account-change wipe, save controller normalisation / busy / errors), widget tests (list, card,
      call / copy, permissions, empty card, offline hint, responder view, RTL + 1.4× text, form save / validation /
      server error / discard / no permission).

## Decision: where the offline copy lives
The task says "cache in LocalCache (key `emergencyCard.<memberId>`)". `docs/08-COMPLIANCE.md` §3 row 19 says health
data must never be cached unencrypted on the device ("if an offline copy is added, use secure storage"), and TASKS
EMC-11 says the same. SharedPreferences is plain text, so I split it:
- The card (health data) goes to `flutter_secure_storage` under `familyhub.emergencyCard.<memberId>`, together with the
  user id it belongs to.
- A marker with no health data goes to `LocalCache` under `emergencyCard.<memberId>`. Its timestamp is the "offline
  copy from …" time. Because `SessionController` clears `LocalCache` on logout, expiry and account switch, a missing
  marker invalidates the secure copy: it is deleted on the next read, and orphans are purged once per run before the
  first read or write.
- The store also calls `clearAll()` itself when `sessionUserIdProvider` changes to another value or to `null`.

## Pending / handoffs
- [ ] (f-settings / whoever owns `SessionController`) Optional: call
      `ref.read(emergencyCardOfflineStoreProvider).clearAll()` during logout / account deletion for an immediate wipe,
      even if the store was never created in that run. Today the wipe happens on the account change (if the store
      exists) or at the next app start (orphan purge).
- [ ] (f-family mock) `DELETE /family/members/:id` should also remove that member's `MockDb.emergencyCards` doc
      (contract cascade). `DELETE /me` too (f-settings mock). `GET /me/export` can use `serializeMockCard`.
- [ ] (f-home / f-settings / f-family / f-sos) Link to the cards so they are within two taps of home: More screen →
      `AppRoutes.emergencyCards`, member detail → `AppRoutes.emergencyCard(id)`, SOS alert screen may embed
      `EmergencyCardView(card:, member:)` via `ref.watch(emergencyCardProvider(memberId))`.
- [ ] (shared) `membersProvider` has no offline fallback. I worked around it inside the feature
      (`emergencyCardMembersProvider`); other features would benefit if the shared provider had one.
- [ ] Translations of the `emergencyCard*` keys (translation agents).
- [ ] Backend `emergencyCards` module (b-* agent): the mock mirrors the limits in
      `family_hub_backend/src/models/enums.js` and a strict schema; keep them in sync.

## Known issues / notes
- Riverpod 3 pauses providers without listeners. Read `emergencyCardProvider(id).future` while something watches the
  provider, as every screen does, or the retry of a failing request waits.
- The responder view cannot keep the screen awake (no wakelock package; adding packages was out of scope).
- The completeness indicator counts 4 key details (blood group, a callable contact, doctor, insurance). Allergies,
  medications and conditions are not counted, because "none" is a valid answer.

---

## Hardening review (f-emergency-harden)

Reviewer and hardener pass over the whole feature, with the same file ownership. Details and the full edge-case table
are in `docs/progress/f-emergency-harden.md`. Summary of the changes:

- **Contract**: paths, methods, field names, blood-group wire names and error codes are correct. Nothing is
  paginated.
- **Mock now matches the backend** (`family_hub_backend/src/modules/emergencyCards`):
  - Unknown and read-only keys are removed. Before, they were rejected with 422.
  - Checks run in this order: 400 (malformed id) → 422 → 404 → 403. Before, there was no 400 and 422 came last.
  - Blood groups are matched ignoring case, spaces and dash style.
  - List items are cleaned up: blank items are dropped, and case-insensitive duplicates are removed before the
    20-item limit applies. There is a cap of 100 raw entries.
  - Text is cleaned up: line breaks become spaces (`notes` keeps `\n`), control characters and bidi controls are
    removed, and text that is only invisible characters counts as blank.
  - The phone separators are the backend's.
  - The limits come from `EmergencyCardLimits`, so they are defined once.
- **Offline copy and session**:
  - Saves check the live session when they write, and all writes run one at a time. So a request that finishes
    after logout can no longer leave health data in the keystore. The old `ref.listen` wipe did not fire while
    nothing was listening to the provider, because Riverpod 3 pauses those listeners.
  - A copy whose time is in the future (the device clock was set back) is shown with the current time.
- **Provider**:
  - Each build now keeps its own `Ref`. `ref` always points at the newest build, so `ref.mounted` stayed true after
    an account switch. Late results of an old build no longer reach the state or the store.
  - An offline copy refreshes by itself when the connection returns.
  - `refreshIfStale()` fetches the card again in the background when it is older than 1 minute or is an offline
    copy. The card screen and the list tiles call it, and it does nothing while a request is still running.
- **Save**:
  - `FORBIDDEN` or `NO_FAMILY` re-reads the session, so the form shows the "no permission" state.
  - `NOT_FOUND` triggers `markChanged({members, emergencyCards})` and deletes the offline copy.
- **UI**:
  - A `NOT_FOUND` card or form shows `EmergencyCardUnavailable` (Back, or All emergency cards) instead of an error
    with a Retry that can never succeed.
  - The form takes a newer card when nothing has been edited yet (for example, the fresh card that replaces an
    offline copy). If the user has already edited, the form keeps their edits and warns that saving replaces the
    newer version.
  - The responder view updates to the live card.
  - Rapid taps no longer open two responder views or push the same route twice.
  - After a save, a form opened from a deep link goes on to the card.
  - A contact without a name is shown as "Contact N".
  - The list separator and "name · relation" are now localized (6 new keys).
- **Tests**: 71 → 104. The new file `emergency_card_edge_cases_test.dart` has 18 widget tests. The provider, store and
  mock tests are extended.

### Status of the builder's handoffs (checked 2026-09-27)
- [x] The f-family mock deletes the card in `DELETE /family/members/:id` (`family_mock_handlers.dart`).
- [x] The f-settings mock `GET /me/export` uses `serializeMockCard`, and `DELETE /me` removes the card.
- [x] The More screen links to `AppRoutes.emergencyCards`, and the member detail screen links to
      `AppRoutes.emergencyCard(id)`.
- [ ] SOS alert screen embedding `EmergencyCardView` (f-sos).
- [ ] Session owner: an optional immediate `clearAll()` on logout. Less important now that saves check the live
      session.
