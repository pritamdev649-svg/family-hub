import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// System status-bar styling: the status bar is always **fully transparent**
/// so the screen behind it (canvas, app bar or the gradient header) shows
/// through edge to edge. Only the colour of the status-bar icons changes, to
/// contrast with whatever is behind them.
///
/// Why this is needed: on Android 14 and older, `FlutterActivity` paints a
/// translucent grey scrim (`0x40000000`) behind the status bar, and Flutter
/// only replaces it while the current screen provides a
/// `SystemUiOverlayStyle` (an `AppBar` or an `AnnotatedRegion`). Screens
/// without an app bar (splash, welcome, sign-in...) would keep that scrim and
/// whatever icon colour the previous screen left behind.
///
/// Usage:
/// * `FamilyHubApp` wraps every route in an app-wide
///   `AnnotatedRegion<SystemUiOverlayStyle>` with [forBackground] of the
///   active theme. It is the fallback for screens without their own style.
/// * Widgets that paint their own colour behind the status bar (e.g. the
///   gradient header) add a nested `AnnotatedRegion` with [forBackground] of
///   that colour. The deepest region under the status bar wins.
/// * `AppBar`s already use a transparent status bar in Material 3 and pick
///   the icon colour from their background, so they need nothing extra.
///
/// Navigation-bar fields are left `null` on purpose so the system keeps its
/// own navigation-bar appearance.
abstract final class AppSystemUi {
  /// Transparent status bar whose icons contrast with a [background] of the
  /// given brightness (dark background -> light icons and vice versa).
  static SystemUiOverlayStyle forBackground(Brightness background) {
    return background == Brightness.dark ? _overDark : _overLight;
  }

  /// Transparent status bar for content painted with [theme]'s own
  /// background (scaffold canvas).
  static SystemUiOverlayStyle forTheme(ThemeData theme) =>
      forBackground(theme.brightness);

  // Dark icons, for light backgrounds.
  static const SystemUiOverlayStyle _overLight = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    // Android: colour of the status-bar icons.
    statusBarIconBrightness: Brightness.dark,
    // iOS: brightness of what is behind the status bar.
    statusBarBrightness: Brightness.light,
    // Android 10+: no automatic scrim behind a transparent status bar.
    systemStatusBarContrastEnforced: false,
  );

  // Light icons, for dark backgrounds.
  static const SystemUiOverlayStyle _overDark = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemStatusBarContrastEnforced: false,
  );
}
