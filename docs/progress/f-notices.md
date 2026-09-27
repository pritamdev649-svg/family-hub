# Progress · f-notices (Flutter notice board)

Owner files: `family_hub_app/lib/features/notices/**`, `family_hub_app/l10n_parts/notices.arb`,
`family_hub_app/test/features/notices/**`.

## Built
- [x] **Domain** `domain/notice.dart`
      - `Notice`: contract §9 fields, defensive `fromJson` (blank image → `null`; missing `createdAt` → `updatedAt` → epoch),
        `toJson`, `copyWith` (ValueGetter for nullable fields), `==`/`hashCode`, `hasImage`, `isAuthoredBy`.
      - `Notice.compareForBoard`: the server's order (pinned first, then `createdAt` desc, ties by id).
      - Limits `Notice.titleMaxLength = 100`, `Notice.bodyMaxLength = 2000`.
      - `NoticePermissions` mirrors the backend: anyone posts; only admins pin; edit/delete for the author or an admin.
- [x] **Repository** `data/notices_repository.dart`, `noticesRepositoryProvider`
      - `list(page, limit)`, `create(NoticeDraft)`, `update(id, NoticePatch)`, `delete(id)`.
      - `findById(id)`: the contract has no `GET /notices/:id`, so it pages the board (100 per page, at most 20 pages).
        Used only by an edit screen opened without the notice in memory.
      - `NoticeDraft`: trims text and omits empty optional fields.
      - `NoticePatch` (a `PatchBody`): `.pin(bool)` and `.diff(before, …)` send changed fields only;
        `imageUrl: null` removes the photo.
- [x] **Mock** `data/notices_mock_handlers.dart`
      - `GET /notices`: paginated, pinned first, then newest.
      - `POST /notices`: `pinned` ignored for non-admins.
      - `PATCH /notices/:id`: author or admin; changing `pinned` needs an admin (403); `imageUrl: null` clears.
      - `DELETE /notices/:id`: author or admin.
      - Errors: another family's notice or an unknown id → 404; malformed id → 400; zod-like 422 with field details.
        Images must be `https://res.cloudinary.com/...`; the mock also accepts local paths, which is what uploads return in mock mode.
      - `authorName` and `authorAvatarUrl` are resolved from the member at read time. A removed author falls back to
        the stored name.
      - Seed: 4 notices by Amit and Priya.
        - Pinned: **"Family meeting Sunday 7pm"**.
        - One long notice, to show "Read more".
        - One with a Cloudinary demo photo.
      - Public helpers for other mocks: `mockFamilyNotices(db, familyId)`, `mockNoticeJson`, `compareMockNotices`,
        `seedMockNotices`, `mockPinnedNoticeTitle`.
- [x] **Application** `application/notices_providers.dart`
      - `noticeListProvider` (`NoticeListController`, state `NoticeListState {paged, isLoadingMore}`):
        - watches the session user, the family id and `DataScope.notices`;
        - pages of 20; `loadMore()` drops duplicate ids and a stale result that arrives after a rebuild;
        - a refetch reloads the whole loaded window (up to 100), so load-more progress survives a mutation;
        - `applyUpsert` / `applyRemove` update the list at once;
        - retry: `apiRetryPolicy`.
      - `noticesControllerProvider` (`NoticesController`, state = ids with a mutation in flight):
        - `create`, `update`, `setPinned`, `delete`;
        - a notice that is already busy is ignored (no double submit);
        - on success: local list update, then `markChanged({DataScope.notices})`;
        - `NOT_FOUND` removes the stale card. For delete, `NOT_FOUND` counts as success.
      - `noticeByIdProvider(id)`: from the loaded list first, otherwise `findById`.
      - `noticePermissionsProvider`.
- [x] **UI**
      - `NoticesScreen` (`/notices`):
        - `AsyncValueView` handles loading, error with retry, empty (with a call to action) and data;
        - `PaginatedListView` with load more, `AppRefreshIndicator`, `ResponsiveCenter`;
        - extended FAB → `/notices/new`;
        - cards are keyed by id.
      - `NoticeCard(notice, {onTap, showActions = true, compact = false})`, the public widget:
        - `MemberAvatar`, author name ("Former member" when unknown), relative time (tooltip with the full date);
        - "Pinned" `StatusChip` and a tinted card when pinned;
        - title as a semantics header;
        - `NoticeBodyText`: "Read more" / "Show less" only when the text really overflows at the current width, scale and direction;
        - 16:9 photo via `AppNetworkImage`; tapping opens `NoticeImageViewer` (full screen, pinch zoom, dark theme tokens);
        - menu button and long-press open a sheet: Edit (author/admin), Pin/Unpin (admin), Copy text (everyone), Delete (author/admin, with confirmation);
        - a spinner replaces the menu button while a mutation runs;
        - localized success and error snackbars stay visible after the card re-sorts or disappears (they use the root navigator's context);
        - `compact`: 3-line text, thumbnail, no LayoutBuilder (safe in intrinsic layouts).
      - `NoticeFormScreen` (`/notices/new`, `/notices/:id/edit`):
        - fields:
          - title (≤ 100, with counter);
          - message (≤ 2000, with counter; the grapheme limit plus a UTF-16 validator, like the backend);
          - `ImagePickerField(folder: UploadFolder.notices)`;
          - "Pin to top" switch, for admins only.
        - Save / Post button with a busy state, double submit prevented, fields disabled while saving.
        - Server `VALIDATION_ERROR` details show under the matching field and clear when the user edits it.
        - Edit sends only the diff; no changes means no request.
        - Unsaved changes: back asks "Discard changes?".
        - Edit uses the `extra` notice when given, otherwise a lookup with loading and error views; non-authors who are not admins see a "can't edit" state.
      - `notices_routes.dart`: `noticeRoutes` (all paths from `AppRoutes`).
- [x] **l10n** `l10n_parts/notices.arb`: 34 `notices*` keys with translator descriptions and placeholders. All are used.
      Reuses the `common*` keys for Edit, Delete, Save, Cancel, Discard and Copied.
- [x] **Tests** `test/features/notices/`: 81 tests.
      - `notice_test.dart` (16): model parsing, sort order, permissions, action menu, `NoticeDraft`, `NoticePatch.diff`.
      - `notices_mock_test.dart` (19): repository → `ApiClient` → Dio → `MockInterceptor` → handlers. Covers seed and order,
        paging, read-time author, `NO_FAMILY`, the pinned-ignored rule, 422 details, image host rules, 403/404/400,
        delete, `findById`, and serializer shape.
      - `notices_controller_test.dart` (18): `ProviderContainer` with a fake repository. Covers paging, dedupe,
        load-more failure, window refetch, signed-out state, first-load error, create/pin/delete/update, busy guard,
        `NOT_FOUND`/`FORBIDDEN` handling, empty patch, `noticeByIdProvider`.
      - `notices_screen_test.dart` (13): widget tests. Covers pinned-first badge, read more, empty, error and retry,
        admin/member menus, long-press, delete confirmation, pin re-sort with snackbar, localized error, load more,
        FAB, and RTL with 1.6× text.
      - `notice_form_screen_test.dart` (10): validation, admin pinned create and pop, member without pin, server field
        errors, edit diff, deep-link lookup, not found, not allowed, discard dialog.
      - `notice_card_test.dart` (5): full-screen photo open and close, compact mode, former member, short text.

## Verified
- [x] `dart run tool/l10n.dart`: 14 fragments merged (notices.arb 34 keys), `flutter gen-l10n` OK.
- [x] `dart analyze lib/features/notices test/features/notices`: **No issues found!**
- [x] `flutter test test/features/notices`: **81 passed**.
- [x] `dart format --set-exit-if-changed lib/features/notices test/features/notices`: clean.
- [x] A temporary test (since removed) confirmed that the real `registerAllMocks` registers the four `/notices` routes
      and seeds 4 notices.
- [x] `dart analyze lib` reports 0 issues in `features/notices`.
- [ ] The whole app (`test/app_smoke_test.dart`) currently fails to compile, because of other agents' unfinished
      `features/tasks` files (missing `tasks*` l10n keys). Not caused by this feature.

## Pending / handoffs
- [ ] Dashboard (f-dashboard): the mock `latestNotices` can use `mockFamilyNotices(db, familyId).take(3)`. The UI can use
      `NoticeCard(notice, compact: true, onTap: () => context.push(AppRoutes.notices))` and `Notice.fromJson`.
- [ ] Settings mock `/me/export` "notices authored": `mockFamilyNotices(db, familyId).where((n) => n['authorId'] == memberId)`.
- [ ] Backend notices module (to match the app and mock):
      - `PATCH` accepts `imageUrl: null` to remove the photo;
      - a non-admin `PATCH` that changes `pinned` → 403 `FORBIDDEN` (the same value is a no-op);
      - `POST` silently ignores `pinned` for non-admins;
      - a malformed id → 400.
- [ ] Core widgets (`ImagePickerField` owner): expose the upload busy state (e.g. `ValueChanged<bool>? onBusyChanged`).
      Today a notice saved while its photo is still uploading is posted without the photo.

## Known issues / decisions
- There is no `GET /notices/:id`. The edit screen gets the notice through `extra`, then the loaded board, then a paged
  lookup (`findById`).
- A mutation refetches page 1 with a limit equal to the number already loaded (at most 100), not only 20. This keeps
  scroll and load-more progress. Beyond 100 loaded notices the window shrinks to 100.
- "Copy text" is offered to everyone, so the menu button always appears. Long-press opens the same sheet (text is not
  selectable, because long-press is taken).
- The mock does not simulate `notice` push notifications.
- The relative time ("2 hours ago") is computed at build time and does not tick live.
- The seed photo uses Cloudinary's public demo image (`res.cloudinary.com/demo/.../sample.jpg`). Offline, it shows the
  broken-image placeholder.

## Hardening review (f-notices-harden)
Reviewed against contract §9, the backend notices module (`family_hub_backend/src/modules/notices/**`) and the
Flutter guide. Tests: 81 → **109**, all passing.

### Contract / backend parity (mock)
- [x] Check order now matches the backend routes: 401 → 403 `NO_FAMILY` → 400 malformed id → 422 → 404 → 403
      (`PATCH` / `DELETE` used to answer 400 before `NO_FAMILY`).
- [x] `pinned: null` (or any non-boolean) → 422 on `POST` and `PATCH`, like zod `z.boolean().optional()`.
- [x] An unchanged `PATCH` writes nothing and keeps `updatedAt`; only differing fields are written.
- [x] `authorName` / `authorAvatarUrl` are `null` once the author is no longer a member of the notice's family
      (the backend's `memberDirectory` behaviour); the mock used to fall back to a stored name. The mock no longer
      stores `authorName` on notice documents (the backend model has no such field).
- [x] Repository paths, methods, JSON names and pagination meta re-checked: no change needed.

### Edge cases fixed
- [x] Timeout / dropped connection on `POST` (response lost, notice created): `create` looks for the member's own
      matching notice among the newest ones and treats it as posted, so a retry cannot duplicate it. Not found →
      original error + board refetch.
- [x] Saving while the photo is still uploading: refused with "Please wait until the photo has finished
      uploading." Leaving during an upload asks to discard. (`NoticePhotoField` wraps `ImagePickerField` and
      tracks uploads through a nested `cloudinaryServiceProvider` override. This closes the earlier gap.)
- [x] Edit saved after someone else deleted the notice: "This notice was deleted in the meantime." and the form
      closes. Pin/unpin of a deleted notice shows the same message (the card is removed).
- [x] Link / restored route to a notice that no longer exists: "This notice is no longer available" with Back
      (home when there is nothing to go back to) instead of an error with a pointless Retry. Network errors keep
      Retry.
- [x] Deletions elsewhere while paging: when the server total shrinks, `loadMore` reloads the whole window so no
      notice is skipped (insertions were already de-duplicated).
- [x] Renamed / removed members: the board also refetches on `DataScope.members`.
- [x] Stale board: refreshes when the app returns from the background while the board is visible (not when only a
      system dialog or the notification shade covered it).
- [x] Rapid taps: a second tap on the FAB, the empty-state button, the menu / long-press or the photo while the
      first one's page, sheet or viewer animates in is ignored (`isNoticeRouteCurrent`).
- [x] Device clock behind the server: a just-posted notice reads "Just now" instead of "Today".
- [x] Clipboard failure on "Copy text" shows an error instead of an uncaught exception.
- [x] Guide nits: action-sheet colours via `ListTile.iconColor/textColor` (no ad-hoc `TextStyle`),
      `EdgeInsetsDirectional`.

### New l10n keys (notices.arb, 38 keys, all used)
`noticesPhotoUploading`, `noticesGone`, `noticesNotFoundTitle`, `noticesNotFoundMessage`.

### Known issues (unchanged / accepted)
- [ ] The field counter counts characters (grapheme clusters) while the server counts UTF-16 code units: text
      with many emoji can show "1500/2000" and still fail the 2000 limit. The validator catches it before sending.
- [ ] Relative times ("5 minutes ago") do not tick while the board stays open; they update on refresh / resume.
- [ ] A notice unpinned or pinned by someone else between two page loads can still shift offsets without
      changing the total, so one notice may be skipped until the next refresh (duplicates are already removed).
- [ ] The uncertain-POST lookup needs device and server clocks within 10 minutes and only checks the newest 20
      notices (pinned ones first).
