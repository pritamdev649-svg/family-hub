import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Navigation helpers of the family screens.
extension FamilyNavigationX on BuildContext {
  /// Whether this screen is the top-most route: no page, dialog or sheet
  /// is above it (e.g. one that a previous tap is still opening).
  bool get isTopRoute => ModalRoute.of(this)?.isCurrent ?? true;

  /// Pushes [location] unless another route is already above this screen.
  /// A quick second tap (double tap, impatient tap during the transition)
  /// would otherwise open the same screen twice.
  void pushIfTop(String location) {
    if (isTopRoute) push<void>(location);
  }

  /// Leaves the screen: pops, or — when it was opened directly (deep link,
  /// notification) with nothing below — goes to [fallback].
  void popOrGo(String fallback) {
    if (canPop()) {
      pop();
    } else {
      go(fallback);
    }
  }
}
