import 'package:family_hub/shared/models/member.dart';

/// Ready-made "company titles" offered as chips in the member form. The
/// designation itself stays free text: picking a suggestion fills the field
/// with its label in the admin's language.
enum DesignationSuggestion {
  headOfFamily,
  financeHead,
  operationsHead,
  healthOfficer,
  techHead,
  chiefStudyOfficer,
  skillBuilder,
  chiefFunOfficer,
  juniorExplorer,
  familyAdvisor,
  chiefMentor;

  /// Age-appropriate suggestions, most fitting first. Without a known age
  /// group a general mix is offered.
  static List<DesignationSuggestion> forAgeGroup(AgeGroup? group) =>
      switch (group) {
        AgeGroup.child => const [juniorExplorer, chiefFunOfficer, skillBuilder],
        AgeGroup.teen => const [
          chiefStudyOfficer,
          skillBuilder,
          techHead,
          chiefFunOfficer,
        ],
        AgeGroup.adult => const [
          headOfFamily,
          financeHead,
          operationsHead,
          healthOfficer,
          techHead,
        ],
        AgeGroup.senior => const [
          familyAdvisor,
          chiefMentor,
          headOfFamily,
          healthOfficer,
        ],
        null => const [
          headOfFamily,
          financeHead,
          chiefStudyOfficer,
          skillBuilder,
          juniorExplorer,
          familyAdvisor,
        ],
      };
}

/// Whether a member can sign in, was invited, or is a managed profile.
enum MemberAccountStatus {
  /// Has their own app account.
  active,

  /// Added with an email (an invitation was sent) but has not joined yet.
  invited,

  /// Managed by admins, no account and no email (young kids, elders).
  managed;

  static MemberAccountStatus of(Member member) {
    if (member.hasAccount) return active;
    return member.email != null ? invited : managed;
  }
}

extension MemberAccountStatusX on Member {
  MemberAccountStatus get accountStatus => MemberAccountStatus.of(this);
}
