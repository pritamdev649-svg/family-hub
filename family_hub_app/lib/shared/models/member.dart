import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show StringCharacters;

import 'package:family_hub/core/config/countries.dart';
import 'package:family_hub/shared/json.dart';
import 'package:family_hub/shared/models/geo_point.dart';

export 'package:family_hub/shared/models/geo_point.dart';

/// A member's permission level inside the family (`admin|member`).
enum MemberRole {
  admin,
  member;

  /// Value sent to / received from the API.
  String get wireName => enumWireName(this);

  static MemberRole fromWire(Object? v, [MemberRole fallback = member]) =>
      enumByName(values, v, fallback);
}

/// Who may see a member's location (wire: `never|sos_only|always`).
/// Privacy by default: unknown / missing values resolve to [never].
enum LocationSharingMode {
  never,
  sosOnly,
  always;

  /// Value sent to / received from the API (`sos_only` for [sosOnly]).
  String get wireName => enumWireName(this);

  static LocationSharingMode fromWire(
    Object? v, [
    LocationSharingMode fallback = never,
  ]) => enumByName(values, v, fallback);

  /// Whether the location may be sent while an SOS is active.
  bool get sharesDuringSos => this != never;

  /// Whether the family can see the last known location at any time.
  bool get sharesAlways => this == always;
}

/// Optional member gender (`male|female|other`); `null` = not specified.
enum Gender {
  male,
  female,
  other;

  String get wireName => enumWireName(this);

  static Gender? fromWire(Object? v) => enumByNameOrNull(values, v);
}

/// Age bands used for age-appropriate duties and UI:
/// child < 13, teen 13–17, adult 18–59, senior 60+.
enum AgeGroup {
  child,
  teen,
  adult,
  senior;

  static AgeGroup forAge(int age) {
    if (age < 13) return child;
    if (age < 18) return teen;
    if (age < 60) return adult;
    return senior;
  }
}

/// A person in the family — with or without an app account
/// (members without an account are "managed profiles", e.g. young kids or
/// elders without a phone). See docs/03-API_CONTRACT.md §2 "Member".
@immutable
class Member {
  const Member({
    required this.id,
    required this.familyId,
    required this.name,
    this.userId,
    this.email,
    this.phone,
    this.avatarUrl,
    this.dateOfBirth,
    this.gender,
    this.designation,
    this.role = MemberRole.member,
    this.hasAccount = false,
    this.locationSharing = LocationSharingMode.never,
    this.lastLocation,
    this.guardianConsent = false,
    this.createdAt,
    this.updatedAt,
  });

  factory Member.fromJson(Map<String, dynamic> json) {
    final userId = asNonEmptyString(json['userId']);
    return Member(
      id: asStringOr(json['id'] ?? json['_id'], ''),
      familyId: asStringOr(json['familyId'], ''),
      userId: userId,
      name: asStringOr(json['name'], '').trim(),
      email: asNonEmptyString(json['email']),
      phone: asNonEmptyString(json['phone']),
      avatarUrl: asNonEmptyString(json['avatarUrl']),
      dateOfBirth: parseDate(json['dateOfBirth']),
      gender: Gender.fromWire(json['gender']),
      designation: asNonEmptyString(json['designation'])?.trim(),
      role: MemberRole.fromWire(json['role']),
      hasAccount: json.containsKey('hasAccount')
          ? asBool(json['hasAccount'], userId != null)
          : userId != null,
      locationSharing: LocationSharingMode.fromWire(json['locationSharing']),
      lastLocation: GeoPoint.tryParse(json['lastLocation']),
      guardianConsent: asBool(json['guardianConsent']),
      createdAt: parseDate(json['createdAt']),
      updatedAt: parseDate(json['updatedAt']),
    );
  }

  final String id;
  final String familyId;

  /// Linked account (`null` for managed profiles).
  final String? userId;
  final String name;
  final String? email;
  final String? phone;
  final String? avatarUrl;

  /// Date-only value; use [birthDate] for the calendar day.
  final DateTime? dateOfBirth;
  final Gender? gender;

  /// Free-text "company title", e.g. *Head of Family*, *Finance Head*.
  final String? designation;
  final MemberRole role;
  final bool hasAccount;
  final LocationSharingMode locationSharing;

  /// Only present when [locationSharing] is `always` (server enforced).
  final GeoPoint? lastLocation;
  final bool guardianConsent;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isAdmin => role == MemberRole.admin;

  /// `true` for profiles managed by admins (no login of their own).
  bool get isManagedProfile => !hasAccount;

  /// Calendar day of birth (local midnight), see [calendarDate].
  DateTime? get birthDate => calendarDate(dateOfBirth);

  /// Completed years of age on [date] (`null` without a date of birth or when
  /// the date of birth lies after [date]).
  int? ageOn(DateTime date) {
    final b = birthDate;
    if (b == null) return null;
    var years = date.year - b.year;
    if (date.month < b.month || (date.month == b.month && date.day < b.day)) {
      years--;
    }
    return years < 0 ? null : years;
  }

  /// Current age in completed years, `null` when unknown.
  int? get age => ageOn(DateTime.now());

  /// Age band derived from [age], `null` when the date of birth is unknown.
  AgeGroup? get ageGroup {
    final a = age;
    return a == null ? null : AgeGroup.forAge(a);
  }

  /// Whether this member is below [country]'s digital age of consent, i.e.
  /// a guardian must consent for them. Unknown age → `false`.
  bool isMinorIn(CountryInfo country) {
    final a = age;
    return a != null && a < country.consentAge;
  }

  /// Up to two upper-cased initials (first letter of the first and last word),
  /// grapheme-aware so Indic / Arabic / emoji names work. `?` for blank names.
  String get initials => initialsOf(name);

  /// Shared implementation of [initials] (also usable for plain names).
  static String initialsOf(String? name) {
    final words = (name ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return '?';
    String first(String w) => w.characters.first.toUpperCase();
    if (words.length == 1) return first(words.first);
    return '${first(words.first)}${first(words.last)}';
  }

  /// Server ordering of `GET /family/members`: admins first, then oldest →
  /// youngest (unknown date of birth last), then name.
  static int compare(Member a, Member b) {
    if (a.isAdmin != b.isAdmin) return a.isAdmin ? -1 : 1;
    final da = a.dateOfBirth;
    final db = b.dateOfBirth;
    if (da != null && db != null) {
      final c = da.compareTo(db);
      if (c != 0) return c;
    } else if (da != null || db != null) {
      return da != null ? -1 : 1;
    }
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'familyId': familyId,
    'userId': userId,
    'name': name,
    'email': email,
    'phone': phone,
    'avatarUrl': avatarUrl,
    'dateOfBirth': isoOrNull(dateOfBirth),
    'gender': gender?.wireName,
    'designation': designation,
    'role': role.wireName,
    'hasAccount': hasAccount,
    'locationSharing': locationSharing.wireName,
    'lastLocation': lastLocation?.toJson(),
    'guardianConsent': guardianConsent,
    'createdAt': isoOrNull(createdAt),
    'updatedAt': isoOrNull(updatedAt),
  };

  /// Nullable fields take a [ValueGetter] so they can be cleared:
  /// `member.copyWith(phone: () => null)`.
  Member copyWith({
    String? id,
    String? familyId,
    ValueGetter<String?>? userId,
    String? name,
    ValueGetter<String?>? email,
    ValueGetter<String?>? phone,
    ValueGetter<String?>? avatarUrl,
    ValueGetter<DateTime?>? dateOfBirth,
    ValueGetter<Gender?>? gender,
    ValueGetter<String?>? designation,
    MemberRole? role,
    bool? hasAccount,
    LocationSharingMode? locationSharing,
    ValueGetter<GeoPoint?>? lastLocation,
    bool? guardianConsent,
    ValueGetter<DateTime?>? createdAt,
    ValueGetter<DateTime?>? updatedAt,
  }) {
    return Member(
      id: id ?? this.id,
      familyId: familyId ?? this.familyId,
      userId: userId != null ? userId() : this.userId,
      name: name ?? this.name,
      email: email != null ? email() : this.email,
      phone: phone != null ? phone() : this.phone,
      avatarUrl: avatarUrl != null ? avatarUrl() : this.avatarUrl,
      dateOfBirth: dateOfBirth != null ? dateOfBirth() : this.dateOfBirth,
      gender: gender != null ? gender() : this.gender,
      designation: designation != null ? designation() : this.designation,
      role: role ?? this.role,
      hasAccount: hasAccount ?? this.hasAccount,
      locationSharing: locationSharing ?? this.locationSharing,
      lastLocation: lastLocation != null ? lastLocation() : this.lastLocation,
      guardianConsent: guardianConsent ?? this.guardianConsent,
      createdAt: createdAt != null ? createdAt() : this.createdAt,
      updatedAt: updatedAt != null ? updatedAt() : this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Member &&
          other.id == id &&
          other.familyId == familyId &&
          other.userId == userId &&
          other.name == name &&
          other.email == email &&
          other.phone == phone &&
          other.avatarUrl == avatarUrl &&
          other.dateOfBirth == dateOfBirth &&
          other.gender == gender &&
          other.designation == designation &&
          other.role == role &&
          other.hasAccount == hasAccount &&
          other.locationSharing == locationSharing &&
          other.lastLocation == lastLocation &&
          other.guardianConsent == guardianConsent &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    id,
    familyId,
    userId,
    name,
    email,
    phone,
    avatarUrl,
    dateOfBirth,
    gender,
    designation,
    role,
    hasAccount,
    locationSharing,
    lastLocation,
    guardianConsent,
    createdAt,
    updatedAt,
  );

  @override
  String toString() => 'Member($id, $name, ${role.wireName})';
}
