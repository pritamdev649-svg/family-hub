# rd-auth: auth screens in the new design language (progress)

Owner: rd-auth. Scope: `family_hub_app/lib/features/auth/presentation/**`,
`family_hub_app/test/features/auth/**`, `family_hub_app/l10n_parts/auth.arb` (new keys only; none were needed).
Spec: docs/12-DESIGN_LANGUAGE.md, docs/05-FLUTTER_GUIDE.md §3–4. Behaviour, providers, routes, the domain and the
mock handlers are unchanged. Earlier history: docs/progress/f-auth.md and f-auth-harden.md.

## Redesign

User request relayed with this task: "make status bar transparent, not looking good". Every auth screen now draws
under a transparent status bar with icons that stay readable.

### Status bar and page frame
- [x] `authSystemUiStyle(context, {onGradient})` (`widgets/auth_layout.dart`) sets these on every auth screen:
      - the status bar is transparent, with no grey scrim;
      - the icons are white over the welcome gradient and in the dark theme, and dark on the light canvas (Android and iOS);
      - the Android navigation bar is canvas-coloured on older Android versions (edge-to-edge versions ignore this).
- [x] `AuthScaffold` has a canvas background and a slim top bar with no title. The bar shows only when the screen was
      pushed (round `AuthBarButton` back button with a thin `AppIcons.back`) or has actions (family setup: log out).
      Otherwise a safe area keeps content below the status bar. It passes the style both as an `AnnotatedRegion` and
      as `AppBar.systemOverlayStyle`.
- [x] Its scroll view is capped at 640 dp, dismisses the keyboard on drag and adds `MediaQuery.paddingOf(context).bottom`.

### Screens
- [x] **Welcome**: the hero is a full-bleed `AppGradients.brand` panel (core `GradientHeader`) that starts behind the
      transparent status bar and fills whatever the actions leave free. On phones that is about the top 55–70 %; the
      page scrolls on short screens and with large text. The hero contains:
      - a frosted "glass" language pill showing the language's native name (opens the language sheet);
      - a large frosted app mark (`AppIcons.family` on white glass with a brand glow);
      - "FamilyHub" in `headlineLarge` white, with the tagline;
      - three glass benefit pills.

      Below the hero are three big actions: the gradient primary *Create a family*, the tonal *Join with invite code*
      and the text button *I already have an account*. The status-bar icons turn dark again (light theme) once the hero
      has scrolled away. The session-expired notice sits above the actions.
- [x] **Log in**: a big bold header (solid brand `IconBadge`, `headlineMedium` title, subtitle), then:
      - a teal demo banner;
      - email and password in a borderless `AppCard`, with *Forgot password?* inside the card;
      - the lockout / wrong-password banner (red, clock icon while locked), the gradient button and the sign-up link.
- [x] **Sign up**: the header follows the mode (indigo house for create, teal door for join). Below it:
      - the mode tiles;
      - an *About you* card with a violet `SectionHeader` icon;
      - a *Your family* card (`FamilyModeFields`: family form or invite code, header icon in the mode colour);
      - the consent card, the gradient submit button and the log-in link.
- [x] **Verify email**: the header, then a card with the 6-box OTP and the resend pill, the gradient *Verify* button and
      *Use another account*.
- [x] **Reset password**: step 1 is the email in a card. Step 2 is one card with the OTP boxes, the resend pill and the
      two new-password fields. Then come the gradient button and *Use a different email*.
- [x] **Family setup**: the header, a "Signed in as …" pill and two solid mode tiles (*Create* indigo, *Join* teal).
      Then the *Your family* card, the gradient button and log out (text button, plus the round top-bar button).

### Widgets
- [x] `OtpCodeField` shows 6 rounded boxes with large tabular digits. One invisible `TextField` spans the boxes, so
      these keep working: typing, pasting "123 456", one-time-code autofill, the formatter and screen readers (label
      merged in).
  - It is a `FormField`, so validation, server errors and auto-validate work as before, with the error text under the
    boxes.
  - The active box gets the primary focus ring; filled boxes get the brand tint; an error turns all boxes
    `errorContainer`.
  - Digits always run left to right (also in Arabic), and animations are skipped with reduced motion.
- [x] `ResendCodeButton` is a centred pill. It is brand-tinted with a retry icon when a code can be sent. While the
      cooldown runs it is a neutral disabled pill with a clock and "Resend code in 42 seconds".
- [x] `FamilyModeSelector` shows two colourful tiles side by side with equal height:
  - the selected tile is a solid gradient with white text, a glow and a white check;
  - the other tile is a soft tint of its colour;
  - screen readers get `button` + `selected` + `inMutuallyExclusiveGroup`.
- [x] `FamilyModeFields` is shared by sign-up and family setup, replacing a duplicated `AnimatedSwitcher` block.
- [x] `AuthHeader`, `AuthSectionCard` (an `AppCard` plus an optional `SectionHeader` with icon and accent),
      `AuthMessageBanner` (a soft accent card with a solid `IconBadge`; red for errors, brand for info, `accent`
      override) and `AuthBarButton`.
- [x] `ConsentCheckbox` sits on its own card, which turns soft green once accepted. The text is `bodyMedium` in the
      `onSurface` colour, and the links are bold, underlined and brand-coloured. The "please accept" hint is inside the
      card (`helperText`).
- [x] Country picker sheet: a header with a blue `IconBadge`, then the search, then rows. Each row has the flag on a
      soft square (`FlagBadge`), the name, the dial code (left-to-right isolated, `countryDialCode`) and an emerald
      currency pill. The selected row is brand-tinted and ticked, and the list clears the home indicator.
      `CountryPickerField` and `countrySubtitle` keep their API (the family settings screen uses them; its tests pass).
- [x] Language sheet: a header with a sky `IconBadge`. Rows show the native names; the selected row is brand-tinted
      and ticked.
- [x] Tokens only:
  - `AuthAccents` (brand, create = indigo, join = teal, about you = violet, demo = teal, error = red) and `AuthGlass`
    (named white-glass opacities) in `auth_labels.dart`;
  - `authSoftFill(context)` reuses the theme's input fill for the OTP boxes and the waiting pill;
  - no `Color(0x…)`, no `Colors.*` apart from white on gradients and transparent, no `Icons.*`, no font sizes or
    weights, no left/right.
- [x] `AuthIcons.createFamily` / `joinFamily` now point to `AppIcons.createFamily` (house) / `AppIcons.joinFamily`
      (door). The new `AuthIcons.inviteCode` is the key.

### Tests
- [x] Tests updated with their intent unchanged:
  - the OTP finders now use `find.byType(OtpCodeField)` (onboarding and flow tests);
  - the mode taps now use the tile label `authWelcomeJoinFamily` (register and onboarding);
  - the consent-link finder is scoped to the rich sentence, because the card's hint also names the documents.
- [x] `pumpAuthApp(theme:)` parameter added.
- [x] New `auth_redesign_test.dart` (13 tests):
  - status bar: welcome transparent with white icons; icons turn dark once the hero scrolled away; canvas screens dark
    icons (light theme) and white icons (dark theme);
  - OTP boxes draw the digits, and an incomplete code is explained under the boxes;
  - the mode tiles' selected state for screen readers;
  - every screen renders on the dark canvas.
- [x] The existing large text (1.4×) + RTL + 320 dp layout test covers every screen with no overflow.
- [x] Checked visually with brand-font renders of every screen: light and dark, RTL, 1.4× at 320 dp, the country sheet
      and reset step 2. They were made by a temporary preview test (deleted) into the session scratchpad.

## Pending
- [ ] `auth_flow_test.dart` (end to end with the real app) fails **after** sign-up → verify → home, at log-out:
      `SosStatusBanner.build` (`lib/features/sos/presentation/widgets/sos_status_banner.dart:59`) triggers "setState()
      or markNeedsBuild() called during build" on the provider scope while the session ends. That is not auth code:
      the auth steps of the flow pass with the new widgets. Handed off to the SOS owner.
- [ ] Not run on a device or simulator: the full app did not compile earlier in this session while other agents were
      mid-change. The system-bar style is verified with `SystemChrome.latestStyle` in widget tests.
- [ ] Translations: no new keys. `authModeCreate` / `authModeJoin` are no longer shown (the tiles use
      `authWelcomeCreateFamily` / `authWelcomeJoinFamily`); the l10n owner can drop them.

## Handoffs (files I do not own)
- **core (`lib/main.dart`, `lib/core/design/app_theme.dart`)**:
  - enable edge-to-edge at start-up (`SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge)`) and a
    transparent default style;
  - give `AppBarTheme` an explicit `systemOverlayStyle`: transparent status bar, icon brightness by theme, canvas
    navigation bar.

  This makes the status bar transparent on every pushed screen, not only in auth. `authSystemUiStyle` in
  `features/auth/presentation/widgets/auth_layout.dart` is a ready implementation to promote.
- **core (`lib/core/widgets/gradient_header.dart`)**: `GradientHeaderScrollView` uses
  `SystemUiOverlayStyle.light/dark`, which also set `systemNavigationBarColor` to **black**. On Android before
  edge-to-edge, a black navigation bar under the light canvas looks broken. Build the style explicitly (see
  `authSystemUiStyle`).
- **visual-QA / core widgets**: candidates to promote from auth:
  - `AuthBarButton` (round back button for canvas app bars; other features still get Material's default arrow);
  - `AuthSectionCard` (form section card);
  - `FlagBadge`;
  - the OTP box field.
- **SOS owner**: the `SosStatusBanner` rebuild during build described under Pending.
- **Android (`android/app/src/main/res/values*/styles.xml`)**: optional. Make the launch/normal theme status bar
  transparent, so the first frame before Flutter paints matches.

## Known issues / decisions
- The welcome hero grows to fill the space above the actions instead of a fixed 55 %. That keeps the actions at the
  bottom with no empty band on tall phones; the minimum is the hero's content.
- In the mode tiles the unselected mode is a soft tint rather than a second solid tile, so the selection is clear
  without relying on colour alone (check mark and screen-reader state as well).
- The OTP input keeps interactive selection, so long-press → Paste works. On an empty field the paste toolbar appears
  at the start of the boxes.
