import 'package:flutter/widgets.dart';

/// Corner radius scale.
///
/// * `xs` – checkboxes, tiny badges
/// * `sm` – chips inside cards, small thumbnails
/// * `md` – inputs, buttons, list tiles, snackbars
/// * `lg` – cards (the default card shape)
/// * `xl` – dialogs, bottom sheets, hero surfaces
/// * `pill` – fully rounded (progress bars, status chips)
abstract final class AppRadius {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;

  /// Cards, tiles and hero containers.
  static const double card = 20;
  /// Bottom corners of the full-bleed gradient header.
  static const double hero = 32;
  static const double pill = 999;

  static const BorderRadius brXs = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius brSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius brMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius brLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius brXl = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius brCard = BorderRadius.all(Radius.circular(card));
  static const BorderRadius brPill = BorderRadius.all(Radius.circular(pill));

  /// Only the top corners rounded (bottom sheets).
  static const BorderRadius brTopXl = BorderRadius.vertical(
    top: Radius.circular(xl),
  );
}
