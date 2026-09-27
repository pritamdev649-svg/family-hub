/// Component dimension tokens: icon sizes, touch targets, strokes, avatar radii
/// and layout widths. Use these instead of raw numbers for anything that is
/// not spacing ([AppSpacing]) or a corner radius ([AppRadius]).
abstract final class AppSizes {
  /// Minimum touch target (Material + WCAG guidance).
  static const double minTapTarget = 48;

  /// Height of primary buttons — slightly taller than Material's default for
  /// easier tapping by older family members.
  static const double buttonHeight = 52;

  // Icons.
  static const double iconXs = 16;
  static const double iconSm = 20;
  static const double iconMd = 24;
  static const double iconLg = 32;
  static const double iconXl = 48;
  static const double iconHero = 64;

  // Strokes & borders.
  static const double hairline = 1;

  /// Checkbox outline — slightly thicker than [hairline] so it stays visible.
  static const double checkboxBorder = 1.5;

  /// Bottom navigation bar height (without safe-area inset).
  static const double navBarHeight = 66;

  /// Raised circular SOS button in the bottom navigation.
  static const double navSosButton = 58;

  /// How far the SOS button rises above the navigation bar's top edge.
  static const double navSosRaise = 20;

  /// Rounded-square icon badge sizes ([IconBadge]).
  static const double badgeSm = 36;
  static const double badgeMd = 44;
  static const double badgeLg = 56;

  /// Blur radius of the soft coloured glow under raised gradient elements.
  static const double glowBlur = 24;

  /// Soft card shadow blur.
  static const double cardShadowBlur = 16;
  static const double borderFocused = 2;
  static const double spinnerStroke = 2.5;

  /// Diameter of small inline spinners (inside buttons, list footers).
  static const double spinnerSm = 20;

  /// Diameter of a full-screen / section loading spinner.
  static const double spinnerLg = 40;

  /// Default height of [AppProgressBar].
  static const double progressBar = 8;

  /// Height of the thin "refreshing" indicator on top of stale data.
  static const double refreshBar = 3;

  // Avatar radii.
  static const double avatarSm = 16;
  static const double avatarMd = 20;
  static const double avatarLg = 28;
  static const double avatarXl = 44;

  /// Square thumbnail (notice images, pickers).
  static const double thumbnail = 56;

  /// Diameter of the large SOS trigger button.
  static const double sosButton = 184;

  /// Content is centred and capped at this width on tablets / landscape.
  static const double maxContentWidth = 640;

  /// Material minimum dialog width.
  static const double minDialogWidth = 280;

  /// Dialogs never grow wider than this.
  static const double maxDialogWidth = 560;
}
