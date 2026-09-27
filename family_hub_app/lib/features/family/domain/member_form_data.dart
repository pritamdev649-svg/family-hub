import 'package:flutter/foundation.dart';

import 'package:family_hub/core/config/countries.dart';
import 'package:family_hub/core/utils/date_x.dart' show ageFrom;
import 'package:family_hub/shared/data/family_repository.dart';
import 'package:family_hub/shared/data/repository_utils.dart';
import 'package:family_hub/shared/models/member.dart';

/// Who is using the member form for whom — decides which fields are shown
/// and sent (docs/03-API_CONTRACT.md §6 "PATCH member").
enum MemberFormAccess {
  /// An admin adds a new member.
  adminAdd,

  /// An admin edits another member: every field incl. role.
  adminEdit,

  /// An admin edits their own record: everything except their role (an
  /// admin can never demote themselves from this form).
  adminEditSelf,

  /// A member edits themselves: name, phone, photo, gender, date of birth.
  selfEdit,

  /// Not allowed (a member adding someone or editing another member).
  denied;

  /// Access for the signed-in member ([currentMemberId], [isAdmin]) on
  /// [target] (`null` = adding a new member).
  static MemberFormAccess resolve({
    required bool isAdmin,
    required String? currentMemberId,
    Member? target,
  }) {
    if (target == null) return isAdmin ? adminAdd : denied;
    final isSelf = currentMemberId != null && target.id == currentMemberId;
    if (isAdmin) return isSelf ? adminEditSelf : adminEdit;
    return isSelf ? selfEdit : denied;
  }

  bool get isAllowed => this != denied;

  bool get isAdd => this == adminAdd;

  bool get isSelf => this == adminEditSelf || this == selfEdit;

  /// Admin-only fields: email, designation, guardian consent.
  bool get isAdminAccess =>
      this == adminAdd || this == adminEdit || this == adminEditSelf;

  bool get canEditRole => this == adminAdd || this == adminEdit;

  /// Whether the email of [target] can be edited. An account holder's email
  /// is the one they signed up with, so it is shown read-only.
  bool canEditEmail(Member? target) =>
      isAdminAccess && (target == null || !target.hasAccount);
}

/// Values of the add / edit member form, independent of widgets so the
/// request building and the guardian-consent rule are unit-testable.
@immutable
class MemberFormData {
  const MemberFormData({
    this.name = '',
    this.email,
    this.phone,
    this.avatarUrl,
    this.birthDate,
    this.gender,
    this.designation,
    this.role = MemberRole.member,
    this.guardianConsent = false,
  });

  /// Form values of an existing member ([birthDate] = calendar day).
  factory MemberFormData.fromMember(Member member) => MemberFormData(
    name: member.name,
    email: member.email,
    phone: member.phone,
    avatarUrl: member.avatarUrl,
    birthDate: member.birthDate,
    gender: member.gender,
    designation: member.designation,
    role: member.role,
    guardianConsent: member.guardianConsent,
  );

  final String name;
  final String? email;
  final String? phone;
  final String? avatarUrl;

  /// Calendar day of birth as picked in the form (local midnight).
  final DateTime? birthDate;
  final Gender? gender;
  final String? designation;
  final MemberRole role;

  /// The guardian-consent checkbox (only meaningful for minors).
  final bool guardianConsent;

  /// Completed years on [today] (`null` without a date of birth or when it
  /// lies in the future). Calendar days only: [birthDate] is the picked day.
  int? ageOn(DateTime today) => ageFrom(birthDate, now: today);

  int? get age => ageOn(DateTime.now());

  AgeGroup? get ageGroup {
    final a = age;
    return a == null ? null : AgeGroup.forAge(a);
  }

  /// Whether the person is younger than [country]'s digital age of consent,
  /// i.e. a parent / guardian must consent (`GUARDIAN_CONSENT_REQUIRED`).
  /// Unknown ages need no consent, like on the server.
  bool needsGuardianConsent(CountryInfo country, {DateTime? today}) {
    final a = ageOn(today ?? DateTime.now());
    return a != null && a < country.consentAge;
  }

  /// Body of `POST /family/members`. Consent is only recorded when the
  /// member needs it — by the local rule, or because the server asked for
  /// it ([consentRequired], after `GUARDIAN_CONSENT_REQUIRED`: its consent
  /// table or "today" may differ from the app's). The photo is not part of
  /// the add body — it is saved with a follow-up `PATCH` (see
  /// `MemberEditorController.add`).
  NewMemberRequest toNewMemberRequest(
    CountryInfo country, {
    bool consentRequired = false,
  }) => NewMemberRequest(
    name: name.trim(),
    email: email,
    phone: phone,
    dateOfBirth: birthDate,
    gender: gender,
    designation: designation,
    role: role,
    guardianConsent:
        (consentRequired || needsGuardianConsent(country)) && guardianConsent,
  );

  /// `PATCH /family/members/:id` body with the changes to [before] that
  /// [access] may make. Fields the editor may not change are never sent,
  /// and an unchanged calendar day of birth is not re-sent. See
  /// [toNewMemberRequest] for [consentRequired].
  MemberPatch toPatch(
    Member before,
    MemberFormAccess access,
    CountryInfo country, {
    bool consentRequired = false,
  }) {
    assert(access.isAllowed && !access.isAdd, 'toPatch needs an edit access');
    final birthDateChanged = !_sameDay(birthDate, before.birthDate);
    final after = before.copyWith(
      name: name.trim(),
      phone: () => phone,
      avatarUrl: () => avatarUrl,
      gender: () => gender,
      dateOfBirth: birthDateChanged ? () => birthDate : null,
      email: access.canEditEmail(before) ? () => email : null,
      designation: access.isAdminAccess ? () => trimOrNull(designation) : null,
      role: access.canEditRole ? role : null,
      guardianConsent:
          access.isAdminAccess &&
              (consentRequired || needsGuardianConsent(country))
          ? guardianConsent
          : null,
    );
    return MemberPatch.diff(before, after);
  }

  /// A member of [members] with the same name —
  /// ignoring case, surrounding and repeated spaces — or `null`. Used to
  /// ask before adding a second "Aarav": usually a mistake, or a retry after
  /// an add whose answer was lost (offline / timeout) although the server
  /// created the member.
  Member? sameNameIn(Iterable<Member> members) {
    final key = nameKey(name);
    if (key.isEmpty) return null;
    for (final m in members) {
      if (nameKey(m.name) == key) return m;
    }
    return null;
  }

  /// Comparison key of a person's name (see [sameNameIn]).
  static String nameKey(String name) =>
      name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  MemberFormData copyWith({
    String? name,
    ValueGetter<String?>? email,
    ValueGetter<String?>? phone,
    ValueGetter<String?>? avatarUrl,
    ValueGetter<DateTime?>? birthDate,
    ValueGetter<Gender?>? gender,
    ValueGetter<String?>? designation,
    MemberRole? role,
    bool? guardianConsent,
  }) {
    return MemberFormData(
      name: name ?? this.name,
      email: email != null ? email() : this.email,
      phone: phone != null ? phone() : this.phone,
      avatarUrl: avatarUrl != null ? avatarUrl() : this.avatarUrl,
      birthDate: birthDate != null ? birthDate() : this.birthDate,
      gender: gender != null ? gender() : this.gender,
      designation: designation != null ? designation() : this.designation,
      role: role ?? this.role,
      guardianConsent: guardianConsent ?? this.guardianConsent,
    );
  }

  static bool _sameDay(DateTime? a, DateTime? b) {
    if (a == null || b == null) return a == b;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MemberFormData &&
          other.name == name &&
          other.email == email &&
          other.phone == phone &&
          other.avatarUrl == avatarUrl &&
          _sameDay(other.birthDate, birthDate) &&
          other.gender == gender &&
          other.designation == designation &&
          other.role == role &&
          other.guardianConsent == guardianConsent;

  @override
  int get hashCode => Object.hash(
    name,
    email,
    phone,
    avatarUrl,
    birthDate == null
        ? null
        : Object.hash(birthDate!.year, birthDate!.month, birthDate!.day),
    gender,
    designation,
    role,
    guardianConsent,
  );
}
