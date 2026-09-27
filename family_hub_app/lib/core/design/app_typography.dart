import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The app's type scale — **the only place** where font sizes, weights,
/// letter-spacing and line-heights are defined.
///
/// Based on the Material 3 scale with a few readability tweaks for
/// multi-generational use (body and label sizes one step larger, more generous
/// line-heights so Indic scripts with stacked vowel marks and Arabic do not
/// collide).
///
/// Brand font: **Plus Jakarta Sans** (via `google_fonts`) for Latin text —
/// modern, rounded and very legible. Scripts it does not cover (Devanagari,
/// Bengali, Tamil, Telugu, Gujarati, Kannada, Malayalam, Gurmukhi, Arabic)
/// automatically fall back to the platform's Noto fonts.
/// The font is fetched once and cached; to ship it offline, drop the TTFs into
/// `assets/google_fonts/` (google_fonts picks them up with no code change).
///
/// Feature code reads styles via `Theme.of(context).textTheme.titleMedium` etc.
/// and may only change colour / weight emphasis with `copyWith(color: …)`.
abstract final class AppTypography {
  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight semiBold = FontWeight.w600;
  static const FontWeight bold = FontWeight.w700;

  static const FontWeight extraBold = FontWeight.w800;

  /// Set to `false` in tests (see `test/flutter_test_config.dart`) so widget
  /// tests never try to download the brand font.
  static bool useBrandFont = true;

  /// Use for amounts and counters so digits line up in lists.
  static const TextStyle tabularFigures = TextStyle(
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  );

  /// Builds the text theme, coloured for [scheme].
  static TextTheme textTheme(ColorScheme scheme) {
    const base = TextTheme(
      displayLarge: TextStyle(
        fontSize: 57,
        height: 64 / 57,
        fontWeight: regular,
        letterSpacing: -0.25,
      ),
      displayMedium: TextStyle(
        fontSize: 45,
        height: 52 / 45,
        fontWeight: regular,
        letterSpacing: 0,
      ),
      displaySmall: TextStyle(
        fontSize: 36,
        height: 44 / 36,
        fontWeight: regular,
        letterSpacing: 0,
      ),
      headlineLarge: TextStyle(
        fontSize: 32,
        height: 40 / 32,
        fontWeight: extraBold,
        letterSpacing: -0.6,
      ),
      headlineMedium: TextStyle(
        fontSize: 28,
        height: 36 / 28,
        fontWeight: extraBold,
        letterSpacing: -0.5,
      ),
      headlineSmall: TextStyle(
        fontSize: 24,
        height: 32 / 24,
        fontWeight: bold,
        letterSpacing: -0.4,
      ),
      titleLarge: TextStyle(
        fontSize: 21,
        height: 28 / 21,
        fontWeight: bold,
        letterSpacing: -0.3,
      ),
      titleMedium: TextStyle(
        fontSize: 17,
        height: 24 / 17,
        fontWeight: bold,
        letterSpacing: -0.1,
      ),
      titleSmall: TextStyle(
        fontSize: 15,
        height: 22 / 15,
        fontWeight: semiBold,
        letterSpacing: 0,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        height: 24 / 16,
        fontWeight: regular,
        letterSpacing: 0.15,
      ),
      bodyMedium: TextStyle(
        fontSize: 15,
        height: 22 / 15,
        fontWeight: regular,
        letterSpacing: 0.15,
      ),
      bodySmall: TextStyle(
        fontSize: 13,
        height: 19 / 13,
        fontWeight: regular,
        letterSpacing: 0.2,
      ),
      labelLarge: TextStyle(
        fontSize: 15,
        height: 20 / 15,
        fontWeight: semiBold,
        letterSpacing: 0.1,
      ),
      labelMedium: TextStyle(
        fontSize: 13,
        height: 18 / 13,
        fontWeight: semiBold,
        letterSpacing: 0.3,
      ),
      labelSmall: TextStyle(
        fontSize: 12,
        height: 16 / 12,
        fontWeight: medium,
        letterSpacing: 0.3,
      ),
    );

    final spaced = _evenLeading(base);
    final branded = useBrandFont
        ? GoogleFonts.plusJakartaSansTextTheme(spaced)
        : spaced;
    return branded.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
      decorationColor: scheme.onSurface,
    );
  }

  /// Distributes extra line-height evenly above and below glyphs so tall
  /// scripts are vertically centred in buttons and chips.
  static TextTheme _evenLeading(TextTheme t) {
    TextStyle? e(TextStyle? s) =>
        s?.copyWith(leadingDistribution: TextLeadingDistribution.even);
    return TextTheme(
      displayLarge: e(t.displayLarge),
      displayMedium: e(t.displayMedium),
      displaySmall: e(t.displaySmall),
      headlineLarge: e(t.headlineLarge),
      headlineMedium: e(t.headlineMedium),
      headlineSmall: e(t.headlineSmall),
      titleLarge: e(t.titleLarge),
      titleMedium: e(t.titleMedium),
      titleSmall: e(t.titleSmall),
      bodyLarge: e(t.bodyLarge),
      bodyMedium: e(t.bodyMedium),
      bodySmall: e(t.bodySmall),
      labelLarge: e(t.labelLarge),
      labelMedium: e(t.labelMedium),
      labelSmall: e(t.labelSmall),
    );
  }
}
