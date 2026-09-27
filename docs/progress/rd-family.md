# rd-family — Family feature redesign ("Modern & Colourful")

Owner: rd-family · Scope: `family_hub_app/lib/features/family/presentation/**`, `l10n_parts/family.arb` (new keys only),
`test/features/family/**`. Presentation only — providers, repositories, domain, routes and mock handlers are unchanged.

## Redesign

### Built
- [x] **Transparent status bar + full-bleed gradient header** (`GradientHeaderScrollView`, `AppGradients.headerOf(AppAccents.family)`)
      on the member list and member detail. No app bar there; a frosted back button (tooltip "Back", `Navigator.maybePop`,
      shown only when there is a page to go back to, like `AppBar`) lives in the header. White status-bar icons while
      the header is behind them (core handles the switch on scroll).
- [x] **MembersScreen**: header with back + settings (frosted round buttons), family name, bold title, member count and
      three glass stats (Admins / On the app / Kids & teens). Borderless member cards overlap the header: avatar in a
      gradient **colour ring** (stable per-member accent), name `titleSmall`, designation, colourful `StatusChip`s
      (You · role with crown/user icon · age group · Invited / No account). Admin FAB in solid family blue.
      Loading / error (retry) / empty states render below the header via `AsyncValueView`; pull-to-refresh kept.
- [x] **MemberDetailScreen**: blue header with big avatar (white ring), name, designation and glass pills (You, role,
      age, account). First card overlapping the header = colourful **ActionTile grid** (Call emerald, Email sky,
      Emergency card rose, Assign task violet — shown by the same rules as before; 2 columns on phones, one row on
      wide screens). Then `SectionHeader` + `AppCard` sections **Details / Contact / Location** with solid `IconBadge`
      rows in varied accents (fintech-list look), tinted pill actions ("Change", "Open map"), tonal "Edit details" and
      danger "Remove from family". While there is no member to show (first load, error, gone) a plain canvas app bar +
      state view is used, so there is always a way back.
- [x] **MemberFormScreen**: photo picker centred on a soft blue card; sectioned `AppCard`s with `SectionHeader(icon, accent)`
      — Details (name, date of birth, gender), Contact (email + hints, phone + hint), Role in the family (designation
      with **colourful suggestion chips**, role chips / own-role note). Guardian consent is a soft amber card with a
      solid amber `IconBadge`. One gradient primary submit button at the end. Scroll padding adds the bottom inset.
- [x] **FamilySettingsScreen**: the invite code is a solid blue gradient **membership card** (family name, "Invite code",
      key glyph, big equal-width frosted code cells, frosted white Copy / New code buttons). Members get the same card
      with "Ask a family admin for the invite code." Other settings in a borderless "Family profile" card
      (admin: fields; member: country / currency / time zone `IconBadge` rows + read-only note); members row with a
      solid `IconBadge` and chevron.
- [x] Shared feature building blocks (private to the feature):
      `family_style.dart` (accent, header gradient, stable member palette, role/age-group accents, glass opacities),
      `widgets/family_glass.dart` (`FamilyHeaderBar`, `FamilyGlassIconButton`, `FamilyGlassStat`, `FamilyGlassPill`,
      `FamilyFrostedButtons`), `widgets/member_avatar_ring.dart`, `widgets/family_choice_chips.dart`
      (borderless tinted chips, solid + check when selected — visible inside cards), `widgets/family_action_grid.dart`,
      `FamilyInfoRow` now leads with a solid `IconBadge(accent:)` + `FamilyRowAction`.
- [x] Dark theme checked visually (rendered all screens light + dark with real fonts during development) and by tests.
- [x] New l10n keys (English, `l10n_parts/family.arb`): `familyStatAdmins`, `familyStatAppUsers`, `familyStatKids`,
      `familyContactSection`, `familyLocationSection`, `familyRoleSection`, `familyProfileSection`; merged with
      `dart run tool/l10n.dart`.
- [x] Tests: finder updated for the email action (`OutlinedButton` → `ActionTile`); the consent retry test now waits for
      the error snack bar to time out (it floats over the taller form's submit button — the tap used to miss silently);
      `pumpFamilyApp(theme:)` added; new `family_redesign_test.dart` (15 tests): transparent status bar + no app bar on
      list/detail, header back pops / hidden when opened directly, gone view keeps an app bar, glass stat values,
      action tiles by permission, membership card for members/admins, dark theme × RTL × 1.4× text × 360 dp on all
      six family routes.

### Pending / known issues
- [ ] Translations of the 7 new keys in `lib/l10n/app_<lang>.arb` (English fallback until then).
- [ ] When the header scrolls away, content scrolls under the transparent status bar with nothing behind the icons —
      needs a pinned canvas scrim in core `GradientHeaderScrollView` (handoff below).
- [ ] Canvas app bars (form, settings, detail loading/gone) still show Material's back arrow — needs a theme-level
      `backButtonIconBuilder` in core (handoff).
- [ ] Floating error snack bars (6 s) can cover the submit button at the bottom of long forms (app-wide, core).
- Known: white text on the header gradient's lighter start (blue-500) is ~3.7:1 — fine for the large title, borderline
  for small labels; same as the dashboard's header. The membership card uses the deeper `AppGradients.of(blue)`.

### Verification
- `cd family_hub_app && dart analyze lib/features/family test/features/family` → No issues found.
- `cd family_hub_app && flutter test test/features/family` → All tests passed (141).
