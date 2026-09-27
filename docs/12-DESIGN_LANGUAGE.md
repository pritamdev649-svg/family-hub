# 12 · Design Language — "Modern & Colourful"

The product owner's direction: **modern, colourful, thin outline icons, NO borders around containers,
and a first-class dark theme** (reference: dark fintech UI — near-black canvas, charcoal borderless cards,
solid saturated colour cards with white text, solid colour icon squares). The Home dashboard
(`lib/features/dashboard/presentation/`) is the reference implementation — every screen must feel like it
belongs next to it. All tokens live in `lib/core/design/`, all building blocks in `lib/core/widgets/`.
Rules from `05-FLUTTER_GUIDE.md` still apply (tokens only, DRY, l10n, RTL, large text, states).

## 1. Visual principles

1. **Soft canvas, borderless cards.** Page background = `semanticColors.canvas` (theme does this). Content sits in
   `AppCard`s: white with a very soft shadow in light mode, charcoal (`#1B1C21`) on near-black (`#0E0F12`) in dark
   mode — **never a border/outline around a container, chip, input, tile or button**. Separation comes from surface
   colour, shadow (light only) and spacing. Hairlines are allowed only as dividers *inside* a card.
2. **Colour = meaning.** Each module owns one accent (`AppAccents`): tasks **violet**, money **emerald**
   (income emerald, expense **rose**), goals **pink**, notices **amber**, SOS **red**, emergency card **rose**,
   family **blue**, settings **sky**, home/brand **indigo**. Use the accent for that module's icon badges, section
   header icons, highlights, progress bars, chips and hero gradient. Mixing is fine on the dashboard / More screen
   (each tile in its module's accent).
3. **Thin icons only.** `AppIcons.*` are Phosphor **Light** outline glyphs. Never `Icons.*`, never filled icons.
   Icons that need emphasis go inside an `IconBadge` — by default a **solid accent square with a white thin icon**
   (like the reference's transaction list); `soft: true` = pale tint for dense/secondary use.
3b. **Solid colour cards.** Highlight cards (quick actions, goals, category totals, member cards on the board when
   emphasised) may be solid accent gradients with white text (`ActionTile`, `GradientCard(gradient: AppGradients.of(a))`),
   like payment cards. Use them for 2–4 items per screen, not for every list row.
3c. **Dark theme is first-class.** Every screen must look intentional in dark mode (Settings → Appearance →
   System/Light/Dark; follows the OS by default). Only use theme/semantic/accent colours so both modes work;
   check contrast of accent text in dark (`AccentShades.foreground` switches to the light shade).
4. **One gradient hero per main screen.** Tab screens and key detail screens open with a `GradientCard` headline
   (white text) summarising the screen: Home greeting (brand), Tasks progress (`AppGradients.tasks`), Money month
   balance (`AppGradients.money`), SOS state (`AppGradients.sos`), More/profile (brand), Emergency card (`AppGradients.emergency`),
   Member detail (`AppGradients.family`), Goal detail (`AppGradients.of(AppAccents.goals)`), Notice board (`AppGradients.notices`).
   Keep heroes compact (≤ ~40 % of the viewport) and never put primary actions *only* inside them.
5. **Bold, friendly type.** Plus Jakarta Sans (theme). Headlines are extra-bold with tight tracking; body is
   regular. Never set fontSize/fontWeight in features — pick a `textTheme` style and only `copyWith(color:)`
   (or `fontWeight: AppTypography.*` for emphasis).
6. **Air.** Screen padding `AppSpacing.screen` (16), gaps between sections `AppGap.xl` (24), inside cards
   `AppGap.md`/`AppGap.sm`. Lists of cards separated by `AppGap.sm`.
7. **Accessible colour.** Text on tints uses `AccentShades.foreground` / `onContainer` (AA contrast); white only
   on gradients/solid accents. Don't convey meaning by colour alone — pair with an icon or label.

## 2. Building blocks (use these, don't rebuild them)

| Need | Use |
|---|---|
| Accent shades | `context.accent(AppAccents.tasks)` → `.base .foreground .container .onContainer .border` |
| Gradients | `AppGradients.brand/sos/money/tasks/notices/emergency/family` or `AppGradients.of(accent)` |
| Hero / headline card | `GradientCard(gradient: …, glowColor: accent.base, child: …)` (text/icons default to white) |
| Leading icon in lists / settings / categories | `IconBadge(icon: AppIcons.x, accent: AppAccents.y, size: AppSizes.badgeSm|badgeMd|badgeLg)` (solid) or `soft: true` |
| Colourful action grid tile | `ActionTile(icon:, label:, accent:, onTap:, subtitle:)` — solid gradient card, white text |
| Card | `AppCard(accent: …)` — borderless; `accent` gives a soft tinted background for highlighted / selected cards |
| Section title | `SectionHeader(title:, icon: AppIcons.x, accent: AppAccents.y, actionLabel:, onAction:)` |
| Buttons | `AppButton` — `primary` = brand gradient with glow (one per screen), `tonal` = soft brand tint, `secondary` = borderless neutral fill, `text`, `danger` |
| Status pills | `StatusChip(label:, icon:, color: context.accent(a).foreground)` |
| Progress | `AppProgressBar(value:, color: context.accent(a).base)` |
| Empty states | `EmptyState` with an `IconBadge(size: AppSizes.badgeLg)`-style visual in the module accent + friendly copy + one action |
| Navigation bar | `AppNavBar` (home shell) — raised gradient SOS button |

## 3. Screen recipes

- **Tab screen:** no heavy AppBar chrome — canvas-coloured app bar with a bold title (theme) *or* a custom header row;
  then the module `GradientCard` hero; then content sections with `SectionHeader(icon, accent)`.
- **List screen:** filter row (`ChoiceChip`s / `SegmentedButton`, thin borders from theme) → cards with
  `IconBadge` leading (category/type in accent), title `titleSmall`, meta row of thin icons + `bodySmall`
  in `onSurfaceVariant`, trailing status chip or amount. Swipe/long-press menus unchanged.
- **Detail screen:** hero `GradientCard` with the main fact (amount, status, blood group, member name) → info
  sections in `AppCard`s with `IconBadge` rows → actions at the bottom (`AppButton` primary + secondary).
- **Form screen:** group fields into `AppCard` sections each with a `SectionHeader(icon, accent)`; outlined inputs
  (theme); category pickers as `ChoiceChipsField` with thin icons; single gradient primary submit button at the end
  (or a bottom bar); destructive actions `danger` and separated.
- **Settings / More:** profile hero on brand gradient → grouped `AppCard`s whose `ListTile`s lead with
  `IconBadge(accent: module accent)`; chevron `AppIcons.chevron`.
- **SOS:** the big button uses `AppGradients.sos`, a soft pulsing glow (respect reduced motion), white thin icon;
  active state = red `GradientCard` with live indicator. Emergency number button prominent (`danger`/tonal red).

## 3b. Screen chrome (mandatory)

- **Tab screens (Home, Tasks, SOS, Money, More)** use `GradientHeaderScrollView(header:, children:, gradient:, onRefresh:)`
  (`core/widgets/gradient_header.dart`): a **full-bleed gradient header that starts behind a transparent status bar**
  (no app bar), rounded bottom corners (`AppRadius.hero`), and the first content card **overlapping** the header's
  bottom edge. Use the module's horizontal header gradient: Home `AppGradients.brandHeader`, others
  `AppGradients.headerOf(AppAccents.x)`. Header content: small date/label line, big bold title, short subtitle, and
  2–3 frosted "glass" stat pills (see `DashboardHeader` / `_GlassStat`). Status-bar icons are handled automatically.
- **Pushed detail screens** may use the same header (member detail, goal detail, emergency card, SOS alert) or a
  plain canvas app bar (forms, lists) — never a coloured app bar.
- **Floating navigation bar**: the home shell overlays a floating capsule (`AppNavBar`) with a sliding indicator and
  passes its height to tab screens as `MediaQuery` bottom padding/viewPadding. Therefore scroll views with an explicit
  `padding` must add `MediaQuery.paddingOf(context).bottom` to their bottom padding (or leave padding `null` to get
  it automatically). FABs and snack bars are positioned above the bar automatically — don't hard-code offsets.

## 4. Motion

`AppDurations.fast/normal` with `Curves.easeOutCubic`. Allowed: `AnimatedContainer`/`AnimatedSwitcher` for state
changes, subtle scale on press for tiles, pulse on SOS. Check `MediaQuery.disableAnimationsOf(context)` and skip
non-essential animation when true.

## 5. Don'ts

- No `Icons.*`, no `Color(0x…)`/`Colors.*` in features (except `Colors.white` on gradients and `Colors.transparent`).
- **No borders/outlines around containers** (cards, tiles, chips, inputs, segmented buttons, dialogs, sheets, nav bar).
  Inputs are borderless soft fills with a primary focus ring only while focused.
- No default purple Material look, no full-bleed flat colour blocks, nothing that only works in light mode.
- No more than one gradient **primary** button per screen; no gradients on small elements other than `IconBadge(filled: true)`.
- Don't hide information in colour only; keep tap targets ≥ 48 dp; keep RTL (`…Directional`) and large-text safety.
