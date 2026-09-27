import 'package:family_hub/features/emergency_card/domain/emergency_card.dart';
import 'package:family_hub/l10n/app_localizations.dart';

/// Blood groups are shown with their universal symbol (`A+`, `O-`); only
/// [BloodGroup.unknown] is translated.
extension BloodGroupLabels on BloodGroup {
  String label(AppLocalizations l10n) =>
      isKnown ? wireName : l10n.emergencyCardBloodGroupUnknown;

  /// Screen-reader text, e.g. "Blood group B+".
  String semanticLabel(AppLocalizations l10n) =>
      l10n.emergencyCardBloodGroupSemantics(label(l10n));
}

extension EmergencyCardSectionLabels on EmergencyCardSection {
  String label(AppLocalizations l10n) => switch (this) {
    EmergencyCardSection.bloodGroup => l10n.emergencyCardBloodGroup,
    EmergencyCardSection.contacts => l10n.emergencyCardSectionContacts,
    EmergencyCardSection.doctor => l10n.emergencyCardDoctor,
    EmergencyCardSection.insurance => l10n.emergencyCardInsurance,
  };
}

/// How far a card has been filled in (list tiles, card header).
enum EmergencyCardProgress {
  /// Never saved and nothing filled in.
  notStarted,

  /// Some key details are missing.
  partial,

  /// Every key detail is there.
  complete,
}

extension EmergencyCardProgressLabels on EmergencyCard {
  EmergencyCardProgress get progress {
    if (!hasBeenSaved && isEmpty) return EmergencyCardProgress.notStarted;
    return completeness.isComplete
        ? EmergencyCardProgress.complete
        : EmergencyCardProgress.partial;
  }

  /// "Not filled in yet" / "3 of 4 key details" / "All key details added".
  String progressLabel(AppLocalizations l10n) => switch (progress) {
    EmergencyCardProgress.notStarted => l10n.emergencyCardNotStarted,
    EmergencyCardProgress.complete => l10n.emergencyCardComplete,
    EmergencyCardProgress.partial => l10n.emergencyCardCompleteness(
      completeness.filled,
      completeness.total,
    ),
  };
}
