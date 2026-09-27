import 'package:flutter/widgets.dart';

/// Spacing scale (logical pixels). The **only** source of paddings, margins and
/// gaps in the app — feature code must never use raw numbers.
///
/// All ready-made [EdgeInsets] here are symmetric, so they are RTL-safe. For
/// one-sided insets use `EdgeInsetsDirectional.only(start: AppSpacing.md)`.
abstract final class AppSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  /// Default padding around a screen body.
  static const EdgeInsets screen = EdgeInsets.all(lg);

  /// Default inner padding of an [AppCard].
  static const EdgeInsets card = EdgeInsets.all(lg);

  /// Default padding of a row inside a list.
  static const EdgeInsets listItem = EdgeInsets.symmetric(
    horizontal: lg,
    vertical: sm,
  );

  /// Screen padding that leaves room below the last item for a FAB.
  static const EdgeInsets screenWithFab = EdgeInsets.fromLTRB(
    lg,
    lg,
    lg,
    xxxl + xxl,
  );
}

/// Pre-built gaps for [Column] / [Row] / [Wrap] children.
///
/// ```dart
/// Column(children: [title, AppGap.md, body]);
/// Row(children: [icon, AppGap.hSm, label]);
/// ```
abstract final class AppGap {
  // Vertical gaps.
  static const SizedBox xxs = SizedBox(height: AppSpacing.xxs);
  static const SizedBox xs = SizedBox(height: AppSpacing.xs);
  static const SizedBox sm = SizedBox(height: AppSpacing.sm);
  static const SizedBox md = SizedBox(height: AppSpacing.md);
  static const SizedBox lg = SizedBox(height: AppSpacing.lg);
  static const SizedBox xl = SizedBox(height: AppSpacing.xl);
  static const SizedBox xxl = SizedBox(height: AppSpacing.xxl);
  static const SizedBox xxxl = SizedBox(height: AppSpacing.xxxl);

  // Horizontal gaps.
  static const SizedBox hXxs = SizedBox(width: AppSpacing.xxs);
  static const SizedBox hXs = SizedBox(width: AppSpacing.xs);
  static const SizedBox hSm = SizedBox(width: AppSpacing.sm);
  static const SizedBox hMd = SizedBox(width: AppSpacing.md);
  static const SizedBox hLg = SizedBox(width: AppSpacing.lg);
  static const SizedBox hXl = SizedBox(width: AppSpacing.xl);
  static const SizedBox hXxl = SizedBox(width: AppSpacing.xxl);
}
