# rd-settings — "Modern & Colourful" redesign of the settings feature

Owner: rd-settings · Scope: `family_hub_app/lib/features/settings/presentation/**`,
`family_hub_app/l10n_parts/settings.arb` (new keys only), `family_hub_app/test/features/settings/**`.
Spec: `docs/12-DESIGN_LANGUAGE.md`, `docs/05-FLUTTER_GUIDE.md` §3–4. Reference: `lib/features/dashboard/presentation/**`.
Presentation only — providers, repositories, domain models, routes and mock handlers are unchanged.

## Redesign

### Done
- [x] **More tab** (`screens/more_screen.dart`): no app bar any more. `GradientHeaderScrollView` with
      `AppGradients.brandHeader` — full-bleed gradient that starts **behind a transparent status bar**
      (status-bar icons switch automatically), rounded bottom, pull to refresh, bottom padding clears the
      floating nav bar.
  - [x] Header (`widgets/profile_header.dart`): small "More" label, avatar in a frosted halo + white ring
        (no border stroke), name, designation (or role), family name, frosted "Edit profile" pill. The whole
        block is one tap target / one screen-reader button (hint "Opens your profile"). Without a family it
        shows the account email and is not tappable.
  - [x] 2×2 solid `ActionTile` shortcuts overlapping the header (`widgets/settings_shortcuts.dart`):
        Members blue, Notice board amber, Emergency cards rose, SOS history red; one row of four when the
        content is wide enough (scaled by text size). Hidden without a family (then the header has no overlap).
  - [x] Grouped borderless cards with solid `IconBadge` rows: Family (admins: Family settings, blue),
        Preferences (language sky, appearance violet, location teal, notifications amber), Account
        (password indigo, privacy emerald, about blue). Current value at the end + `AppIcons.chevron`.
  - [x] Log out as a soft red card row (busy spinner, confirm dialog unchanged); version line.
- [x] **Shared rows** (`widgets/settings_section.dart`): `SettingsSection` (optional `SectionHeader` with
      icon/accent, borderless `AppCard`, hairline dividers inset past the badge, optional `tint`) and
      `SettingsTile` (solid badge, title, subtitle, **value** at the end, chevron / custom trailing, busy,
      disabled, destructive = SOS red). The value is measured: if title + value don't fit on one line
      (large text, long translations) it moves **below** the title instead of breaking words.
- [x] **Pushed screens chrome** (`widgets/settings_page.dart`): `SettingsPage` = canvas app bar (theme,
      transparent status bar) + `ResponsiveCenter`; `SettingsListView` / `settingsListPadding` add the bottom
      safe-area inset so lists scroll edge to edge behind the gesture bar.
- [x] **Appearance**: three visual theme cards (Same as phone / Light / Dark) with mini previews (canvas +
      card + text lines + brand accent swatch/pill, drawn from the *other* theme's tokens via
      `AppSemanticColors.of(brightness)`; "Same as phone" is split light/dark, RTL-aware). Selected card is
      tinted violet with a solid check; radio semantics (`checked` + `inMutuallyExclusiveGroup`). Large-text
      switch with a sky badge and the live `TextSizePreview` card (amber notice badge).
- [x] **Language**: device-language card (sky badge, tint fills the card when chosen) + list card; native name
      big (`titleMedium`, with its locale), English name small; chosen row tinted with a solid **indigo** check
      circle (`widgets/selection_check.dart`, animated, reduced-motion aware).
- [x] **Location sharing**: solid teal `GradientCard` "Your family can see your location" with a frosted
      "Share now" button (spinner, no double submit); three option cards with solid badges (never indigo,
      SOS red, always teal) + description, selected tinted + checked, saving card shows a spinner, others
      dimmed while busy; amber-tinted permission notice; "How it works" card with soft badges.
- [x] **Privacy**: emerald consent card, legal links, "Your data" export row, leave family / delete account on
      soft red cards (danger zone).
- [x] **About**: brand `GradientCard` hero (app mark, name, version, mission), "Good to know" disclaimer cards
      with solid badges (SOS red + danger call button, medical rose, ledger emerald), "Legal & contact" rows.
- [x] **Change password**: two `AppCard` sections with `SectionHeader`s ("Confirm it's you", "Choose a new
      password"), rules hint with a thin info icon, one gradient primary button.
- [x] **Profile**: "About you" card section for the form fields, read-only email / title / role as badge rows in an
      "Account" section, primary save button.
- [x] **Data export**: summary as badge rows in each module's accent (`DataExportSection.accent`), borderless JSON
      block on the card surface, bottom inset added to the sliver padding.
- [x] l10n: 6 new keys in `l10n_parts/settings.arb` (`settingsEditProfile`, `settingsProfileSectionPersonal`,
      `settingsPasswordSectionCurrent`, `settingsPasswordSectionNew`, `settingsAboutGoodToKnow`,
      `settingsAboutLegal`), merged with `dart run tool/l10n.dart`.
- [x] Tokens only (no `Color(0x…)`, no `Colors.*` except white/transparent on gradients, no raw sizes / fonts),
      `AppIcons` only, `…Directional` paddings, no fixed text heights, ≥ 48 dp rows.
- [x] Tests: 130 → 132. Logout finder updated (was `OutlinedButton`, now the red card row). New: More without a
      family; large-text value moves below the title. Appearance test also asserts the radio semantics of the
      theme cards. Visual check: rendered every screen in light + dark, RTL + 1.6× text and no-family to PNGs
      with a throw-away golden test (deleted afterwards).

### Pending / known issues
- [ ] Material 3 `Switch` (large-text switch) still draws its track outline when off — a theme-level
      `switchTheme.trackOutlineColor` change in core would remove it (handoff).
- [ ] Only the More tab is in this feature; the other tab screens' status bars belong to their features.
- [ ] Private widgets that could be promoted to core by visual QA: `SettingsTile`/`SettingsSection`
      (badge list rows with measured inline/stacked value), `SelectionCheck`, `SettingsPage`/`SettingsListView`,
      the frosted `_GlassButton` / `_GlassPill` / `_FrostedIcon` (location screen / profile header), the
      shortcut `_Grid` (duplicate of `DashboardLayout.grid`).
