import 'package:flutter/material.dart';

/// Raw brand colours. Feature code should **not** use these directly — use
/// `Theme.of(context).colorScheme` for Material roles, `context.semanticColors`
/// for success / warning / SOS / money colours, `context.accent(AppAccent.x)`
/// for the colourful per-module accents and [AppGradients] for gradients.
abstract final class AppColors {
  /// Vivid indigo. Every Material colour role is derived from it.
  static const Color seed = Color(0xFF6366F1);

  /// Emergency red. White text on it meets WCAG AA (4.8:1).
  static const Color sos = Color(0xFFDC2626);

  /// Pressed / gradient end shade of [sos].
  static const Color sosDark = Color(0xFFB91C1C);

  static const Color success = Color(0xFF15803D);
  static const Color warning = Color(0xFFB45309);
  static const Color info = Color(0xFF1D4ED8);
  static const Color income = Color(0xFF047857);
  static const Color expense = Color(0xFFE11D48);

  // ── Neutral canvas (the colourful accents sit on these) ───────────────────
  static const Color canvasLight = Color(0xFFF5F6FB);
  static const Color canvasDark = Color(0xFF0E0F12);
  static const Color cardLight = Color(0xFFFFFFFF);
  static const Color cardDark = Color(0xFF1B1C21);
  static const Color borderLight = Color(0xFFE6E8F1);
  static const Color borderDark = Color(0xFF2A2C33);

  /// Very soft card shadow used in light mode (cards are borderless).
  static const Color shadowLight = Color(0x0F1B1F3B);

  /// Opacity of a soft tint behind coloured text / icons (status chips,
  /// icon badges): `color.withValues(alpha: AppColors.tintOpacity)`.
  static const double tintOpacity = 0.14;

  /// Opacity of a surface scrim over images (e.g. upload progress overlay).
  static const double scrimOpacity = 0.6;

  /// Opacity of the soft coloured glow under raised elements (SOS button,
  /// gradient hero cards).
  static const double glowOpacity = 0.35;

  /// Seeds for member avatars. [MemberAvatar] derives accessible
  /// container / on-container pairs from them for the current brightness.
  static const List<Color> avatarSeeds = <Color>[
    Color(0xFF6366F1), // indigo
    Color(0xFF14B8A6), // teal
    Color(0xFFF97316), // orange
    Color(0xFF8B5CF6), // violet
    Color(0xFF10B981), // emerald
    Color(0xFFEC4899), // pink
    Color(0xFF3B82F6), // blue
    Color(0xFFF59E0B), // amber
    Color(0xFF0EA5E9), // sky
    Color(0xFFF43F5E), // rose
  ];
}

/// The colourful accent palette. Every module owns one accent so the app is
/// vivid yet consistent (see [AppAccents]); use `context.accent(accent)` to
/// get brightness-aware shades.
enum AppAccent {
  indigo(Color(0xFFA5B4FC), Color(0xFF6366F1), Color(0xFF4338CA)),
  violet(Color(0xFFC4B5FD), Color(0xFF8B5CF6), Color(0xFF6D28D9)),
  blue(Color(0xFF93C5FD), Color(0xFF3B82F6), Color(0xFF1D4ED8)),
  sky(Color(0xFF7DD3FC), Color(0xFF0EA5E9), Color(0xFF0369A1)),
  teal(Color(0xFF5EEAD4), Color(0xFF14B8A6), Color(0xFF0F766E)),
  emerald(Color(0xFF6EE7B7), Color(0xFF10B981), Color(0xFF047857)),
  amber(Color(0xFFFCD34D), Color(0xFFF59E0B), Color(0xFFB45309)),
  orange(Color(0xFFFDBA74), Color(0xFFF97316), Color(0xFFC2410C)),
  rose(Color(0xFFFDA4AF), Color(0xFFF43F5E), Color(0xFFBE123C)),
  pink(Color(0xFFF9A8D4), Color(0xFFEC4899), Color(0xFFBE185D)),
  red(Color(0xFFFCA5A5), Color(0xFFEF4444), Color(0xFFB91C1C));

  const AppAccent(this.light, this.base, this.dark);

  /// 300 shade — foreground on dark surfaces.
  final Color light;

  /// 500 shade — icons, progress bars, gradient stops.
  final Color base;

  /// 700 shade — text / icons on light surfaces (WCAG AA on white).
  final Color dark;

  /// Stable accent for an index (avatars, list decorations, charts).
  static AppAccent cycle(int index) =>
      AppAccent.values[index.abs() % AppAccent.values.length];
}

/// Which accent each module uses. Keep every screen of a module on its
/// accent so users learn "violet = tasks, green = money, …".
abstract final class AppAccents {
  static const AppAccent brand = AppAccent.indigo;
  static const AppAccent home = AppAccent.indigo;
  static const AppAccent tasks = AppAccent.violet;
  static const AppAccent money = AppAccent.emerald;
  static const AppAccent income = AppAccent.emerald;
  static const AppAccent expense = AppAccent.rose;
  static const AppAccent goals = AppAccent.pink;
  static const AppAccent notices = AppAccent.amber;
  static const AppAccent sos = AppAccent.red;
  static const AppAccent emergency = AppAccent.rose;
  static const AppAccent family = AppAccent.blue;
  static const AppAccent settings = AppAccent.sky;
  static const AppAccent success = AppAccent.emerald;
  static const AppAccent warning = AppAccent.amber;
}

/// Brightness-aware shades of one [AppAccent].
@immutable
class AccentShades {
  const AccentShades({
    required this.base,
    required this.foreground,
    required this.container,
    required this.onContainer,
    required this.border,
  });

  /// Solid accent (icons, progress, gradient stops).
  final Color base;

  /// Accent-coloured text / icons on the normal surface (AA contrast).
  final Color foreground;

  /// Soft tinted background (icon badges, chips, tonal buttons).
  final Color container;

  /// Text / icons on [container].
  final Color onContainer;

  /// Thin border in the accent colour.
  final Color border;

  factory AccentShades.of(AppAccent accent, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final surface = isDark ? AppColors.cardDark : AppColors.cardLight;
    return AccentShades(
      base: accent.base,
      foreground: isDark ? accent.light : accent.dark,
      container: Color.alphaBlend(
        accent.base.withValues(alpha: isDark ? 0.20 : 0.12),
        surface,
      ),
      onContainer: isDark ? accent.light : accent.dark,
      border: accent.base.withValues(alpha: isDark ? 0.45 : 0.30),
    );
  }
}

/// Gradients used for hero headers, primary buttons and the SOS button.
abstract final class AppGradients {
  static const LinearGradient brand = LinearGradient(
    begin: AlignmentDirectional.topStart,
    end: AlignmentDirectional.bottomEnd,
    colors: <Color>[Color(0xFF6366F1), Color(0xFF8B5CF6), Color(0xFFEC4899)],
    stops: <double>[0, 0.55, 1],
  );

  /// Horizontal variants for the full-bleed [GradientHeader]: the colour only
  /// changes left→right, so the pinned status-bar strip always matches the
  /// header behind it.
  static const LinearGradient brandHeader = LinearGradient(
    begin: AlignmentDirectional.centerStart,
    end: AlignmentDirectional.centerEnd,
    colors: <Color>[Color(0xFF6366F1), Color(0xFF8B5CF6), Color(0xFFD946EF)],
    stops: <double>[0, 0.6, 1],
  );

  /// Horizontal header gradient for any accent.
  static LinearGradient headerOf(AppAccent accent) => LinearGradient(
    begin: AlignmentDirectional.centerStart,
    end: AlignmentDirectional.centerEnd,
    colors: <Color>[accent.base, Color.lerp(accent.base, accent.dark, 0.5)!],
  );

  static const LinearGradient sos = LinearGradient(
    begin: AlignmentDirectional.topStart,
    end: AlignmentDirectional.bottomEnd,
    colors: <Color>[Color(0xFFF43F5E), Color(0xFFDC2626)],
  );

  static const LinearGradient money = LinearGradient(
    begin: AlignmentDirectional.topStart,
    end: AlignmentDirectional.bottomEnd,
    colors: <Color>[Color(0xFF14B8A6), Color(0xFF10B981)],
  );

  static const LinearGradient tasks = LinearGradient(
    begin: AlignmentDirectional.topStart,
    end: AlignmentDirectional.bottomEnd,
    colors: <Color>[Color(0xFF8B5CF6), Color(0xFF6366F1)],
  );

  static const LinearGradient notices = LinearGradient(
    begin: AlignmentDirectional.topStart,
    end: AlignmentDirectional.bottomEnd,
    colors: <Color>[Color(0xFFF59E0B), Color(0xFFF97316)],
  );

  static const LinearGradient emergency = LinearGradient(
    begin: AlignmentDirectional.topStart,
    end: AlignmentDirectional.bottomEnd,
    colors: <Color>[Color(0xFFF43F5E), Color(0xFFEC4899)],
  );

  static const LinearGradient family = LinearGradient(
    begin: AlignmentDirectional.topStart,
    end: AlignmentDirectional.bottomEnd,
    colors: <Color>[Color(0xFF0EA5E9), Color(0xFF3B82F6)],
  );

  /// Two-stop gradient from an accent's base colour to a slightly deeper one.
  static LinearGradient of(AppAccent accent) => LinearGradient(
    begin: AlignmentDirectional.topStart,
    end: AlignmentDirectional.bottomEnd,
    colors: <Color>[accent.base, Color.lerp(accent.base, accent.dark, 0.45)!],
  );
}

/// Colours that Material's [ColorScheme] has no role for.
///
/// Access with `context.semanticColors.success` etc. All foreground/background
/// pairs meet WCAG AA contrast in both themes.
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.success,
    required this.onSuccess,
    required this.warning,
    required this.onWarning,
    required this.sos,
    required this.onSos,
    required this.sosContainer,
    required this.onSosContainer,
    required this.income,
    required this.expense,
    required this.info,
    required this.canvas,
    required this.card,
    required this.border,
  });

  final Color success;
  final Color onSuccess;
  final Color warning;
  final Color onWarning;
  final Color sos;
  final Color onSos;
  final Color sosContainer;
  final Color onSosContainer;
  final Color income;
  final Color expense;
  final Color info;

  /// Page background behind cards.
  final Color canvas;

  /// Card / sheet surface.
  final Color card;

  /// Hairline used only for dividers inside cards and focus outlines —
  /// containers themselves are borderless (docs/12-DESIGN_LANGUAGE.md).
  final Color border;

  static const AppSemanticColors light = AppSemanticColors(
    success: AppColors.success,
    onSuccess: Color(0xFFFFFFFF),
    warning: AppColors.warning,
    onWarning: Color(0xFFFFFFFF),
    sos: AppColors.sos,
    onSos: Color(0xFFFFFFFF),
    sosContainer: Color(0xFFFEE2E2),
    onSosContainer: Color(0xFF7F1D1D),
    income: AppColors.income,
    expense: AppColors.expense,
    info: AppColors.info,
    canvas: AppColors.canvasLight,
    card: AppColors.cardLight,
    border: AppColors.borderLight,
  );

  static const AppSemanticColors dark = AppSemanticColors(
    success: Color(0xFF6EE7B7),
    onSuccess: Color(0xFF022C22),
    warning: Color(0xFFFCD34D),
    onWarning: Color(0xFF451A03),
    // SOS keeps the same recognisable red in dark mode (white text stays AA).
    sos: AppColors.sos,
    onSos: Color(0xFFFFFFFF),
    sosContainer: Color(0xFF4C1515),
    onSosContainer: Color(0xFFFECACA),
    income: Color(0xFF6EE7B7),
    expense: Color(0xFFFDA4AF),
    info: Color(0xFF93C5FD),
    canvas: AppColors.canvasDark,
    card: AppColors.cardDark,
    border: AppColors.borderDark,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSemanticColors &&
          other.success == success &&
          other.onSuccess == onSuccess &&
          other.warning == warning &&
          other.onWarning == onWarning &&
          other.sos == sos &&
          other.onSos == onSos &&
          other.sosContainer == sosContainer &&
          other.onSosContainer == onSosContainer &&
          other.income == income &&
          other.expense == expense &&
          other.info == info &&
          other.canvas == canvas &&
          other.card == card &&
          other.border == border;

  @override
  int get hashCode => Object.hash(
    success,
    onSuccess,
    warning,
    onWarning,
    sos,
    onSos,
    sosContainer,
    onSosContainer,
    income,
    expense,
    info,
    canvas,
    card,
    border,
  );

  /// Instance matching [brightness].
  static AppSemanticColors of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  @override
  AppSemanticColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? warning,
    Color? onWarning,
    Color? sos,
    Color? onSos,
    Color? sosContainer,
    Color? onSosContainer,
    Color? income,
    Color? expense,
    Color? info,
    Color? canvas,
    Color? card,
    Color? border,
  }) {
    return AppSemanticColors(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      sos: sos ?? this.sos,
      onSos: onSos ?? this.onSos,
      sosContainer: sosContainer ?? this.sosContainer,
      onSosContainer: onSosContainer ?? this.onSosContainer,
      income: income ?? this.income,
      expense: expense ?? this.expense,
      info: info ?? this.info,
      canvas: canvas ?? this.canvas,
      card: card ?? this.card,
      border: border ?? this.border,
    );
  }

  @override
  AppSemanticColors lerp(
    covariant ThemeExtension<AppSemanticColors>? other,
    double t,
  ) {
    if (other is! AppSemanticColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t) ?? a;
    return AppSemanticColors(
      success: l(success, other.success),
      onSuccess: l(onSuccess, other.onSuccess),
      warning: l(warning, other.warning),
      onWarning: l(onWarning, other.onWarning),
      sos: l(sos, other.sos),
      onSos: l(onSos, other.onSos),
      sosContainer: l(sosContainer, other.sosContainer),
      onSosContainer: l(onSosContainer, other.onSosContainer),
      income: l(income, other.income),
      expense: l(expense, other.expense),
      info: l(info, other.info),
      canvas: l(canvas, other.canvas),
      card: l(card, other.card),
      border: l(border, other.border),
    );
  }
}

extension SemanticColorsX on BuildContext {
  /// Semantic colours of the current theme. Falls back to the instance that
  /// matches the theme brightness if the extension was not registered (e.g. in
  /// a bare `MaterialApp` inside a widget test).
  AppSemanticColors get semanticColors {
    final theme = Theme.of(this);
    return theme.extension<AppSemanticColors>() ??
        AppSemanticColors.of(theme.brightness);
  }

  /// Brightness-aware shades of [accent], e.g.
  /// `context.accent(AppAccents.tasks).container`.
  AccentShades accent(AppAccent accent) =>
      AccentShades.of(accent, Theme.of(this).brightness);
}
