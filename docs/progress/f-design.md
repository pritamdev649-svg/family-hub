# f-design — Flutter design system & shared widgets

Owner of `lib/core/design/**`, `lib/core/widgets/**`, `l10n_parts/widgets.arb`,
`test/core/design/**`, `test/core/widgets/**`.

## Design tokens & theme (`lib/core/design/`, barrel `design.dart`)

- [x] `app_spacing.dart` — `AppSpacing` (xxs 2 … xxxl 48, `screen`, `card`, `listItem`, `screenWithFab`) + `AppGap` (vertical `xxs…xxxl`, horizontal `hXxs…hXxl`)
- [x] `app_radius.dart` — `AppRadius` (xs 4, sm 8, md 12, lg 16, xl 24, pill 999) + `brXs brSm brMd brLg brXl brPill brTopXl` (const `BorderRadius`)
- [x] `app_durations.dart` — `fast normal slow pollSos pollActiveSos snackbar` (+ `debounce`)
- [x] `app_sizes.dart` (extra) — icon sizes, `minTapTarget` 48, `buttonHeight` 52, strokes, spinner sizes, avatar radii, `progressBar`, `refreshBar`, `thumbnail`, `sosButton`, `maxContentWidth` 640, `maxDialogWidth`
- [x] `app_colors.dart` — `AppColors` (seed indigo `0xFF3949AB`, `sos`, `sosDark`, `success`, `warning`, `info`, `income`, `expense`, `avatarSeeds`, `tintOpacity`, `scrimOpacity`) + `AppSemanticColors` ThemeExtension (light/dark, `copyWith`, `lerp`, `of(brightness)`, value equality) + `context.semanticColors` (falls back to brightness instance if the extension is missing)
- [x] `app_typography.dart` — `AppTypography.textTheme(scheme)`: the only place with font sizes/weights/line-heights (M3 scale, body/label one step larger, generous line-heights for Indic/Arabic, even leading), weight constants, `tabularFigures`
- [x] `app_theme.dart` — `AppTheme.light()/dark()`: `ColorScheme.fromSeed`, typography, AppBar, Card (outlined, `brLg`, no margin), Filled/Outlined/Text/Elevated/Icon buttons (52 dp tall, `brMd`), InputDecoration (filled, `brMd`, focused 2 dp primary), Chip, NavigationBar (labels always shown), ListTile, SnackBar (floating), Dialog, BottomSheet (drag handle, max width), FAB, SegmentedButton, ProgressIndicator, Divider, TabBar, PopupMenu, DatePicker/TimePicker, Tooltip, Badge, ExpansionTile, Switch/Checkbox/Radio; `visualDensity: standard`, `materialTapTargetSize: padded`
- [x] `app_icons.dart` — `AppIcons` (navigation incl. selected variants, domain, settings, actions, media, status); directional icons mirror in RTL

## Shared widgets (`lib/core/widgets/`, barrel `widgets.dart`)

- [x] `AppButton` + `AppButtonVariant` (spinner + disabled while loading, wraps long labels, `expand`)
- [x] `AppTextField` (show/hide toggle for obscured fields, controller *or* initialValue, multiline defaults, tap-outside unfocus)
- [x] `AsyncValueView<T>` (loading / error+retry / empty / data; keeps previous data with a thin progress bar while refreshing; dismissible "couldn't refresh" notice when a refresh fails; stable tree so scroll positions survive; ErrorView stays visible during retries)
- [x] `LoadingView`, `ErrorView` (+ optional `isRetrying`), `EmptyState` (scrollable full-area layout so pull-to-refresh works and large text never overflows)
- [x] `AppRefreshIndicator` (swallows refresh errors — the provider shows them)
- [x] `AppCard`, `SectionHeader`, `StatusChip`, `AppProgressBar` (clamped, animated, localised % semantics via `Fmt.percent`)
- [x] `MemberAvatar` (grapheme-safe initials, deterministic accessible colour per name, image fallback to initials) — also exposes `initialsOf` / `colorsFor`
- [x] `AppNetworkImage` (+ `appImageProvider`, `appImageKind`, `cacheWidthFor`): http(s) cached, local path → `Image.file`, placeholder on error, decode-size limits
- [x] `MoneyText` + `LedgerFlow` (via `fmtProvider`; `+`/`−` and semantic colours; zero never signed; tabular figures; never truncated)
- [x] `showConfirmDialog` (scrollable, destructive style)
- [x] `SnackX` (`showSuccess` / `showError` / `showInfo`; errors localised via `localizedErrorMessage`, Riverpod `ProviderException` unwrapped, cancellations silent)
- [x] `ImagePickerField` (camera/gallery sheet, remove, resize 1600 px / q80, upload via `cloudinaryServiceProvider` with progress overlay and local preview, permission errors localised, upload cancelled on dispose)
- [x] `DatePickerField` (controlled FormField, localised display via `Fmt.date`, clamps initial/first/last dates, clear button, validator)
- [x] `AppDropdownField<T>` (value not in items → empty instead of crash; menu rows grow with large text)
- [x] `ChoiceChipsField<T>`
- [x] `ResponsiveCenter` (max 640, top-centred, fills width on phones)
- [x] `PaginatedListView<T>` (auto-load near the end once per page + accessible "Load more" button; spinner footer; no retry storm offline)
- [x] `OfflineBanner` (reads `connectivityStatusProvider` from `core/providers/core_providers.dart`)

## Localisation

- [x] `l10n_parts/widgets.arb`: `widgetPhotoPermissionDenied`, `widgetPhotoSourceUnavailable`, `widgetStaleDataNotice`, `widgetProgressLabel(percent)`, `widgetPhotoLabel`, `widgetClearDate` (everything else uses the `common*` keys)
- [ ] Translations of the `widget*` keys into the other 14 languages (translation agents)

## Tests

- [x] `test/core/design/app_theme_test.dart` — 13 tests, pass in the real tree (`flutter test test/core/design`)
- [x] `test/core/widgets/*_test.dart` (+ `widget_test_harness.dart`) — 36 tests: buttons, text field, avatar, image kinds, money, chips, progress, section header, card, responsive centre, AsyncValueView state machine (incl. refresh / failed refresh / dismiss), confirm dialog, snackbars, offline banner, dropdown, choice chips, date picker, paginated list
- [ ] The widget tests only compile in the real tree once every file imported by `core_providers.dart` exists (the feature `*_mock_handlers.dart` files were still missing at the time of writing). All 49 design + widget tests pass against a scratch copy of the app with the nine missing `*_mock_handlers.dart` files stubbed. Re-run `flutter test test/core/design test/core/widgets` once those files land.

## Known issues / notes for other agents

- `ErrorView` / `EmptyState` / `AsyncValueView` error & empty states use a `LayoutBuilder` (full-area scroll for pull-to-refresh). Inside widgets that measure intrinsic sizes (e.g. `AlertDialog` content) wrap them in a `SizedBox(width: …)`. `LoadingView` has no such restriction.
- `AppButtonVariant.secondary` is an outlined button; use `text` for the lowest emphasis.
- `AppDropdownField.onChanged` is nullable-required: pass `null` to disable the field.
- Extra optional params (compatible with the guide): `ErrorView.isRetrying`, `PaginatedListView.padding/separator/controller`.
