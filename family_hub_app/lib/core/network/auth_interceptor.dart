import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:family_hub/core/storage/token_storage.dart';
import 'package:family_hub/core/network/api_exception.dart';
import 'package:family_hub/core/network/auth_events.dart';

/// Attaches `Authorization: Bearer <access>` and transparently renews an
/// expired access token.
///
/// On `401 TOKEN_EXPIRED` (or `401 UNAUTHORIZED` for a request that carried
/// a token — e.g. after a server secret rotation) it:
/// 1. performs **one** `POST /auth/refresh` for all concurrent failures
///    (single-flight) using a separate [refreshDio] without this
///    interceptor,
/// 2. stores the rotated tokens and retries the original request **once**,
/// 3. if the server rejects the refresh token: clears the tokens, emits
///    [AuthEvents.emitSessionExpired] and fails with
///    `ApiErrorCode.sessionExpired`.
///
/// A refresh that fails for a transient reason (offline, timeout, 5xx) keeps
/// the tokens and surfaces that error instead, so a flaky network never logs
/// the user out.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this.tokenStorage,
    required this.authEvents,
    required this.refreshDio,
    required Dio Function() retryDio,
  }) : _retryDio = retryDio;

  final TokenStorage tokenStorage;
  final AuthEvents authEvents;

  /// Bare client for `/auth/refresh` (same base URL, no auth interceptor).
  final Dio refreshDio;

  /// Client used to replay the original request (normally the main Dio).
  final Dio Function() _retryDio;

  static const refreshPath = '/auth/refresh';

  /// `RequestOptions.extra` key: set to true to send a request without the
  /// `Authorization` header.
  static const skipAuthKey = 'skipAuth';
  static const _retriedKey = 'authRetried';
  static const _sentTokenKey = 'authSentToken';

  Future<AuthTokens?>? _refreshing;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (options.extra[skipAuthKey] == true || !_isApiHost(options)) {
      // Never leak the token to third-party hosts (absolute URLs).
      options.extra.remove(_sentTokenKey);
      return handler.next(options);
    }
    // Don't start new requests with a token that is being replaced.
    final pending = _refreshing;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {
        // The failing request that triggered the refresh reports the error.
      }
    }
    final tokens = await tokenStorage.read();
    if (tokens != null) {
      options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
      options.extra[_sentTokenKey] = tokens.accessToken;
    } else {
      options.headers.remove('Authorization');
      options.extra.remove(_sentTokenKey);
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    final sentToken = options.extra[_sentTokenKey];
    final code = ApiException.codeOf(err);
    final shouldRefresh =
        err.response?.statusCode == 401 &&
        sentToken is String &&
        options.extra[_retriedKey] != true &&
        options.extra[skipAuthKey] != true &&
        (code == ApiErrorCode.tokenExpired ||
            code == ApiErrorCode.unauthorized);
    if (!shouldRefresh) return handler.next(err);

    AuthTokens? tokens;
    try {
      tokens = await _freshTokens(sentToken);
    } on ApiException catch (e) {
      // Transient refresh failure: keep the session, report this error.
      return handler.next(
        DioException(
          requestOptions: options,
          response: err.response,
          type: err.type,
          error: e,
          message: e.message,
        ),
      );
    }

    if (tokens == null) {
      return handler.next(
        DioException(
          requestOptions: options,
          response: err.response,
          type: DioExceptionType.badResponse,
          error: const ApiException.sessionExpired(),
          message: 'Session expired',
        ),
      );
    }

    try {
      final retryOptions = options.copyWith(
        extra: {...options.extra, _retriedKey: true},
        headers: {
          ...options.headers,
          'Authorization': 'Bearer ${tokens.accessToken}',
        },
      );
      final response = await _retryDio().fetch<dynamic>(retryOptions);
      handler.resolve(response);
    } on DioException catch (e) {
      // The retry already ran through every interceptor; finish with it.
      handler.reject(e);
    }
  }

  static bool _isApiHost(RequestOptions o) {
    final base = Uri.tryParse(o.baseUrl);
    if (base == null || base.host.isEmpty) return true;
    final target = o.uri;
    return target.host == base.host && target.scheme == base.scheme;
  }

  /// Tokens to retry with. If another request already rotated the token
  /// since [sentToken] was sent, reuse it; otherwise refresh (single-flight).
  /// Returns null when the session is gone; throws [ApiException] for
  /// transient failures.
  Future<AuthTokens?> _freshTokens(String sentToken) async {
    final current = await tokenStorage.read();
    if (current == null) return null;
    if (current.accessToken != sentToken) return current;
    final inFlight = _refreshing;
    if (inFlight != null) return inFlight;
    final future = _refresh(current.refreshToken);
    _refreshing = future;
    try {
      return await future;
    } finally {
      if (identical(_refreshing, future)) _refreshing = null;
    }
  }

  Future<AuthTokens?> _refresh(String refreshToken) async {
    try {
      final res = await refreshDio.post<dynamic>(
        refreshPath,
        data: {'refreshToken': refreshToken},
      );
      final body = res.data;
      final data = body is Map ? body['data'] : null;
      final tokens = AuthTokens.tryParse(data is Map ? data['tokens'] : null);
      if (tokens == null) {
        throw const ApiException.unknown('Malformed /auth/refresh response');
      }
      await tokenStorage.save(tokens);
      return tokens;
    } on DioException catch (e) {
      final api = ApiException.fromDio(e);
      final status = e.response?.statusCode;
      final rejected =
          status != null &&
          status >= 400 &&
          status < 500 &&
          status != 408 &&
          status != 429;
      if (!rejected) throw api; // offline / timeout / 5xx / rate limited
      await _expireSession();
      return null;
    } on ApiException {
      rethrow;
    } catch (e) {
      debugPrint('AuthInterceptor: refresh failed ($e)');
      throw ApiException.unknown('$e');
    }
  }

  Future<void> _expireSession() async {
    await tokenStorage.clear();
    authEvents.emitSessionExpired();
  }
}
