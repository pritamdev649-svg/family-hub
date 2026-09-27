import 'package:flutter/foundation.dart';

import 'package:family_hub/core/network/api_client.dart';
import 'package:family_hub/shared/data/repository_utils.dart';
import 'package:family_hub/shared/json.dart';
import 'package:family_hub/shared/models/family.dart';
import 'package:family_hub/shared/models/member.dart';
import 'package:family_hub/shared/models/session_state.dart';

/// Body of `POST /family` and the `family` object of register (create mode).
@immutable
class CreateFamilyRequest {
  const CreateFamilyRequest({
    required this.name,
    required this.country,
    required this.currency,
    required this.timezone,
  });

  final String name;

  /// ISO 3166-1 alpha-2.
  final String country;

  /// ISO 4217.
  final String currency;

  /// IANA time zone, e.g. `Asia/Kolkata`.
  final String timezone;

  Map<String, dynamic> toJson() => {
    'name': name.trim(),
    'country': country.trim().toUpperCase(),
    'currency': currency.trim().toUpperCase(),
    'timezone': timezone.trim(),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CreateFamilyRequest &&
          other.name == name &&
          other.country == country &&
          other.currency == currency &&
          other.timezone == timezone;

  @override
  int get hashCode => Object.hash(name, country, currency, timezone);
}

/// Body of `PATCH /family` (admin) — only the given, non-blank fields are
/// sent.
class FamilyPatch extends PatchBody {
  factory FamilyPatch({
    String? name,
    String? country,
    String? currency,
    String? timezone,
  }) {
    return FamilyPatch._(
      Map.unmodifiable(<String, dynamic>{
        'name': ?trimOrNull(name),
        'country': ?trimOrNull(country)?.toUpperCase(),
        'currency': ?trimOrNull(currency)?.toUpperCase(),
        'timezone': ?trimOrNull(timezone),
      }),
    );
  }

  /// Only the values that differ from [before] (settings form result).
  factory FamilyPatch.diff(
    Family before, {
    String? name,
    String? country,
    String? currency,
    String? timezone,
  }) {
    final d = PatchDiff<Never>();
    return FamilyPatch(
      name: d(before.name, trimOrNull(name) ?? before.name),
      country: d(
        before.country,
        trimOrNull(country)?.toUpperCase() ?? before.country,
      ),
      currency: d(
        before.currency,
        trimOrNull(currency)?.toUpperCase() ?? before.currency,
      ),
      timezone: d(before.timezone, trimOrNull(timezone) ?? before.timezone),
    );
  }

  const FamilyPatch._(super.fields);
}

/// Body of `POST /family/members` (admin). Members without an email are
/// managed profiles (`hasAccount=false`); with an email the server sends an
/// invitation with the family invite code.
@immutable
class NewMemberRequest {
  const NewMemberRequest({
    required this.name,
    this.email,
    this.phone,
    this.dateOfBirth,
    this.gender,
    this.designation,
    this.role = MemberRole.member,
    this.guardianConsent = false,
  });

  final String name;
  final String? email;
  final String? phone;
  final DateTime? dateOfBirth;
  final Gender? gender;
  final String? designation;
  final MemberRole role;

  /// Required (`true`) when the member is younger than the family country's
  /// consent age, else `GUARDIAN_CONSENT_REQUIRED`.
  final bool guardianConsent;

  /// Contract-exact body; blank optional text is sent as `null`.
  Map<String, dynamic> toJson() => {
    'name': name.trim(),
    'email': normalizeEmail(email),
    'phone': normalizePhone(phone),
    'dateOfBirth': isoOrNull(dateOfBirth),
    'gender': gender?.wireName,
    'designation': trimOrNull(designation),
    'role': role.wireName,
    'guardianConsent': guardianConsent,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NewMemberRequest && mapEquals(other.toJson(), toJson());

  @override
  int get hashCode => Object.hashAllUnordered(
    toJson().entries.map((e) => Object.hash(e.key, e.value)),
  );
}

/// Nullable member fields a [MemberPatch] can explicitly clear (send `null`).
enum MemberPatchField {
  email,
  phone,
  avatarUrl,
  dateOfBirth,
  gender,
  designation,
}

/// Body of `PATCH /family/members/:id`. Only the given fields are sent;
/// fields listed in `clear` are sent as `null`.
///
/// Admins may change every field incl. `role`; a non-admin may patch only
/// themselves and only `name, phone, avatarUrl, gender, dateOfBirth`
/// (else `FORBIDDEN`). Demoting the last admin → `LAST_ADMIN`.
///
/// Location sharing is deliberately **not** patchable here: it is controlled
/// by the member themselves through `PATCH /me` (privacy by design).
class MemberPatch extends PatchBody {
  factory MemberPatch({
    String? name,
    String? email,
    String? phone,
    String? avatarUrl,
    DateTime? dateOfBirth,
    Gender? gender,
    String? designation,
    MemberRole? role,
    bool? guardianConsent,
    Set<MemberPatchField> clear = const {},
  }) {
    return MemberPatch._(
      Map.unmodifiable(<String, dynamic>{
        for (final f in clear) f.name: null,
        'name': ?trimOrNull(name),
        'email': ?normalizeEmail(email),
        'phone': ?normalizePhone(phone),
        'avatarUrl': ?trimOrNull(avatarUrl),
        'dateOfBirth': ?isoOrNull(dateOfBirth),
        'gender': ?gender?.wireName,
        'designation': ?trimOrNull(designation),
        'role': ?role?.wireName,
        'guardianConsent': ?guardianConsent,
      }),
    );
  }

  /// The changes between [before] and [after] (e.g. an edit form's result):
  /// changed fields are set, fields cleared in [after] are sent as `null`.
  factory MemberPatch.diff(Member before, Member after) {
    final d = PatchDiff<MemberPatchField>();
    return MemberPatch(
      name: d(before.name.trim(), after.name.trim()),
      email: d(
        normalizeEmail(before.email),
        normalizeEmail(after.email),
        MemberPatchField.email,
      ),
      phone: d(
        normalizePhone(before.phone),
        normalizePhone(after.phone),
        MemberPatchField.phone,
      ),
      avatarUrl: d(
        trimOrNull(before.avatarUrl),
        trimOrNull(after.avatarUrl),
        MemberPatchField.avatarUrl,
      ),
      dateOfBirth: d(
        before.dateOfBirth,
        after.dateOfBirth,
        MemberPatchField.dateOfBirth,
      ),
      gender: d(before.gender, after.gender, MemberPatchField.gender),
      designation: d(
        trimOrNull(before.designation),
        trimOrNull(after.designation),
        MemberPatchField.designation,
      ),
      role: d(before.role, after.role),
      guardianConsent: d(before.guardianConsent, after.guardianConsent),
      clear: d.cleared,
    );
  }

  const MemberPatch._(super.fields);
}

/// `/family` endpoints (docs/03-API_CONTRACT.md §6). Emergency cards live in
/// the `emergency_card` feature.
class FamilyRepository {
  FamilyRepository(this._api);

  final ApiClient _api;

  /// `POST /family` (user without a family) → `{ user, family, member }`.
  /// Errors: `ALREADY_IN_FAMILY`, `VALIDATION_ERROR`.
  Future<SessionState> createFamily(CreateFamilyRequest request) async {
    final data = await _api.post('/family', body: request.toJson());
    return _membership(data);
  }

  /// `POST /family/join` → `{ user, family, member }`.
  /// Errors: `INVALID_INVITE_CODE`, `ALREADY_IN_FAMILY`.
  Future<SessionState> joinFamily(String inviteCode) async {
    final data = await _api.post(
      '/family/join',
      body: {'inviteCode': normalizeInviteCode(inviteCode)},
    );
    return _membership(data);
  }

  /// `GET /family`.
  Future<Family> getFamily() async =>
      Family.fromJson(requireObject(await _api.get('/family'), 'family'));

  /// `PATCH /family` (admin).
  Future<Family> updateFamily(FamilyPatch patch) async => Family.fromJson(
    requireObject(await _api.patch('/family', body: patch.toJson()), 'family'),
  );

  /// `POST /family/invite-code` (admin) — the old code stops working.
  Future<Family> regenerateInviteCode() async => Family.fromJson(
    requireObject(await _api.post('/family/invite-code'), 'family'),
  );

  /// `GET /family/members` — admins first, then oldest → youngest (server
  /// order is kept). Entries without an id are dropped.
  Future<List<Member>> getMembers() async {
    final list = requireList(await _api.get('/family/members'));
    return List.unmodifiable(
      asMapList(list, Member.fromJson).where((m) => m.id.isNotEmpty),
    );
  }

  /// `GET /family/members/:id`. Errors: `NOT_FOUND` (also for other families).
  Future<Member> getMember(String id) async =>
      _member(await _api.get('/family/members/${pathId(id)}'));

  /// `POST /family/members` (admin) → `201 Member`. Errors:
  /// `GUARDIAN_CONSENT_REQUIRED`, `MEMBER_EMAIL_EXISTS`, `VALIDATION_ERROR`.
  Future<Member> addMember(NewMemberRequest request) async =>
      _member(await _api.post('/family/members', body: request.toJson()));

  /// `PATCH /family/members/:id`. Errors: `FORBIDDEN`, `LAST_ADMIN`,
  /// `MEMBER_EMAIL_EXISTS`, `VALIDATION_ERROR`.
  Future<Member> updateMember(String id, MemberPatch patch) async => _member(
    await _api.patch('/family/members/${pathId(id)}', body: patch.toJson()),
  );

  /// `DELETE /family/members/:id` (admin). Errors: `LAST_ADMIN`, `NOT_FOUND`.
  Future<void> deleteMember(String id) async {
    await _api.delete('/family/members/${pathId(id)}');
  }

  Member _member(Object? data) {
    final member = Member.fromJson(requireObject(data));
    if (member.id.isEmpty) {
      throw const ApiException.unknown('Malformed response: member without id');
    }
    return member;
  }

  SessionState _membership(Object? data) {
    final session = SessionState.fromJson(requireObject(data));
    if (!session.isSignedIn ||
        session.member == null ||
        session.family == null) {
      throw const ApiException.unknown(
        'Malformed response: expected { user, family, member }',
      );
    }
    return session;
  }
}
