import 'package:flutter/foundation.dart';

import 'package:family_hub/shared/json.dart';

/// A recorded GPS position (`{ lat, lng, accuracy, recordedAt }` in the API).
///
/// Used for `Member.lastLocation` and the SOS `lastLocation` / `trail`.
@immutable
class GeoPoint {
  const GeoPoint({
    required this.lat,
    required this.lng,
    this.accuracy,
    this.recordedAt,
  });

  /// Latitude in degrees, −90..90.
  final double lat;

  /// Longitude in degrees, −180..180.
  final double lng;

  /// Horizontal accuracy radius in metres (`null` when unknown).
  final double? accuracy;

  /// When the fix was recorded (UTC as sent by the server).
  final DateTime? recordedAt;

  /// Parses a location object. Returns `null` when [json] is not an object or
  /// `lat` / `lng` are missing, non-numeric or out of range, so a corrupt
  /// point never ends up on a map.
  static GeoPoint? tryParse(Object? json) {
    if (json is! Map) return null;
    final m = asMap(json);
    final lat = asDoubleOrNull(m['lat'] ?? m['latitude']);
    final lng = asDoubleOrNull(m['lng'] ?? m['lon'] ?? m['longitude']);
    if (lat == null || lng == null) return null;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
    final accuracy = asDoubleOrNull(m['accuracy']);
    return GeoPoint(
      lat: lat,
      lng: lng,
      accuracy: accuracy == null || accuracy < 0 ? null : accuracy,
      recordedAt: parseDate(m['recordedAt']),
    );
  }

  /// Parses a JSON array of points, silently dropping invalid entries.
  static List<GeoPoint> listFrom(Object? json) {
    if (json is! List) return const <GeoPoint>[];
    return [for (final e in json) ?tryParse(e)];
  }

  Map<String, dynamic> toJson() => {
    'lat': lat,
    'lng': lng,
    'accuracy': accuracy,
    'recordedAt': isoOrNull(recordedAt),
  };

  GeoPoint copyWith({
    double? lat,
    double? lng,
    ValueGetter<double?>? accuracy,
    ValueGetter<DateTime?>? recordedAt,
  }) {
    return GeoPoint(
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      accuracy: accuracy != null ? accuracy() : this.accuracy,
      recordedAt: recordedAt != null ? recordedAt() : this.recordedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GeoPoint &&
          other.lat == lat &&
          other.lng == lng &&
          other.accuracy == accuracy &&
          other.recordedAt == recordedAt;

  @override
  int get hashCode => Object.hash(lat, lng, accuracy, recordedAt);

  @override
  String toString() =>
      'GeoPoint($lat, $lng, accuracy: $accuracy, recordedAt: $recordedAt)';
}
