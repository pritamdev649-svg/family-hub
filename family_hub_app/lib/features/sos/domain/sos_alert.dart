import 'package:flutter/foundation.dart';

import 'package:family_hub/core/config/app_config.dart';
import 'package:family_hub/shared/json.dart';
import 'package:family_hub/shared/models/geo_point.dart';

export 'package:family_hub/shared/models/geo_point.dart';

/// Lifecycle of an SOS alert (wire: `active|resolved|expired`).
///
/// Unknown values resolve to [expired]: an alert whose state the app does not
/// understand must never start live tracking or look like it still needs
/// help.
enum SosStatus {
  active,
  resolved,
  expired;

  String get wireName => enumWireName(this);

  static SosStatus fromWire(Object? v) => enumByName(values, v, expired);
}

/// How an alert was resolved (wire: `safe|false_alarm|helped`).
enum SosResolution {
  /// The owner tapped "I am okay".
  safe,

  /// The owner cancelled an accidental alert.
  falseAlarm,

  /// An admin marked the member as helped.
  helped;

  String get wireName => enumWireName(this);

  /// `null` for missing / unknown values (e.g. alerts closed by the
  /// member-removal cascade have no outcome).
  static SosResolution? fromWire(Object? v) => enumByNameOrNull(values, v);
}

/// An emergency alert raised by a family member (docs/03-API_CONTRACT.md §10).
///
/// The status is computed lazily by the server, but a list fetched a while
/// ago can still say `active` for an alert whose 15-minute window has passed,
/// so the UI always asks [isActiveAt] / [effectiveStatusAt], which also look
/// at [expiresAt].
@immutable
class SosAlert {
  const SosAlert({
    required this.id,
    required this.memberId,
    required this.status,
    required this.startedAt,
    required this.expiresAt,
    this.memberName,
    this.memberPhone,
    this.memberAvatarUrl,
    this.message,
    this.locationShared = false,
    this.lastLocation,
    this.trail = const <GeoPoint>[],
    this.resolvedAt,
    this.resolvedById,
    this.resolution,
  });

  /// Parses the contract shape defensively: unknown enums fall back, a
  /// missing `startedAt` becomes the epoch and a missing `expiresAt` is
  /// derived from the 15-minute window. Invalid trail points are dropped.
  factory SosAlert.fromJson(Map<String, dynamic> json) {
    final startedAt = parseDateOr(json['startedAt'], _epoch);
    return SosAlert(
      id: asStringOr(json['id'] ?? json['_id'], ''),
      memberId: asStringOr(json['memberId'], ''),
      memberName: asNonEmptyString(json['memberName'])?.trim(),
      memberPhone: asNonEmptyString(json['memberPhone'])?.trim(),
      memberAvatarUrl: asNonEmptyString(json['memberAvatarUrl']),
      status: SosStatus.fromWire(json['status']),
      message: asNonEmptyString(json['message'])?.trim(),
      locationShared: asBool(json['locationShared']),
      lastLocation: GeoPoint.tryParse(json['lastLocation']),
      trail: List<GeoPoint>.unmodifiable(GeoPoint.listFrom(json['trail'])),
      startedAt: startedAt,
      expiresAt:
          parseDate(json['expiresAt']) ??
          startedAt.add(AppConfig.sosTrackingWindow),
      resolvedAt: parseDate(json['resolvedAt']),
      resolvedById: asNonEmptyString(json['resolvedById']),
      resolution: SosResolution.fromWire(json['resolution']),
    );
  }

  static final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(
    0,
    isUtc: true,
  );

  /// Longest optional message (`POST /sos { message }`), UTF-16 code units.
  static const int messageMaxLength = 140;

  /// The server keeps at most this many trail points per alert.
  static const int trailMaxPoints = 100;

  final String id;

  /// Member who raised the alert.
  final String memberId;

  /// `null` when the member no longer belongs to the family.
  final String? memberName;
  final String? memberPhone;
  final String? memberAvatarUrl;

  /// Status as sent by the server (see [effectiveStatusAt]).
  final SosStatus status;
  final String? message;

  /// Whether the owner shares their location for this alert (their sharing
  /// mode is not `never`).
  final bool locationShared;
  final GeoPoint? lastLocation;

  /// Newest ≤ 100 points, oldest first. Only `GET /sos/:id` includes it.
  final List<GeoPoint> trail;
  final DateTime startedAt;

  /// End of the live window (`startedAt + 15 min`).
  final DateTime expiresAt;
  final DateTime? resolvedAt;
  final String? resolvedById;
  final SosResolution? resolution;

  /// Status at [now]: an `active` alert whose window has passed is
  /// [SosStatus.expired].
  SosStatus effectiveStatusAt(DateTime now) {
    if (status == SosStatus.active && !now.isBefore(expiresAt)) {
      return SosStatus.expired;
    }
    return status;
  }

  /// Whether the alert still needs attention at [now].
  bool isActiveAt(DateTime now) => effectiveStatusAt(now) == SosStatus.active;

  /// [isActiveAt] the current time.
  bool get isActive => isActiveAt(DateTime.now());

  /// Time left in the live window at [now] (never negative; zero once the
  /// alert is not active).
  Duration remainingAt(DateTime now) {
    if (!isActiveAt(now)) return Duration.zero;
    return expiresAt.difference(now);
  }

  /// When the alert ended: resolution time, or the end of the window for
  /// an expired alert; `null` while active.
  DateTime? endedAtAsOf(DateTime now) =>
      isActiveAt(now) ? null : (resolvedAt ?? expiresAt);

  bool isOwnedBy(String? memberId) =>
      memberId != null && memberId.isNotEmpty && memberId == this.memberId;

  /// Whether a location may be shown (shared and present).
  bool get hasLocation => locationShared && lastLocation != null;

  /// Newest first (by `startedAt`, then id), like `/sos/active` and
  /// `/sos/history`.
  static int compareNewestFirst(SosAlert a, SosAlert b) {
    final byStart = b.startedAt.compareTo(a.startedAt);
    return byStart != 0 ? byStart : b.id.compareTo(a.id);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'memberId': memberId,
    'memberName': memberName,
    'memberPhone': memberPhone,
    'memberAvatarUrl': memberAvatarUrl,
    'status': status.wireName,
    'message': message,
    'locationShared': locationShared,
    'lastLocation': lastLocation?.toJson(),
    'trail': [for (final p in trail) p.toJson()],
    'startedAt': isoOrNull(startedAt),
    'expiresAt': isoOrNull(expiresAt),
    'resolvedAt': isoOrNull(resolvedAt),
    'resolvedById': resolvedById,
    'resolution': resolution?.wireName,
  };

  /// Nullable fields take a [ValueGetter] so they can be cleared.
  SosAlert copyWith({
    String? id,
    String? memberId,
    ValueGetter<String?>? memberName,
    ValueGetter<String?>? memberPhone,
    ValueGetter<String?>? memberAvatarUrl,
    SosStatus? status,
    ValueGetter<String?>? message,
    bool? locationShared,
    ValueGetter<GeoPoint?>? lastLocation,
    List<GeoPoint>? trail,
    DateTime? startedAt,
    DateTime? expiresAt,
    ValueGetter<DateTime?>? resolvedAt,
    ValueGetter<String?>? resolvedById,
    ValueGetter<SosResolution?>? resolution,
  }) {
    return SosAlert(
      id: id ?? this.id,
      memberId: memberId ?? this.memberId,
      memberName: memberName != null ? memberName() : this.memberName,
      memberPhone: memberPhone != null ? memberPhone() : this.memberPhone,
      memberAvatarUrl: memberAvatarUrl != null
          ? memberAvatarUrl()
          : this.memberAvatarUrl,
      status: status ?? this.status,
      message: message != null ? message() : this.message,
      locationShared: locationShared ?? this.locationShared,
      lastLocation: lastLocation != null ? lastLocation() : this.lastLocation,
      trail: trail != null ? List.unmodifiable(trail) : this.trail,
      startedAt: startedAt ?? this.startedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      resolvedAt: resolvedAt != null ? resolvedAt() : this.resolvedAt,
      resolvedById: resolvedById != null ? resolvedById() : this.resolvedById,
      resolution: resolution != null ? resolution() : this.resolution,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SosAlert &&
          other.id == id &&
          other.memberId == memberId &&
          other.memberName == memberName &&
          other.memberPhone == memberPhone &&
          other.memberAvatarUrl == memberAvatarUrl &&
          other.status == status &&
          other.message == message &&
          other.locationShared == locationShared &&
          other.lastLocation == lastLocation &&
          listEquals(other.trail, trail) &&
          other.startedAt == startedAt &&
          other.expiresAt == expiresAt &&
          other.resolvedAt == resolvedAt &&
          other.resolvedById == resolvedById &&
          other.resolution == resolution;

  @override
  int get hashCode => Object.hash(
    id,
    memberId,
    memberName,
    memberPhone,
    memberAvatarUrl,
    status,
    message,
    locationShared,
    lastLocation,
    Object.hashAll(trail),
    startedAt,
    expiresAt,
    resolvedAt,
    resolvedById,
    resolution,
  );

  @override
  String toString() => 'SosAlert($id, $memberId, ${status.wireName})';
}
