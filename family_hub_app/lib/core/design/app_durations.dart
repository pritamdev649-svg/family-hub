/// Animation, polling and UI timing tokens.
abstract final class AppDurations {
  /// Micro-interactions (icon swaps, fades of small elements).
  static const Duration fast = Duration(milliseconds: 150);

  /// Default transition length (expand/collapse, cross-fades).
  static const Duration normal = Duration(milliseconds: 250);

  /// Larger surface transitions (progress bars filling, hero cards).
  static const Duration slow = Duration(milliseconds: 400);

  /// How often the app polls for new SOS alerts while in the foreground.
  static const Duration pollSos = Duration(seconds: 5);

  /// How often an open SOS alert screen refreshes the live location.
  static const Duration pollActiveSos = Duration(seconds: 15);

  /// How long a snackbar stays visible.
  static const Duration snackbar = Duration(seconds: 4);

  /// Delay before "search as you type" style inputs fire.
  static const Duration debounce = Duration(milliseconds: 350);
}
