import 'package:dio/dio.dart';

import 'package:family_hub/core/network/api_exception.dart';
import 'package:family_hub/core/network/paged.dart';

export 'package:family_hub/core/network/api_exception.dart';
export 'package:family_hub/core/network/paged.dart';

/// Thin wrapper over [Dio] that speaks the API envelope.
///
/// Every method returns the **unwrapped** `data` of
/// `{ success: true, data, meta? }` and throws only [ApiException].
/// Paths are relative to `/api/v1`, e.g. `/tasks/$id/complete`.
class ApiClient {
  ApiClient(this._dio);

  final Dio _dio;

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _send(() => _dio.get<dynamic>(path, queryParameters: _clean(query)));

  Future<dynamic> post(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) => _send(
    () => _dio.post<dynamic>(path, data: body, queryParameters: _clean(query)),
  );

  Future<dynamic> patch(String path, {Object? body}) =>
      _send(() => _dio.patch<dynamic>(path, data: body));

  Future<dynamic> put(String path, {Object? body}) =>
      _send(() => _dio.put<dynamic>(path, data: body));

  Future<dynamic> delete(String path, {Object? body}) =>
      _send(() => _dio.delete<dynamic>(path, data: body));

  /// `GET` a paginated list. Items that are not JSON objects are skipped;
  /// [fromJson] should parse defensively (never throw on odd data).
  Future<Paged<T>> getPaged<T>(
    String path,
    T Function(Map<String, dynamic> json) fromJson, {
    Map<String, dynamic>? query,
    int page = 1,
    int limit = 20,
  }) async {
    final safePage = page < 1 ? 1 : page;
    final safeLimit = limit.clamp(1, 100);
    final body = await _request(
      () => _dio.get<dynamic>(
        path,
        queryParameters: {
          ...?_clean(query),
          'page': safePage,
          'limit': safeLimit,
        },
      ),
    );
    final data = body['data'];
    final list = data is List ? data : const <dynamic>[];
    final items = <T>[
      for (final e in list)
        if (e is Map) fromJson(Map<String, dynamic>.from(e)),
    ];
    final meta = body['meta'] is Map ? body['meta'] as Map : const {};
    final metaPage = _asInt(meta['page']) ?? safePage;
    final metaLimit = _asInt(meta['limit']) ?? safeLimit;
    final total =
        _asInt(meta['total']) ?? ((metaPage - 1) * metaLimit + items.length);
    final hasMore = meta['hasMore'] is bool
        ? meta['hasMore'] as bool
        : metaPage * metaLimit < total;
    return Paged<T>(
      items: List.unmodifiable(items),
      page: metaPage,
      limit: metaLimit,
      total: total,
      hasMore: hasMore,
    );
  }

  Future<dynamic> _send(Future<Response<dynamic>> Function() call) async =>
      (await _request(call))['data'];

  /// Performs the call and returns the success envelope as a map.
  Future<Map<String, dynamic>> _request(
    Future<Response<dynamic>> Function() call,
  ) async {
    final Response<dynamic> response;
    try {
      response = await call();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    } catch (e) {
      throw ApiException.from(e);
    }

    final body = response.data;
    // 204 / empty body: treat as `data: null`.
    if (body == null || (body is String && body.trim().isEmpty)) {
      return const {'success': true, 'data': null};
    }
    if (body is! Map) {
      throw ApiException(
        code: ApiErrorCode.unknown,
        message: 'Unexpected response format',
        statusCode: response.statusCode,
      );
    }
    final map = Map<String, dynamic>.from(body);
    if (map['success'] == false) {
      throw ApiException.fromResponse(response);
    }
    return map;
  }

  /// Drops null values so callers can pass optional filters directly;
  /// DateTimes are sent as UTC ISO strings.
  static Map<String, dynamic>? _clean(Map<String, dynamic>? query) {
    if (query == null) return null;
    final out = <String, dynamic>{};
    query.forEach((k, v) {
      if (v == null) return;
      if (v is String && v.isEmpty) return;
      out[k] = switch (v) {
        final DateTime d => d.toUtc().toIso8601String(),
        final Enum e => wireName(e),
        _ => v,
      };
    });
    return out;
  }

  /// Contract enum value for [e]: `sosOnly` → `sos_only`.
  static String wireName(Enum e) => e.name.replaceAllMapped(
    RegExp('[A-Z]'),
    (m) => '_${m[0]!.toLowerCase()}',
  );

  static int? _asInt(Object? v) => switch (v) {
    final int i => i,
    final num n => n.toInt(),
    final String s => int.tryParse(s),
    _ => null,
  };
}
