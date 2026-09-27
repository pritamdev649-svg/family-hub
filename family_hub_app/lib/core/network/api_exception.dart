import 'dart:async';

import 'package:dio/dio.dart';

/// Every error code the client can see: the contract codes
/// (`docs/03-API_CONTRACT.md` §1) plus client-side codes.
abstract final class ApiErrorCode {
  // ── Client-side ──────────────────────────────────────────────────────────
  /// No connection / DNS failure / TLS failure.
  static const network = 'NETWORK_ERROR';

  /// Connect / send / receive timeout.
  static const timeout = 'TIMEOUT';

  /// Anything we could not classify (malformed response, bug…).
  static const unknown = 'UNKNOWN';

  /// The request was cancelled by the app (never shown to users).
  static const cancelled = 'CANCELLED';

  /// Token refresh failed; tokens were cleared and the user must sign in.
  static const sessionExpired = 'SESSION_EXPIRED';

  // ── Contract codes ───────────────────────────────────────────────────────
  static const badRequest = 'BAD_REQUEST';
  static const invalidOtp = 'INVALID_OTP';
  static const otpExpired = 'OTP_EXPIRED';
  static const invalidInviteCode = 'INVALID_INVITE_CODE';
  static const unauthorized = 'UNAUTHORIZED';
  static const tokenExpired = 'TOKEN_EXPIRED';
  static const invalidCredentials = 'INVALID_CREDENTIALS';
  static const invalidRefreshToken = 'INVALID_REFRESH_TOKEN';
  static const forbidden = 'FORBIDDEN';
  static const noFamily = 'NO_FAMILY';
  static const locationSharingDisabled = 'LOCATION_SHARING_DISABLED';
  static const notFound = 'NOT_FOUND';
  static const emailTaken = 'EMAIL_TAKEN';
  static const alreadyInFamily = 'ALREADY_IN_FAMILY';
  static const memberEmailExists = 'MEMBER_EMAIL_EXISTS';
  static const lastAdmin = 'LAST_ADMIN';
  static const sosNotActive = 'SOS_NOT_ACTIVE';
  static const conflict = 'CONFLICT';
  static const validation = 'VALIDATION_ERROR';
  static const guardianConsentRequired = 'GUARDIAN_CONSENT_REQUIRED';
  static const tooManyRequests = 'TOO_MANY_REQUESTS';
  static const internal = 'INTERNAL_ERROR';

  // Extra server codes (backend `ApiError`): body over 100 kB, dependency
  // (DB / mail / push) temporarily down.
  static const payloadTooLarge = 'PAYLOAD_TOO_LARGE';
  static const serviceUnavailable = 'SERVICE_UNAVAILABLE';

  /// Codes that mean "the stored session is no longer valid".
  static const sessionCodes = {
    unauthorized,
    tokenExpired,
    invalidRefreshToken,
    sessionExpired,
  };

  /// Best-effort code for an HTTP status when the body has no envelope.
  static String fromStatus(int? status) => switch (status) {
    400 => badRequest,
    401 => unauthorized,
    403 => forbidden,
    404 => notFound,
    409 => conflict,
    413 => payloadTooLarge,
    422 => validation,
    429 => tooManyRequests,
    503 => serviceUnavailable,
    final s? when s >= 500 => internal,
    _ => unknown,
  };
}

/// The only exception type repositories throw. UI code turns it into text
/// with `localizedErrorMessage` / `context.showError`.
class ApiException implements Exception {
  const ApiException({
    required this.code,
    this.message = '',
    this.statusCode,
    this.details,
  });

  /// Contract error code (see [ApiErrorCode]).
  final String code;

  /// Server message (already localized via `Accept-Language`) or a
  /// developer-facing description for client-side errors. May be empty.
  final String message;

  final int? statusCode;

  /// `VALIDATION_ERROR` → field path → message; `TOO_MANY_REQUESTS` →
  /// `{retryAfterSeconds}`; otherwise usually null.
  final Map<String, dynamic>? details;

  const ApiException.network([String message = ''])
    : this(code: ApiErrorCode.network, message: message);

  const ApiException.timeout([String message = ''])
    : this(code: ApiErrorCode.timeout, message: message);

  const ApiException.unknown([String message = ''])
    : this(code: ApiErrorCode.unknown, message: message);

  const ApiException.sessionExpired()
    : this(code: ApiErrorCode.sessionExpired, statusCode: 401);

  /// No response reached us (offline or timed out).
  bool get isNetwork =>
      code == ApiErrorCode.network || code == ApiErrorCode.timeout;

  /// The session is invalid (the app should sign out / re-authenticate).
  /// `INVALID_CREDENTIALS` is *not* included: that is a wrong password.
  bool get isUnauthorized => ApiErrorCode.sessionCodes.contains(code);

  bool get isForbidden => code == ApiErrorCode.forbidden;
  bool get isNotFound => code == ApiErrorCode.notFound;
  bool get isValidation => code == ApiErrorCode.validation;
  bool get isCancelled => code == ApiErrorCode.cancelled;
  bool get isServer =>
      code == ApiErrorCode.internal ||
      code == ApiErrorCode.serviceUnavailable ||
      (statusCode != null && statusCode! >= 500);

  /// `details.retryAfterSeconds` for `TOO_MANY_REQUESTS` (null if absent).
  int? get retryAfterSeconds {
    final v = details?['retryAfterSeconds'];
    if (v is num) return v.ceil();
    if (v is String) return int.tryParse(v);
    return null;
  }

  /// `VALIDATION_ERROR` details as `field → message` (non-string values are
  /// skipped). Empty for other errors.
  Map<String, String> get fieldErrors {
    final d = details;
    if (d == null || !isValidation) return const {};
    return {
      for (final e in d.entries)
        if (e.value is String) e.key: e.value as String,
    };
  }

  /// Converts anything thrown while talking to the API into an
  /// [ApiException] (never throws).
  static ApiException from(Object error) {
    if (error is ApiException) return error;
    if (error is DioException) return fromDio(error);
    if (error is TimeoutException) return ApiException.timeout('$error');
    return ApiException.unknown('$error');
  }

  /// Maps a [DioException] (including one produced by the mock backend).
  static ApiException fromDio(DioException e) {
    final inner = e.error;
    if (inner is ApiException) return inner;

    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return ApiException.timeout(e.message ?? '');
      case DioExceptionType.connectionError:
      case DioExceptionType.badCertificate:
        return ApiException.network(e.message ?? '');
      case DioExceptionType.cancel:
        return const ApiException(code: ApiErrorCode.cancelled);
      case DioExceptionType.badResponse:
        return fromResponse(e.response);
      case DioExceptionType.unknown:
        if (e.response != null) return fromResponse(e.response);
        // dart:io SocketException / HttpException / HandshakeException end up
        // here; checked by name to stay web-compatible (no dart:io import).
        final name = inner?.runtimeType.toString() ?? '';
        if (name.contains('Socket') ||
            name.contains('HttpException') ||
            name.contains('Handshake') ||
            name.contains('ClientException')) {
          return ApiException.network('$inner');
        }
        return ApiException.unknown(e.message ?? '$inner');
    }
  }

  /// Parses the error envelope
  /// `{ success:false, error:{ code, message, details } }`.
  static ApiException fromResponse(Response<dynamic>? response) {
    final status = response?.statusCode;
    final body = response?.data;
    if (body is Map && body['error'] is Map) {
      final err = body['error'] as Map;
      final code = err['code'];
      final message = err['message'];
      final details = err['details'];
      return ApiException(
        code: code is String && code.isNotEmpty
            ? code
            : ApiErrorCode.fromStatus(status),
        message: message is String ? message : '',
        statusCode: status,
        details: details is Map ? Map<String, dynamic>.from(details) : null,
      );
    }
    return ApiException(
      code: ApiErrorCode.fromStatus(status),
      message: response?.statusMessage ?? '',
      statusCode: status,
    );
  }

  /// Error code carried by a Dio error response (without full parsing).
  static String? codeOf(DioException e) {
    final body = e.response?.data;
    if (body is Map && body['error'] is Map) {
      final code = (body['error'] as Map)['code'];
      if (code is String) return code;
    }
    return null;
  }

  @override
  String toString() {
    final status = statusCode == null ? '' : ' ($statusCode)';
    final msg = message.isEmpty ? '' : ': $message';
    return 'ApiException[$code]$status$msg';
  }
}
