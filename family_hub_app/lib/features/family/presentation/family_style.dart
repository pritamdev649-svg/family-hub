import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/shared/models/member.dart';

/// Visual rules of the family screens (docs/12-DESIGN_LANGUAGE.md): the
/// module accent, per-member / per-group accents and the frosted "glass"
/// opacities used for white content on the blue gradients.
abstract final class FamilyStyle {
  /// The family module's accent (blue).
  static const AppAccent accent = AppAccents.family;

  /// Full-bleed header gradient of the family screens.
  static LinearGradient get header => AppGradients.headerOf(accent);

  /// Accents that give each member a stable colour of their own (avatar
  /// ring). Red / rose are left out on purpose — they mean SOS / emergency.
  static const List<AppAccent> memberPalette = <AppAccent>[
    AppAccent.blue,
    AppAccent.violet,
    AppAccent.teal,
    AppAccent.orange,
    AppAccent.pink,
    AppAccent.emerald,
    AppAccent.amber,
    AppAccent.sky,
    AppAccent.indigo,
  ];

  /// Stable accent for [seed] (a member id): the same member keeps the same
  /// colour on every screen, run and device.
  static AppAccent accentFor(String seed) {
    var sum = 0;
    for (final unit in seed.codeUnits) {
      sum = (sum * 31 + unit) & 0x7fffffff;
    }
    return memberPalette[sum % memberPalette.length];
  }

  /// Accent of the n-th option of a colourful chip group.
  static AppAccent cycle(int index) =>
      memberPalette[index.abs() % memberPalette.length];

  /// Solid chip / button fill for [accent] that keeps white text at WCAG AA
  /// in both themes (the 700 shade).
  static Color solid(AppAccent accent) => accent.dark;

  // ── Frosted "glass" on gradients (white with these opacities) ────────────

  /// Fill of glass pills, cells and buttons.
  static const double glassFill = 0.16;

  /// Fill of glass elements that should stand out a little more.
  static const double glassFillStrong = 0.24;

  /// Secondary white text / icons on a gradient.
  static const double onGradientMuted = 0.85;

  /// Ring around avatars on a gradient.
  static const double glassRing = 0.7;

  /// Disabled glass content.
  static const double glassDisabled = 0.5;

  /// Secondary white text on a gradient.
  static Color get mutedOnGradient =>
      Colors.white.withValues(alpha: onGradientMuted);
}

/// Accents of the member-related enums (chips, icon badges).
extension MemberRoleAccent on MemberRole {
  AppAccent get accent => switch (this) {
    MemberRole.admin => AppAccent.amber,
    MemberRole.member => FamilyStyle.accent,
  };
}

extension AgeGroupAccent on AgeGroup {
  AppAccent get accent => switch (this) {
    AgeGroup.child => AppAccent.orange,
    AgeGroup.teen => AppAccent.violet,
    AgeGroup.adult => AppAccent.teal,
    AgeGroup.senior => AppAccent.emerald,
  };
}
