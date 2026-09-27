import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Text-scale policy applied app-wide in `FamilyHubApp.builder`.
abstract final class AppTextScale {
  /// Minimum scale while the in-app "Large text" setting is on.
  static const double largeTextMin = 1.3;

  /// Layouts are verified up to this scale; larger system settings are capped
  /// so text never overflows fixed chrome (navigation bar, app bars, chips).
  static const double max = 1.6;

  /// Combines the system [system] scaler with the app's large-text setting:
  /// * large text on  -> at least [largeTextMin] (a larger system setting
  ///   wins), capped at [max];
  /// * large text off -> the system setting, capped at [max].
  ///
  /// Bounds are applied per font size, so Android 14+ non-linear font scaling
  /// stays intact. The returned scaler can be clamped again safely (e.g. with
  /// `MediaQuery.withClampedTextScaling`), even to a range that collapses to a
  /// single value.
  static TextScaler resolve(TextScaler system, {required bool largeText}) {
    return BoundedTextScaler(
      system,
      minScaleFactor: largeText ? largeTextMin : 0,
      maxScaleFactor: max,
    );
  }
}

/// A [TextScaler] that keeps [base]'s scaling within
/// `[minScaleFactor, maxScaleFactor]` for every font size.
///
/// Unlike the framework's clamped scaler, clamping it again merges the bounds
/// (the later maximum wins over an earlier minimum) instead of asserting that
/// the range is non-empty.
@immutable
class BoundedTextScaler implements TextScaler {
  const BoundedTextScaler(
    this.base, {
    this.minScaleFactor = 0,
    this.maxScaleFactor = double.infinity,
  }) : assert(minScaleFactor >= 0),
       assert(maxScaleFactor >= minScaleFactor);

  final TextScaler base;
  final double minScaleFactor;
  final double maxScaleFactor;

  @override
  double scale(double fontSize) => base
      .scale(fontSize)
      .clamp(minScaleFactor * fontSize, maxScaleFactor * fontSize)
      .toDouble();

  @Deprecated('Use scale() instead.')
  @override
  double get textScaleFactor => scale(_probe) / _probe;

  static const double _probe = 14;

  @override
  TextScaler clamp({
    double minScaleFactor = 0,
    double maxScaleFactor = double.infinity,
  }) {
    final upper = math.min(maxScaleFactor, this.maxScaleFactor);
    final lower = math.min(
      math.max(minScaleFactor, this.minScaleFactor),
      upper,
    );
    if (lower == this.minScaleFactor && upper == this.maxScaleFactor) {
      return this;
    }
    return BoundedTextScaler(
      base,
      minScaleFactor: lower,
      maxScaleFactor: upper,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BoundedTextScaler &&
          other.base == base &&
          other.minScaleFactor == minScaleFactor &&
          other.maxScaleFactor == maxScaleFactor;

  @override
  int get hashCode => Object.hash(base, minScaleFactor, maxScaleFactor);

  @override
  String toString() =>
      'BoundedTextScaler($base, $minScaleFactor..$maxScaleFactor)';
}
