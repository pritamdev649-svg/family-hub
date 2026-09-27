import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/providers/core_providers.dart';
import 'package:family_hub/features/sos/domain/sos_alert.dart';
import 'package:family_hub/shared/data/repository_utils.dart';

/// `/sos` endpoints (docs/03-API_CONTRACT.md §10).
class SosRepository {
  SosRepository(this._api);

  final ApiClient _api;

  /// Largest page `GET /sos/history` accepts.
  static const int maxPageSize = 100;

  /// `POST /sos`. Returns the new alert, or the caller's already active one
  /// (idempotent — so retrying after a lost response is safe). The server
  /// drops [location] when the caller's sharing mode is `never`.
  /// A blank [message] is omitted; longer messages are cut to
  /// [SosAlert.messageMaxLength]. A [location] the server would reject
  /// (non-finite / out-of-range coordinates) is left out, so the alert
  /// itself always goes through.
  Future<SosAlert> create({GeoPoint? location, String? message}) async {
    final text = trimOrNull(message);
    final point = location == null ? null : wirePoint(location);
    final data = await _api.post(
      '/sos',
      body: {
        'location': ?point,
        if (text != null) 'message': clampMessage(text),
      },
    );
    return _alert(data);
  }

  /// Cuts [text] to [SosAlert.messageMaxLength] UTF-16 code units without
  /// splitting a surrogate pair (an SOS must never fail validation).
  static String clampMessage(String text) {
    const max = SosAlert.messageMaxLength;
    if (text.length <= max) return text;
    final last = text.codeUnitAt(max - 1);
    final isHighSurrogate = last >= 0xD800 && last <= 0xDBFF;
    return text.substring(0, isHighSurrogate ? max - 1 : max);
  }

  /// `GET /sos/active` — the family's active alerts (the caller's included),
  /// newest first.
  Future<List<SosAlert>> active() async {
    final list = requireList(await _api.get('/sos/active'));
    return List.unmodifiable([
      for (final e in list)
        if (e is Map) SosAlert.fromJson(Map<String, dynamic>.from(e)),
    ]);
  }

  /// `GET /sos/history?page&limit` — resolved / expired alerts, newest first.
  Future<Paged<SosAlert>> history({int page = 1, int limit = 20}) =>
      _api.getPaged<SosAlert>(
        '/sos/history',
        SosAlert.fromJson,
        page: page,
        limit: limit.clamp(1, maxPageSize),
      );

  /// `GET /sos/:id` (includes the trail). Errors: `NOT_FOUND`.
  Future<SosAlert> get(String id) async =>
      _alert(await _api.get('/sos/${pathId(id)}'));

  /// `POST /sos/:id/location` (owner only). Updates arriving < 3 s after the
  /// previous one are accepted but not stored.
  /// Errors: `SOS_NOT_ACTIVE`, `LOCATION_SHARING_DISABLED`, `FORBIDDEN`,
  /// `NOT_FOUND`; an unusable [point] fails locally with
  /// `VALIDATION_ERROR` (nothing is sent).
  Future<SosAlert> sendLocation(String id, GeoPoint point) async {
    final body = wirePoint(point);
    if (body == null) {
      throw const ApiException(
        code: ApiErrorCode.validation,
        message: 'Unusable location',
        statusCode: 422,
      );
    }
    return _alert(await _api.post('/sos/${pathId(id)}/location', body: body));
  }

  /// `POST /sos/:id/resolve` (owner or admin). Idempotent on an already
  /// resolved alert. Errors: `SOS_NOT_ACTIVE` (expired), `FORBIDDEN`,
  /// `NOT_FOUND`.
  Future<SosAlert> resolve(String id, SosResolution resolution) async => _alert(
    await _api.post(
      '/sos/${pathId(id)}/resolve',
      body: {'resolution': resolution.wireName},
    ),
  );

  /// Largest `accuracy` (metres) the server accepts (backend `latLng`).
  static const double maxAccuracyMeters = 100000;

  /// `{ lat, lng, accuracy? }` as the server validates it (backend `latLng`:
  /// finite numbers, lat −90..90, lng −180..180, accuracy 0..100 km), or
  /// `null` when the coordinates are unusable. An accuracy outside the
  /// range (negative, non-finite, or a coarse fix of more than 100 km) is
  /// omitted rather than failing the request.
  static Map<String, dynamic>? wirePoint(GeoPoint p) {
    final lat = p.lat;
    final lng = p.lng;
    if (!lat.isFinite || !lng.isFinite || lat.abs() > 90 || lng.abs() > 180) {
      return null;
    }
    final accuracy = p.accuracy;
    return {
      'lat': lat,
      'lng': lng,
      if (accuracy != null &&
          accuracy.isFinite &&
          accuracy >= 0 &&
          accuracy <= maxAccuracyMeters)
        'accuracy': accuracy,
    };
  }

  static SosAlert _alert(Object? data) {
    final alert = SosAlert.fromJson(requireObject(data));
    if (alert.id.isEmpty) {
      throw const ApiException.unknown('Malformed response: alert without id');
    }
    return alert;
  }
}

final sosRepositoryProvider = Provider<SosRepository>(
  (ref) => SosRepository(ref.watch(apiClientProvider)),
);
