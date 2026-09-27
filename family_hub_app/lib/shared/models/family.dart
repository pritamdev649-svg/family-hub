import 'package:flutter/foundation.dart';

import 'package:family_hub/core/config/countries.dart';
import 'package:family_hub/shared/json.dart';

/// The family ("the company"). See docs/03-API_CONTRACT.md §2 "Family".
@immutable
class Family {
  const Family({
    required this.id,
    required this.name,
    required this.country,
    required this.currency,
    required this.timezone,
    this.inviteCode,
    this.ownerId,
    this.memberCount = 0,
    this.createdAt,
  });

  /// Missing `country` falls back to [Countries.fallback]; missing `currency`
  /// falls back to the country's default currency, missing `timezone` to UTC.
  factory Family.fromJson(Map<String, dynamic> json) {
    final country =
        asNonEmptyString(json['country'])?.trim().toUpperCase() ??
        Countries.fallback.code;
    return Family(
      id: asStringOr(json['id'] ?? json['_id'], ''),
      name: asStringOr(json['name'], '').trim(),
      inviteCode: asNonEmptyString(json['inviteCode'])?.trim().toUpperCase(),
      country: country,
      currency:
          asNonEmptyString(json['currency'])?.trim().toUpperCase() ??
          Countries.byCode(country).currency,
      timezone: asNonEmptyString(json['timezone'])?.trim() ?? defaultTimezone,
      ownerId: asNonEmptyString(json['ownerId']),
      memberCount: asInt(json['memberCount']).clamp(0, 1 << 31),
      createdAt: parseDate(json['createdAt']),
    );
  }

  static const defaultTimezone = 'UTC';

  final String id;
  final String name;

  /// 8-char invite code — only returned to admins (`null` for members).
  final String? inviteCode;

  /// ISO 3166-1 alpha-2, upper-case (e.g. `IN`).
  final String country;

  /// ISO 4217, upper-case (e.g. `INR`).
  final String currency;

  /// IANA time zone (e.g. `Asia/Kolkata`).
  final String timezone;

  /// User id of the creator.
  final String? ownerId;
  final int memberCount;
  final DateTime? createdAt;

  /// Country defaults (emergency number, consent age, dial code …).
  CountryInfo get countryInfo => Countries.byCode(country);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'inviteCode': inviteCode,
    'country': country,
    'currency': currency,
    'timezone': timezone,
    'ownerId': ownerId,
    'memberCount': memberCount,
    'createdAt': isoOrNull(createdAt),
  };

  /// Nullable fields take a [ValueGetter] so they can be cleared.
  Family copyWith({
    String? id,
    String? name,
    ValueGetter<String?>? inviteCode,
    String? country,
    String? currency,
    String? timezone,
    ValueGetter<String?>? ownerId,
    int? memberCount,
    ValueGetter<DateTime?>? createdAt,
  }) {
    return Family(
      id: id ?? this.id,
      name: name ?? this.name,
      inviteCode: inviteCode != null ? inviteCode() : this.inviteCode,
      country: country ?? this.country,
      currency: currency ?? this.currency,
      timezone: timezone ?? this.timezone,
      ownerId: ownerId != null ? ownerId() : this.ownerId,
      memberCount: memberCount ?? this.memberCount,
      createdAt: createdAt != null ? createdAt() : this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Family &&
          other.id == id &&
          other.name == name &&
          other.inviteCode == inviteCode &&
          other.country == country &&
          other.currency == currency &&
          other.timezone == timezone &&
          other.ownerId == ownerId &&
          other.memberCount == memberCount &&
          other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    inviteCode,
    country,
    currency,
    timezone,
    ownerId,
    memberCount,
    createdAt,
  );

  @override
  String toString() => 'Family($id, $name, $country/$currency)';
}
