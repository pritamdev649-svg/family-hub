import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:family_hub/core/network/mock/mock_backend.dart';

/// Answers API requests from the in-memory [MockBackend] instead of the
/// network: wraps results in the contract envelope, simulates latency and
/// turns [MockException]s into the error envelope with the right status.
///
/// Must be the **last** interceptor so `Authorization` / `Accept-Language`
/// are already set. Errors are rejected with `callFollowingErrorInterceptor`
/// so `AuthInterceptor.onError` sees them exactly like real HTTP errors.
class MockInterceptor extends Interceptor {
  MockInterceptor(
    this.backend, {
    this.minLatency = const Duration(milliseconds: 250),
    this.maxLatency = const Duration(milliseconds: 600),
    Random? random,
  }) : _random = random ?? Random();

  final MockBackend backend;
  final Duration minLatency;
  final Duration maxLatency;
  final Random _random;

  /// Only requests to the mock host are answered; anything else (e.g. an
  /// absolute third-party URL) continues untouched.
  bool _handles(RequestOptions o) => o.uri.host == _mockHost;

  static final _mockHost = Uri.parse(MockBackend.baseUrl).host;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (!_handles(options)) return handler.next(options);

    await _delay();
    if (options.cancelToken?.isCancelled ?? false) {
      return handler.reject(
        DioException.requestCancelled(
          requestOptions: options,
          reason: options.cancelToken?.cancelError,
        ),
        true,
      );
    }

    int status;
    Map<String, dynamic> envelope;
    try {
      final res = await backend.handle(options);
      status = res.status;
      envelope = {
        'success': true,
        'data': res.data,
        if (res.meta != null) 'meta': res.meta,
      };
    } on MockException catch (e) {
      status = e.status;
      envelope = e.toEnvelope();
    } catch (e, st) {
      debugPrint(
        'MockBackend: ${options.method} ${options.path} crashed: $e\n$st',
      );
      status = 500;
      envelope = const MockException(
        500,
        'INTERNAL_ERROR',
        'Something went wrong',
      ).toEnvelope();
    }

    // JSON round-trip: the app receives exactly what it would get over the
    // wire (and handler bugs like returning a DateTime surface here).
    Object? body;
    try {
      body = jsonDecode(jsonEncode(envelope));
    } catch (e) {
      debugPrint('MockBackend: ${options.path} returned non-JSON data: $e');
      status = 500;
      body = const MockException(
        500,
        'INTERNAL_ERROR',
        'Something went wrong',
      ).toEnvelope();
    }

    final response = Response<dynamic>(
      requestOptions: options,
      statusCode: status,
      statusMessage: status < 400 ? 'OK' : 'Error',
      data: body,
      headers: Headers.fromMap({
        Headers.contentTypeHeader: ['application/json; charset=utf-8'],
      }),
    );

    if (status >= 200 && status < 300) {
      handler.resolve(response, true);
    } else {
      handler.reject(
        DioException.badResponse(
          statusCode: status,
          requestOptions: options,
          response: response,
        ),
        true,
      );
    }
  }

  Future<void> _delay() {
    final minMs = minLatency.inMilliseconds;
    final maxMs = max(minMs, maxLatency.inMilliseconds);
    if (maxMs <= 0) return Future.value();
    final ms = minMs + _random.nextInt(maxMs - minMs + 1);
    return Future.delayed(Duration(milliseconds: ms));
  }
}
