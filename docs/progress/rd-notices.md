# rd-notices — notice board redesign ("Modern & Colourful")

Owner: rd-notices · Scope: `family_hub_app/lib/features/notices/presentation/**`,
`family_hub_app/l10n_parts/notices.arb` (new keys only), `family_hub_app/test/features/notices/**`.
Presentation only: providers, repository, domain, routes and mock handlers are unchanged.

## Redesign

Trigger (user): "make status bar transparent not looking good". Spec: docs/12-DESIGN_LANGUAGE.md, module accent **amber**.

### Built
- [x] **Notice board header** (`widgets/notices_header.dart`): amber full-bleed `GradientHeaderScrollView`
      (`AppGradients.headerOf(AppAccents.notices)`) that starts behind the **transparent status bar**; no AppBar.
      Frosted back button (only when the route can pop, same rule as AppBar), family name, bold "Notice board",
      subtitle, frosted megaphone badge, two glass stat pills (notices on the board, pinned). Pills are hidden until the board loads.
- [x] **Status bar strip once scrolled** (`screens/notices_screen.dart` `_StatusBarBackdrop`): when the board scrolls,
      a strip of the same horizontal gradient fades in behind the status bar (`AppDurations.fast`, skipped with reduced motion),
      with its own `AnnotatedRegion` (transparent, white icons, `systemStatusBarContrastEnforced: false`). Cards no longer slide
      under the clock/icons, and the icons no longer flip to dark over scrolling content.
- [x] Cards overlap the header's rounded edge; loading = `AppCard(LoadingView)`, empty = borderless card with a solid amber
      `IconBadge` + copy + tonal "New notice"; error = `ErrorView` with retry (AsyncValueView unchanged).
- [x] Pagination kept: auto "load more" near the end (once per page, no retry storm), plus a "Load more" button / spinner footer.
- [x] FAB "New notice" in solid deep amber with white text (AA contrast); extra bottom room so the last card is not hidden.
- [x] **NoticeCard** (public, used on the dashboard; API unchanged): borderless `AppCard`; pinned notices on the soft amber
      accent background; avatar + author + thin clock icon + relative time; **solid amber "Pinned" pill** with white pin icon;
      extra-bold title; "Read more"/"Show less" in amber; photo with larger rounding (`AppRadius.brLg`); amber busy spinner.
- [x] **Form** (`screens/notice_form_screen.dart`): canvas app bar; fields grouped into `AppCard` sections with amber
      `SectionHeader`s ("What's new?" = title + message, "Photo (optional)" = big 168 dp soft-fill picker with hint text);
      admin "Pin to top" switch row with a solid amber `IconBadge` and amber switch; privacy hint; gradient primary submit.
- [x] Form robustness: switched from a lazy `ListView` to `SingleChildScrollView` (a field scrolled far away could otherwise be
      unregistered and skipped by validation on small phones / large text); a failed check scrolls the first invalid field into view
      (`validateGranularly` + `Scrollable.ensureVisible`, reduced-motion aware). Bottom padding adds `MediaQuery.paddingOf(context).bottom`.
- [x] `widgets/notice_style.dart`: the feature's accent, header gradient and white-text-safe solid amber in one place.
- [x] New l10n keys (notices.arb): `noticesSubtitle`, `noticesStatTotal`, `noticesSectionMessage`, `noticesPhotoHint`; merged via `dart run tool/l10n.dart`.
- [x] Tokens only (AppSpacing/AppGap/AppRadius/AppSizes/AppDurations/textTheme/colorScheme/accent); `Colors.white` only on
      gradient/solid amber; RTL (`PositionedDirectional`, mirrored `AppIcons.back`); large-text safe (no fixed text heights); 48 dp targets.

### Tests (test/features/notices) — 121 passing
- Updated for the new layout: form helper scrolls the form's `SingleChildScrollView`; the double-tap test unfocuses before scrolling.
- New: header content + back button; status bar stays transparent with white icons after scrolling (mutation-checked: fails without the strip);
  pinned card uses the amber accent; empty card badge + zero stats; failed page retried via "Load more" only; dark theme board;
  pinned pill colours; dark card with photo + long text; form sections, big picker and pin badge; first invalid field revealed
  (mutation-checked); dark theme + 1.4x text form.
- Visual check: rendered light/dark screenshots (board top, scrolled, empty, form) from a throw-away test with real fonts; removed afterwards.

### Pending / handoffs
- [ ] **core `GradientHeaderScrollView`** (`lib/core/widgets/gradient_header.dart`): its `GradientHeader` doc says it "pins a strip of
      the same gradient behind the status bar", but it doesn't. Content scrolls under the transparent status bar and icons flip to dark.
      That's likely what the user means by "not looking good" on Home/tab screens. Suggest promoting `_StatusBarBackdrop` from
      `notices_screen.dart` (fade-in strip + light-icon `AnnotatedRegion`), plus `systemStatusBarContrastEnforced: false`.
      After that, the notices screen can drop its own strip.
- [ ] **core `GradientHeaderScrollView`**: lays all children out in one `Column` (not lazy). Fine for a family board (20 per page),
      but long boards build every loaded card and image. A sliver/builder variant would let the board go back to lazy building.
- [ ] **app bootstrap** (`lib/main.dart`, owner f-core/f-shell): no `SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge)` /
      transparent `setSystemUIOverlayStyle`. On Android < 15 the status/navigation bars can keep the default translucent scrim before the first annotated screen.
      `GradientHeaderScrollView` also uses `SystemUiOverlayStyle.light/dark` as-is, so it sets a **black** system navigation bar.
- [ ] **core theme** (`app_theme.dart`): `appBarTheme.systemOverlayStyle` (transparent + contrast not enforced) and
      `actionIconTheme` back-button builder → `AppIcons.back`. Form screens still show the Material back arrow.
- [ ] **core `ImagePickerField`**: square only. A full-width 16:9 "banner" mode would match how notice photos are shown (notice form uses a 168 dp square).
- [ ] **core `PaginatedListView`**: expose its footer (spinner / "Load more") publicly; the board has a private copy (`_LoadMoreFooter`).
- [ ] Promote the frosted `_GlassStat` / glass icon button (duplicated from `DashboardHeader`) to `lib/core/widgets/`.

### Known issues
- The header stat "Pinned" counts pinned notices in the loaded window (they always sort first, so it's exact unless one page holds only pinned notices).
- When `/notices` is the only route (no back stack) there is no back button, same as before (the AppBar had none either).
