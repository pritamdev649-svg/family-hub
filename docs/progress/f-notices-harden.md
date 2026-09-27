# Progress · f-notices-harden (review + hardening of the Flutter notice board)

Owner files (same as f-notices): `family_hub_app/lib/features/notices/**`, `family_hub_app/l10n_parts/notices.arb`,
`family_hub_app/test/features/notices/**`. Details of every finding are in `docs/progress/f-notices.md`
("Hardening review").

## Done
- [x] Contract conformance: repository calls and mock handlers vs contract §9 and the backend module.
      Mock fixed to match the backend: check order, `pinned: null` → 422, unchanged PATCH keeps `updatedAt`,
      removed/moved authors → `authorName: null`.
- [x] Guide conformance: tokens only, no user-visible literals, RTL-safe paddings, `AsyncValueView` everywhere,
      `markChanged` after mutations, `mounted` checks after awaits, busy guards. Minor fixes in the action sheet.
- [x] Edge-case sweep (23 cases, see below) with code fixes and tests.
- [x] New widget `presentation/widgets/notice_photo_field.dart` (upload-aware photo field) and helper
      `presentation/widgets/notice_route_guard.dart` (`isNoticeRouteCurrent`).
- [x] Tests: 81 → 109 (`notice_card` 7, `notice_form_screen` 17, `notice` 16, `notices_controller` 25,
      `notices_mock` 26, `notices_screen` 18). The route-guard tests were checked to fail without the guard.
- [x] Verified: `dart run tool/l10n.dart` OK, `dart analyze lib/features/notices test/features/notices` no issues,
      `flutter test test/features/notices` 109 passed, `dart analyze lib` no issues,
      `flutter test test/app_smoke_test.dart` passed.

## Edge cases (status)
| # | Case | Handling |
|---|------|----------|
| 1 | Offline first load | ErrorView + Retry (transient errors retried twice) |
| 2 | Offline refresh with data | data kept + "offline" notice (AsyncValueView) |
| 3 | Offline / timeout on load more | snackbar, loaded notices kept, button to retry |
| 4 | POST response lost (timeout) | lookup of the just-posted notice → no duplicate (new) |
| 5 | Still offline during that lookup | original error, board refetch (new) |
| 6 | 401 expiry mid-action | interceptor refresh + retry; on failure session ends; `mounted` guards; logout resets board and busy set (test added) |
| 7 | 403 for non-admin (pin / others' notice) | actions hidden; server 403 shown localized |
| 8 | 404: pin/unpin a deleted notice | card removed + "deleted in the meantime" (new) |
| 9 | 404: delete an already deleted notice | counts as deleted |
| 10 | 404: save an edit of a deleted notice | message + form closes (new) |
| 11 | 404: link opens a deleted notice | "no longer available" + Back, no Retry (new) |
| 12 | 422 validation | messages under the fields; mock parity for `pinned: null` (new) |
| 13 | Concurrent edits (no 409 in §9) | PATCH sends only changed fields, so others' changes are not overwritten |
| 14 | Empty board / page past the end | EmptyState with call to action; empty page, `hasMore: false` |
| 15 | Very long names, titles, unbroken text, 1.4–1.6× text, RTL | wraps / ellipsizes, no overflow (test added) |
| 16 | Emoji / Devanagari / Arabic at the limits | UTF-16 limit enforced like the backend (tests added) |
| 17 | Clock skew / day boundaries | future `createdAt` → "Just now" (new); local-day "Yesterday" via `Fmt` |
| 18 | Renamed / removed author | refetch on `DataScope.members` (new); "Former member" |
| 19 | Rapid repeated taps | busy guards; FAB / CTA / menu / photo open once (new); Post once (test added) |
| 20 | Stale data from other members | refresh on return from background (new), pull-to-refresh, refetch after remote deletions while paging (new) |
| 21 | Pagination end | no further requests |
| 22 | Permission change while open | reactive permissions; submit re-reads `canPin`; server 403 handled |
| 23 | Save / leave while photo uploads | refused with message / asks to discard (new) |

## Pending / handoffs
- [ ] Core widgets owner: `ImagePickerField` could expose `onBusyChanged`; `NoticePhotoField` could then drop its
      service wrapper.
- [ ] Core widgets owner: `AppTextField` counter counts characters while the API counts UTF-16 code units (emoji).
- [ ] Push / app owner: on a foreground `notice` push, call `markChanged({DataScope.notices})` so an open board
      updates without waiting for resume or pull-to-refresh.
- [ ] Carried over from f-notices: dashboard `latestNotices` / `NoticeCard(compact: true)`; settings export helper.

## Known issues
- Relative times don't tick while the board stays open.
- Remote pin/unpin between two page loads can still shift offsets without changing the total.
- Uncertain-POST lookup assumes device and server clocks within 10 minutes and checks the newest 20 notices.
