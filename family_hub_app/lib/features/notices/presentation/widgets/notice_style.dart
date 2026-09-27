import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';

/// Colour decisions of the notice board, in one place
/// (docs/12-DESIGN_LANGUAGE.md: notices = **amber**).
abstract final class NoticeStyle {
  /// Module accent of every notice screen and widget.
  static const AppAccent accent = AppAccents.notices;

  /// Full-bleed header gradient of the board (horizontal, so a strip of it
  /// pinned behind the status bar matches the header exactly).
  static final LinearGradient header = AppGradients.headerOf(accent);

  /// Solid amber for surfaces that carry **white** text or icons (pinned
  /// pill, "New notice" button). The base amber is too light for white text;
  /// the deep shade keeps WCAG AA contrast in both themes.
  static Color get solid => accent.dark;
}
