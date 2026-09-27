import 'package:family_hub/core/design/design.dart';

/// Which accent each part of an emergency card uses
/// (docs/12-DESIGN_LANGUAGE.md: "colour = meaning"). The module itself is
/// rose ([AppAccents.emergency]); every section gets its own colour so the
/// card reads at a glance, and the same colours are used on the card, in the
/// responder view and in the form.
abstract final class EmergencyCardAccents {
  /// The module accent: headers, blood group, "Emergency card" markers.
  static const AppAccent module = AppAccents.emergency;

  static const AppAccent bloodGroup = AppAccents.emergency;
  static const AppAccent allergies = AppAccent.amber;
  static const AppAccent medications = AppAccent.violet;
  static const AppAccent conditions = AppAccent.rose;
  static const AppAccent contacts = AppAccent.sky;
  static const AppAccent doctor = AppAccent.blue;
  static const AppAccent insurance = AppAccent.emerald;
  static const AppAccent notes = AppAccent.indigo;

  /// Round call button next to an emergency contact.
  static const AppAccent callContact = AppAccent.emerald;

  /// Round call button next to the doctor.
  static const AppAccent callDoctor = AppAccent.blue;

  // Completeness of a card.
  static const AppAccent complete = AppAccents.success;
  static const AppAccent incomplete = AppAccents.warning;
}
