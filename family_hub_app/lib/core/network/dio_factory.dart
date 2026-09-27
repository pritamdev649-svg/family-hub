import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:family_hub/core/config/app_config.dart';
import 'package:family_hub/core/storage/token_storage.dart';
import 'package:family_hub/core/network/api_exception.dart';
import 'package:family_hub/core/network/auth_events.dart';
import 'package:family_hub/core/network/auth_interceptor.dart';
import 'package:family_hub/core/network/locale_interceptor.dart';
import 'package:family_hub/core/network/mock/mock_backend.dart';
import 'package:family_hub/core/network/mock/mock_interceptor.dart';

/// Builds the app's [Dio] client.
///
/// Interceptor order (request →): reachability, locale, auth, debug log,
/// mock (mock mode only, must be last). Token refresh uses a separate bare
/// client (locale + mock only) so it can never recurse into itself.
///
/// * [mockBackend] non-null → requests are answered in memory
///   (`AppConfig.useMockApi`), with [mockMinLatency]..[mockMaxLatency]
///   simulated latency.
/// * [onReachability] receives `false` when a request failed without any
///   response (offline/timeout) and `true` whenever the server answered.
Dio createDio({
  required TokenStorage tokenStorage,
  required AuthEvents authEvents,
  required String Function() languageCode,
  MockBackend? mockBackend,
  void Function(bool reachable)? onReachability,
  String? baseUrl,
  Duration mockMinLatency = const Duration(milliseconds: 250),
  Duration mockMaxLatency = const Duration(milliseconds: 600),
}) {
  final options = BaseOptions(
    baseUrl:
        baseUrl ??
        (mockBackend != null ? MockBackend.baseUrl : AppConfig.apiBaseUrl),
    connectTimeout: AppConfig.connectTimeout,
    receiveTimeout: AppConfig.receiveTimeout,
    contentType: Headers.jsonContentType,
    responseType: ResponseType.json,
    headers: {Headers.acceptHeader: Headers.jsonContentType},
  );

  MockInterceptor? mock() => mockBackend == null
      ? null
      : MockInterceptor(
          mockBackend,
          minLatency: mockMinLatency,
          maxLatency: mockMaxLatency,
        );

  final locale = LocaleInterceptor(languageCode);

  final refreshDio = Dio(options.copyWith());
  refreshDio.interceptors.addAll([locale, ?mock()]);

  final dio = Dio(options);
  dio.interceptors.addAll([
    if (onReachability != null) ReachabilityInterceptor(onReachability),
    locale,
    AuthInterceptor(
      tokenStorage: tokenStorage,
      authEvents: authEvents,
      refreshDio: refreshDio,
      retryDio: () => dio,
    ),
    if (kDebugMode) DebugLogInterceptor(),
    ?mock(),
  ]);
  return dio;
}

/// Reports whether the API is reachable (drives the offline banner).
class ReachabilityInterceptor extends Interceptor {
  ReachabilityInterceptor(this._report);

  final void Function(bool reachable) _report;

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    _safeReport(true);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final e = ApiException.fromDio(err);
    if (e.isNetwork) {
      _safeReport(false);
    } else if (err.response != null) {
      _safeReport(true);
    }
    handler.next(err);
  }

  void _safeReport(bool reachable) {
    try {
      _report(reachable);
    } catch (e) {
      debugPrint('ReachabilityInterceptor: listener failed ($e)');
    }
  }
}

/// Debug-only one-line request log. Never logs bodies or headers (they
/// contain tokens, passwords and personal data).
class DebugLogInterceptor extends Interceptor {
  static const _startKey = 'debugLogStart';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_startKey] = DateTime.now().millisecondsSinceEpoch;
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    _log(response.requestOptions, '${response.statusCode}');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final code = ApiException.codeOf(err) ?? err.type.name;
    _log(err.requestOptions, '${err.response?.statusCode ?? '-'} $code');
    handler.next(err);
  }

  void _log(RequestOptions o, String result) {
    final start = o.extra[_startKey];
    final ms = start is int ? DateTime.now().millisecondsSinceEpoch - start : 0;
    debugPrint('[api] ${o.method} ${o.path} → $result (${ms}ms)');
  }
}
