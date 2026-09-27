import 'package:flutter/widgets.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/features/family/domain/member_designation.dart';
import 'package:family_hub/l10n/app_localizations.dart';
import 'package:family_hub/shared/l10n/shared_labels.dart';
import 'package:family_hub/shared/models/member.dart';

// Localised labels of the family feature's enums
// (docs/05-FLUTTER_GUIDE.md §6).

extension DesignationSuggestionLabels on DesignationSuggestion {
  String label(AppLocalizations l10n) => switch (this) {
    DesignationSuggestion.headOfFamily => l10n.familyDesignationHeadOfFamily,
    DesignationSuggestion.financeHead => l10n.familyDesignationFinanceHead,
    DesignationSuggestion.operationsHead =>
      l10n.familyDesignationOperationsHead,
    DesignationSuggestion.healthOfficer => l10n.familyDesignationHealthOfficer,
    DesignationSuggestion.techHead => l10n.familyDesignationTechHead,
    DesignationSuggestion.chiefStudyOfficer =>
      l10n.familyDesignationChiefStudyOfficer,
    DesignationSuggestion.skillBuilder => l10n.familyDesignationSkillBuilder,
    DesignationSuggestion.chiefFunOfficer =>
      l10n.familyDesignationChiefFunOfficer,
    DesignationSuggestion.juniorExplorer =>
      l10n.familyDesignationJuniorExplorer,
    DesignationSuggestion.familyAdvisor => l10n.familyDesignationFamilyAdvisor,
    DesignationSuggestion.chiefMentor => l10n.familyDesignationChiefMentor,
  };
}

extension MemberAccountStatusLabels on MemberAccountStatus {
  /// One-line status for the member detail screen.
  String label(AppLocalizations l10n) => switch (this) {
    MemberAccountStatus.active => l10n.familyAccountActive,
    MemberAccountStatus.invited => l10n.familyAccountInvited,
    MemberAccountStatus.managed => l10n.familyAccountManaged,
  };

  /// Short badge for lists; `null` for members with an account.
  String? badge(AppLocalizations l10n) => switch (this) {
    MemberAccountStatus.active => null,
    MemberAccountStatus.invited => l10n.familyInvitedBadge,
    MemberAccountStatus.managed => l10n.familyNoAccountBadge,
  };

  IconData get icon => switch (this) {
    MemberAccountStatus.active => AppIcons.success,
    MemberAccountStatus.invited => AppIcons.email,
    MemberAccountStatus.managed => AppIcons.memberOutlined,
  };
}

extension MemberAgeLabels on Member {
  /// "Child · 10 years", or `null` without a date of birth.
  String? ageGroupLabel(AppLocalizations l10n) {
    final group = ageGroup;
    final age = ageLabel(l10n);
    if (group == null || age == null) return null;
    return l10n.familyAgeGroupWithAge(group.label(l10n), age);
  }
}
