# f-domain: Flutter shared domain (models, repositories, session)

Owner files: `family_hub_app/lib/shared/**`, `family_hub_app/l10n_parts/shared.arb`, `family_hub_app/test/shared/**`.

## Built

- [x] `lib/shared/json.dart`: defensive parsers from §5 (`parseDate`, `parseDateOr`, `asString(Or)`, `asDouble`, `asInt`, `asBool`, `asList`, `asStringList`, `asMap`, `enumByName` (accepts snake_case / kebab / any case), `isoOrNull`). Extras: `asNonEmptyString`, `asDoubleOrNull`, `asMapList`, `enumByNameOrNull`, `enumWireName` (`sosOnly` → `sos_only`), and `calendarDate` (the viewer-independent calendar day of a date-only wire value).
- [x] Models (`lib/shared/models/`, barrel `models.dart`), each with fromJson/toJson/copyWith/==/hashCode:
  - `Member` + `MemberRole`, `LocationSharingMode` (wire `never|sos_only|always`; unknown → `never`), `Gender` (nullable), `AgeGroup` (<13, 13–17, 18–59, 60+). Getters `age`, `ageOn(date)`, `ageGroup`, `birthDate`, `isAdmin`, `isManagedProfile`, `initials` (grapheme-aware, so Indic and Arabic scripts work), `isMinorIn(CountryInfo)`, plus `Member.compare` (the server's sort order).
  - `GeoPoint` (`tryParse` rejects out-of-range values, `listFrom` drops bad points).
  - `AuthUser`, `Family` (country/currency upper-cased, currency falls back to the country default), `SessionState` (`isSignedIn`, `needsEmailVerification`, `needsFamily`, `isComplete`, `isAdmin`, `signedOut`).
  - `AuthTokens` is re-exported from `core/storage/auth_tokens.dart`, which f-core owns as the single tokens model.
  - Nullable fields in `copyWith` take `ValueGetter`, so they can be cleared: `copyWith(phone: () => null)`.
- [x] Repositories (`lib/shared/data/`), following contract §4–6 exactly:
  - `AuthRepository`: register, login (tokens saved through `TokenStorage`), logout (best effort, 8 s limit, always clears tokens), verifyEmail, resendVerification (returns the cooldown in seconds), forgotPassword, resetPassword, changePassword, me, hasTokens, clearTokens. DTOs: `RegisterRequest.create/.join`, `AuthResult`.
  - `FamilyRepository`: createFamily, joinFamily, getFamily, updateFamily, regenerateInviteCode, getMembers, getMember, addMember, updateMember, deleteMember. DTOs: `CreateFamilyRequest`, `FamilyPatch(.diff)`, `NewMemberRequest`, `MemberPatch(.diff)` + `MemberPatchField`.
  - `MeRepository`: updateMe, updateLocation (validates coordinates), registerDevice, unregisterDevice, exportData, deleteAccount, leaveFamily. DTOs: `MePatch(.diff)` + `MePatchField`, `DevicePlatform`.
  - `repository_utils.dart`: `requireObject`/`optionalObject`/`requireList` (a response with the wrong shape → `ApiException(UNKNOWN)`), `pathId` (URL-encodes ids; a blank id → `NOT_FOUND`), normalisers for email, phone, invite code and OTP, `PatchBody`, `PatchDiff`.
- [x] `SessionController extends AsyncNotifier<SessionState>` (`sessionControllerProvider`):
  - Restore: tokens → `/auth/me`. On network or 5xx it falls back to the cached `session.last` and retries in the background (10 s, 30 s, 1, 2, 5 min). A 401 signs out. Without a cache, transient errors are retried and then the provider goes to `AsyncError`.
  - Methods: `login`, `register`, `logout`, `refreshMe`, `verifyEmail`, `resendVerification`, `createFamily`, `joinFamily`, `applyMe([user, member, family])`, `handleSessionExpired` (listens to `AuthEvents.sessionExpired`). Extras: `leaveFamily`, `deleteAccount(password)`.
  - Actions never set `AsyncLoading`. They set `AsyncData` on success and rethrow `ApiException` on failure.
  - Push: `registerDevice()` runs once per session after sign-in or online restore, fire-and-forget. Logout calls `unregisterDevice()`, then `POST /auth/logout`, then clears tokens and `LocalCache`, then signs out. On session expiry the state goes to signed out first, then cleanup runs, so there is no 401 loop. A new registration waits for any pending unregistration.
  - An epoch guard drops late background results that belong to an earlier session.
  - The member's `lastLocation` is never written to disk.
  - When the family id changes, every `DataScope` is bumped. When the member or family changes, `members`/`family` are bumped.
- [x] Derived providers: `currentUserProvider`, `currentMemberProvider`, `currentFamilyProvider`, `isAdminProvider`, `currentCountryProvider`, `sessionUserIdProvider`.
- [x] `membersProvider` (watches the user id, the family id and `DataScope.members`) and `memberByIdProvider` (served from the members list first; unwraps Riverpod's `ProviderException`).
- [x] `apiRetryPolicy`: Riverpod 3 otherwise retries 10× while showing `AsyncLoading`, about 40 s of spinner for a 403 or 404. This policy retries only connection errors and 5xx, twice.
- [x] Data-change bus `lib/shared/providers/data_refresh.dart` (§10): `DataScope`, `dataRefreshProvider`, `markChanged(Ref, …)`, `WidgetRef.markChanged(…)`, `markAllChanged()`.
- [x] `l10n_parts/shared.arb` (19 keys, merged into `app_en.arb`) and `lib/shared/l10n/shared_labels.dart`:
  - `label`/`description`/`icon` for `MemberRole` and `LocationSharingMode`.
  - `label` for `Gender` and `AgeGroup`, plus `Gender?.labelOrUnspecified`.
  - `Member.ageLabel` (uses the `ageYears` plural) and `Member.titleOrRole`.
- [x] Barrels: `lib/shared/shared.dart` and `models/models.dart`. `session_controller.dart` and `shared_providers.dart` re-export each other, so either import gives the whole session API.
- [x] Tests in `test/shared/` (87 total): json, models, repositories/DTOs, session controller, data bus, labels.

## Pending

- [ ] Run `flutter test test/shared` in the real project once the feature `*_mock_handlers.dart` files exist. Today `core/network/mock/mock_registry.dart` imports them, so the `core_providers` graph can't compile. Until then the suite passes in a scratch copy with stub handler files; the 4 test files that don't need that graph pass in the real project.
- [ ] Widget-level check of the labels in RTL / large text. They are plain strings, so there is no layout risk.

## Known issues and decisions

- Register sends `family: null` (join mode), `inviteCode: null` (create mode) and `dateOfBirth: null`, following the contract example. The backend should accept these as nullish.
- `MemberPatch` does not send `locationSharing`. Location sharing is member-controlled only, through `PATCH /me` (privacy by design).
- Date-only values (`dateOfBirth`) are read with `calendarDate`, which rounds to the nearest UTC midnight. Only time-zone offsets beyond ±12 h can shift the shown date by one day.
- Offline start with tokens but no cached session: after the retries, the router treats the user as signed out. Tokens are kept, so the next start or login works.
