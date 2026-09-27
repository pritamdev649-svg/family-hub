# rd-emergency: emergency card redesign ("Modern & Colourful")

Owner files: `family_hub_app/lib/features/emergency_card/presentation/**`,
`family_hub_app/l10n_parts/emergency_card.arb` (new keys only),
`family_hub_app/test/features/emergency_card/**`, this file.

Only the presentation layer changed. Providers, repositories, domain models, routes, mock handlers and behaviour are
the same as before. Spec: `docs/12-DESIGN_LANGUAGE.md`, `docs/05-FLUTTER_GUIDE.md` §3–4. The reference was the
dashboard.

## Redesign

### Screens
- [x] **Status bar (the user's request).** The list and card screens have a full-bleed rose gradient header
      (`AppGradients.headerOf(AppAccents.emergency)`) behind a **transparent** status bar. The status-bar icons are
      white over the header and switch to the theme's colour once the header scrolls away. The overlay style comes from
      `AppSystemUi.forBackground` and leaves the navigation bar untouched. These screens have no app bar. The form keeps
      a plain canvas app bar, which Material 3 already makes transparent. The responder view uses its own region with
      light icons.
- [x] **EmergencyCardsScreen.** The header has a frosted back button, a glass icon, the title, the intro text and two
      glass stat pills (family members, cards complete). "In danger? Call 112" is a solid SOS-red `GradientCard` that
      overlaps the header. Each member row is a borderless `AppCard` with the avatar, name, "Me" / "Offline copy" pills,
      the designation, a completeness progress bar with an icon and label, a **solid rose blood-group pill** and a thin
      chevron.
- [x] **EmergencyCardScreen.** The header has frosted back and edit buttons, an "Emergency card" caption, the member's
      name and designation, a **huge white blood-group badge** (red symbol, `displayMedium`) and a glass completeness
      pill. "Show to responder" is a solid SOS-red card overlapping the header. The sections follow.
- [x] **EmergencyCardView** (also embedded in the SOS alert screen; the API is unchanged, plus `showHeader`). Each
      section is a borderless card led by a solid `IconBadge`: allergies amber, medications violet, conditions rose,
      contacts sky, doctor blue, insurance emerald, notes indigo. Items are soft tinted chips in the section colour.
      Allergy chips carry a warning icon. Contacts and the doctor have initials avatars and **round solid call
      buttons** (green for contacts, blue for the doctor). The policy number has a tonal round copy button. The empty
      card is a state card with a large rose badge and the single gradient primary "Fill in card".
- [x] **Responder view.** It is full screen and high contrast, and **always dark** in both app themes: the app's
      near-black canvas and charcoal cards with the highest-contrast scheme of the emergency red. The name uses
      `displaySmall` extra-bold. The blood group is a huge solid-red badge (`displayLarge`). Known allergies are a solid
      red block with extra-bold white text. Every call button is a full-width solid button with its label. The close
      bar is pinned under the transparent status bar.
- [x] **Form.** Every group is an `AppCard` section with a solid `IconBadge` header in its colour. The blood group is
      picked with **colourful chips** (soft rose, and solid deep rose with white text when chosen; symbols stay LTR)
      instead of a dropdown. The chip lists use borderless tinted `InputChip`s and a solid round add button. Contacts
      are soft sky panels inside the contacts card. The Save button (gradient primary) sits in a bottom bar with no
      divider. The app-bar back arrow is the thin Phosphor icon, set through a local `ActionIconTheme`.
- [x] States: loading, error with retry, empty and data still go through `AsyncValueView`. The empty, unavailable
      (NOT_FOUND) and no-permission states are `EmergencyStateCard`s in the module accent: in the content column under
      a header, or centred and scrollable on plain screens. The offline banner is now a rounded strip in the content
      column, because the header sits behind the status bar.

### New feature-private building blocks
- `presentation/emergency_card_style.dart`: `EmergencyCardAccents`, the accent of each section, used by the card, the
  responder view and the form.
- `presentation/emergency_card_labels.dart`: `EmergencyCardProgress` and `progress` / `progressLabel`, shared by the
  list tile and the header pill.
- `widgets/emergency_chrome.dart`: `EmergencyHeaderTopBar`, `EmergencyGlassIconButton`, `EmergencyGlassIcon`,
  `EmergencyGlassPill`, `EmergencyOfflineNotice`, `mutedOnGradient()` and `glassOnGradient()`.
- `widgets/emergency_section.dart`: `EmergencySectionTitle`, `EmergencySectionCard` and `EmergencyStateCard`.
- `widgets/emergency_header_scroll_view.dart`: `EmergencyHeaderScrollView`. It is a copy of core
  `GradientHeaderScrollView` with a **hit-test fix** (see known issues and handoffs).
- `BloodGroupBadge` has the variants `small` (solid rose pill), `large` (solid rose square), `header` (white square,
  red symbol) and `hero` (solid red, responder).
- `CardNotice` now takes an `AppAccent` (a borderless tint) instead of a `Color`.
- `ChipListField` now takes `required icon` and `required accent`.
- `CallButton` has an `accent` parameter. By default it is round and solid; `expand` gives a full-width solid button.

### l10n
- [x] New keys: `emergencyCardStatMembers` ("Family members") and `emergencyCardStatComplete` ("Cards complete"), used
      by the header stat pills. `dart run tool/l10n.dart` passes.

### Rules check
- [x] Tokens only. A grep finds no `Color(0x…)`, no `Colors.*` other than white or transparent on gradients and solid
      accents, no `Icons.*`, no `fontSize` / `FontWeight.w*`, and no raw paddings or sizes.
- [x] No borders on containers, chips or inputs. The only hairlines are the dividers between contacts inside a card.
- [x] RTL: everything uses start/end. Blood groups, phone numbers and the policy number stay LTR. Directional icons are
      mirrored.
- [x] Large text (1.4×): no fixed text heights and no overflow on a 360 dp phone in RTL. Checked on screenshots and in
      the existing long-content tests.
- [x] Tap targets are at least 48 dp, including the round call, glass and copy buttons. Icon-only buttons have
      tooltips or semantics labels.
- [x] Scroll views with an explicit padding add `MediaQuery.paddingOf(context).bottom`. The form list is the exception:
      it ends above the SafeArea'd save bar.
- [x] Dark theme: every screen was checked on rendered screenshots, light and dark.

### Tests
- [x] `emergency_card_screens_test.dart`: the two form tests used `find.byType(Card)`. `AppCard` is a borderless
      `Material` now, so they already failed before this change. They now find the contact panel by its key,
      `emergencyContactEditor-<n>`, and still test the same thing.
- [x] `emergency_card_test_utils.dart`: `pumpEmergencyApp(theme:)` is optional.
- [x] New `emergency_card_design_test.dart` (8 tests):
  - a transparent status bar with light icons over the header, dark icons after scrolling, and no navigation-bar
    override (card and list);
  - the form's app-bar status bar;
  - taps on the top edge of the cards overlapping the header ("Show to responder" and "Call 112"), as a regression
    test for the hit-test fix;
  - the responder view is dark and high contrast in the light theme;
  - the dark theme across list, card, responder and form;
  - the blood-group chips select and save the group.
- [x] 112 of 112 emergency card tests pass, and 92 of 92 SOS tests pass (SOS embeds `EmergencyCardView`).

### Pending / known issues
- [ ] **Core `GradientHeaderScrollView` hit-test bug.** The part of the content that overlaps the header (the top
      `overlap` = 32 px) does not receive taps. The header list item captures them, because the translated content
      item's box starts at the header's bottom. This also affects the dashboard's quick actions. This feature uses the
      private `EmergencyHeaderScrollView` until core is fixed (handoff).
- [ ] The emergency number card and the "Show to responder" card use core `GradientCard`. On the light canvas its glow
      shows as a soft pink band under the card. Leaving it as is keeps them the same as the other gradient cards.
- [ ] The glass opacities (0.18 fill, 0.85 muted text) are local constants, as on the dashboard. Core tokens would be
      better (handoff).
- [ ] The member list is a `Column` in the header scroll view, the same approach as the dashboard's members board.
      Families are small, so it is not lazy.

## Handoffs
1. **core (`lib/core/widgets/gradient_header.dart`)**: fix `GradientHeaderScrollView` so the overlapping content
   receives taps. Put `GradientHeader` and the `Transform.translate`d content column in **one** list item, a `Column`,
   which hit-tests its last child first. See `EmergencyHeaderScrollView` for the fix. After that, emergency cards can go
   back to the core widget: delete `widgets/emergency_header_scroll_view.dart` and rename the two usages.
2. **core (`gradient_header.dart` / `colorful.dart`)**: promote a top bar for pushed gradient-header screens, the glass
   icon button, the glass icon square and the glass stat pill. The implementations are in `widgets/emergency_chrome.dart`
   (the dashboard's `_GlassStat` is the same idea). Add glass and muted-on-gradient opacity tokens to `AppColors`.
3. **core (`lib/core/design/app_theme.dart`)**: set `actionIconTheme: ActionIconThemeData(backButtonIconBuilder: (_) =>
   const Icon(AppIcons.back))` so every `AppBar` back button uses the thin Phosphor arrow instead of Material's filled
   arrow. The emergency form sets it locally for now.
4. **core (`lib/core/widgets/state_views.dart`)**: give `EmptyState` an `accent` (a solid `IconBadge` visual, as in
   design doc §2). `EmergencyStateCard` could then shrink to a wrapper.
5. **core (`lib/core/widgets/offline_banner.dart`)**: screens whose gradient header sits behind the status bar cannot
   place the banner above the content. A rounded, inline variant would help; `EmergencyOfflineNotice` is a local
   stand-in.
