import 'package:flutter/foundation.dart';

import 'package:family_hub/shared/json.dart';
import 'package:family_hub/shared/models/member.dart' show MemberRole;

/// The signed-in account. See docs/03-API_CONTRACT.md §2 "User".
@immutable
class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.name,
    this.emailVerified = false,
    this.locale,
    this.familyId,
    this.memberId,
    this.role,
    this.createdAt,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: asStringOr(json['id'] ?? json['_id'], ''),
      email: asStringOr(json['email'], '').trim().toLowerCase(),
      name: asStringOr(json['name'], '').trim(),
      emailVerified: asBool(json['emailVerified']),
      locale: asNonEmptyString(json['locale'])?.trim(),
      familyId: asNonEmptyString(json['familyId']),
      memberId: asNonEmptyString(json['memberId']),
      role: enumByNameOrNull(MemberRole.values, json['role']),
      createdAt: parseDate(json['createdAt']),
    );
  }

  final String id;

  /// Always trimmed + lower-cased.
  final String email;
  final String name;
  final bool emailVerified;

  /// Preferred language code (`hi`, `ta`, `ar` …) — used by the server for
  /// pushes and emails.
  final String? locale;

  /// `null` when the user has not joined a family yet or was removed.
  final String? familyId;
  final String? memberId;

  /// Role in the family, `null` without a family.
  final MemberRole? role;
  final DateTime? createdAt;

  bool get hasFamily => familyId != null && memberId != null;
  bool get isAdmin => role == MemberRole.admin;

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'name': name,
    'emailVerified': emailVerified,
    'locale': locale,
    'familyId': familyId,
    'memberId': memberId,
    'role': role?.wireName,
    'createdAt': isoOrNull(createdAt),
  };

  /// Nullable fields take a [ValueGetter] so they can be cleared:
  /// `user.copyWith(familyId: () => null)`.
  AuthUser copyWith({
    String? id,
    String? email,
    String? name,
    bool? emailVerified,
    ValueGetter<String?>? locale,
    ValueGetter<String?>? familyId,
    ValueGetter<String?>? memberId,
    ValueGetter<MemberRole?>? role,
    ValueGetter<DateTime?>? createdAt,
  }) {
    return AuthUser(
      id: id ?? this.id,
      email: email ?? this.email,
      name: name ?? this.name,
      emailVerified: emailVerified ?? this.emailVerified,
      locale: locale != null ? locale() : this.locale,
      familyId: familyId != null ? familyId() : this.familyId,
      memberId: memberId != null ? memberId() : this.memberId,
      role: role != null ? role() : this.role,
      createdAt: createdAt != null ? createdAt() : this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthUser &&
          other.id == id &&
          other.email == email &&
          other.name == name &&
          other.emailVerified == emailVerified &&
          other.locale == locale &&
          other.familyId == familyId &&
          other.memberId == memberId &&
          other.role == role &&
          other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(
    id,
    email,
    name,
    emailVerified,
    locale,
    familyId,
    memberId,
    role,
    createdAt,
  );

  @override
  String toString() =>
      'AuthUser($id, verified: $emailVerified, '
      'family: $familyId, role: ${role?.wireName})';
}
