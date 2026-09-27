import 'package:flutter/material.dart';

import 'package:family_hub/l10n/app_localizations.dart';
import 'package:family_hub/shared/models/member.dart';

import 'package:family_hub/core/design/app_icons.dart';

// Localised labels for the shared domain enums (docs/05-FLUTTER_GUIDE.md §6).
// Usage: `member.role.label(context.l10n)`.

extension MemberRoleLabels on MemberRole {
  String label(AppLocalizations l10n) => switch (this) {
    MemberRole.admin => l10n.roleAdmin,
    MemberRole.member => l10n.roleMember,
  };

  /// One-line explanation for role pickers.
  String description(AppLocalizations l10n) => switch (this) {
    MemberRole.admin => l10n.roleAdminDescription,
    MemberRole.member => l10n.roleMemberDescription,
  };

  IconData get icon => switch (this) {
    MemberRole.admin => AppIcons.roleAdmin,
    MemberRole.member => AppIcons.roleMember,
  };
}

extension GenderLabels on Gender {
  String label(AppLocalizations l10n) => switch (this) {
    Gender.male => l10n.genderMale,
    Gender.female => l10n.genderFemale,
    Gender.other => l10n.genderOther,
  };
}

/// Label for an optional gender (`null` → "Prefer not to say").
extension NullableGenderLabels on Gender? {
  String labelOrUnspecified(AppLocalizations l10n) =>
      this?.label(l10n) ?? l10n.genderUnspecified;
}

extension AgeGroupLabels on AgeGroup {
  String label(AppLocalizations l10n) => switch (this) {
    AgeGroup.child => l10n.ageGroupChild,
    AgeGroup.teen => l10n.ageGroupTeen,
    AgeGroup.adult => l10n.ageGroupAdult,
    AgeGroup.senior => l10n.ageGroupSenior,
  };
}

extension LocationSharingModeLabels on LocationSharingMode {
  String label(AppLocalizations l10n) => switch (this) {
    LocationSharingMode.never => l10n.locationSharingNever,
    LocationSharingMode.sosOnly => l10n.locationSharingSosOnly,
    LocationSharingMode.always => l10n.locationSharingAlways,
  };

  /// One-line explanation, e.g. under a radio option.
  String description(AppLocalizations l10n) => switch (this) {
    LocationSharingMode.never => l10n.locationSharingNeverDescription,
    LocationSharingMode.sosOnly => l10n.locationSharingSosOnlyDescription,
    LocationSharingMode.always => l10n.locationSharingAlwaysDescription,
  };

  IconData get icon => switch (this) {
    LocationSharingMode.never => AppIcons.locationNever,
    LocationSharingMode.sosOnly => AppIcons.locationSosOnly,
    LocationSharingMode.always => AppIcons.locationAlways,
  };
}

extension MemberLabels on Member {
  /// "12 years" / "Under 1 year", or `null` when the date of birth is unknown.
  String? ageLabel(AppLocalizations l10n) {
    final a = age;
    return a == null ? null : l10n.ageYears(a);
  }

  /// The member's designation ("Finance Head"), or the role label when no
  /// designation is set — for list subtitles.
  String titleOrRole(AppLocalizations l10n) => designation ?? role.label(l10n);
}
