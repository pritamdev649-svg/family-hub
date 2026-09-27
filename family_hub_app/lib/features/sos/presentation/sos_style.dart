import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';

/// The SOS feature's look in one place (docs/12-DESIGN_LANGUAGE.md): the
/// module accent (red), the horizontal header gradient that continues
/// behind the transparent status bar, and the opacities of the frosted
/// "glass" elements on red gradients.
abstract final class SosStyle {
  /// Module accent: SOS is red everywhere (badges, rings, section icons).
  static const AppAccent accent = AppAccents.sos;

  /// Horizontal gradient of the full-bleed headers (SOS tab, alert screen)
  /// and of the status banner. Horizontal on purpose: a strip of it behind
  /// the status bar always matches the header / banner below it.
  static final LinearGradient header = AppGradients.headerOf(accent);

  /// Frosted fill of pills and icon buttons on a red gradient.
  static const double glassFill = 0.18;

  /// Stronger frosted fill (avatar ring, pressed / emphasised glass).
  static const double glassFillStrong = 0.26;

  /// Secondary white text on a red gradient.
  static const double mutedOpacity = 0.88;

  /// Disabled controls (busy "I am okay" / "False alarm").
  static const double disabledOpacity = 0.6;

  /// Secondary white text / icons on a red gradient.
  static Color get mutedOnGradient =>
      Colors.white.withValues(alpha: mutedOpacity);
}
