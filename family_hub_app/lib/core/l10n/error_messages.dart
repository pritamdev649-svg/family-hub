import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;

import 'package:family_hub/core/network/api_exception.dart';
import 'package:family_hub/l10n/app_localizations.dart';

/// User-facing, localized message for anything a repository / service can
/// throw. Known error codes map to `error*` strings; unknown codes fall back
/// to the server message (already localized via `Accept-Language`), then to
/// a status-based message, then to `errorUnknown`.
///
/// Riverpod's `ProviderException` wrappers (errors of dependent providers)
/// are unwrapped first, so the original code is mapped.
///
/// Widgets normally go through `ErrorView` / `context.showError(e)` which
/// call this.
String localizedErrorMessage(Object error, AppLocalizations l10n) {
  final ApiException e = switch (unwrapProviderError(error)) {
    final ApiException api => api,
    final DioException dio => ApiException.fromDio(dio),
    TimeoutException() => const ApiException.timeout(),
    _ => const ApiException.unknown(),
  };

  final byCode = _byCode(e, l10n);
  if (byCode != null) return byCode;

  if (e.message.trim().isNotEmpty && e.statusCode != null) {
    return e.message.trim();
  }
  return _byStatus(e.statusCode, l10n) ?? l10n.errorUnknown;
}

/// Riverpod 3 wraps errors of dependent providers in [ProviderException]
/// (possibly several levels deep); returns the original error.
Object unwrapProviderError(Object error) {
  var current = error;
  while (current is ProviderException) {
    current = current.exception;
  }
  return current;
}

String? _byCode(ApiException e, AppLocalizations l10n) => switch (e.code) {
  ApiErrorCode.network => l10n.errorNetwork,
  ApiErrorCode.timeout => l10n.errorTimeout,
  ApiErrorCode.unknown => l10n.errorUnknown,
  ApiErrorCode.cancelled => l10n.errorUnknown,
  ApiErrorCode.internal || ApiErrorCode.serviceUnavailable => l10n.errorServer,
  ApiErrorCode.payloadTooLarge => l10n.errorBadRequest,
  ApiErrorCode.badRequest => l10n.errorBadRequest,
  ApiErrorCode.unauthorized => l10n.errorUnauthorized,
  ApiErrorCode.tokenExpired ||
  ApiErrorCode.invalidRefreshToken ||
  ApiErrorCode.sessionExpired => l10n.errorSessionExpired,
  ApiErrorCode.forbidden => l10n.errorForbidden,
  ApiErrorCode.notFound => l10n.errorNotFound,
  ApiErrorCode.validation => l10n.errorValidation,
  ApiErrorCode.invalidCredentials => l10n.errorInvalidCredentials,
  ApiErrorCode.emailTaken => l10n.errorEmailTaken,
  ApiErrorCode.invalidOtp => l10n.errorInvalidOtp,
  ApiErrorCode.otpExpired => l10n.errorOtpExpired,
  ApiErrorCode.invalidInviteCode => l10n.errorInvalidInviteCode,
  ApiErrorCode.alreadyInFamily => l10n.errorAlreadyInFamily,
  ApiErrorCode.noFamily => l10n.errorNoFamily,
  ApiErrorCode.memberEmailExists => l10n.errorMemberEmailExists,
  ApiErrorCode.lastAdmin => l10n.errorLastAdmin,
  ApiErrorCode.sosNotActive => l10n.errorSosNotActive,
  ApiErrorCode.guardianConsentRequired => l10n.errorGuardianConsentRequired,
  ApiErrorCode.tooManyRequests => l10n.errorTooManyRequests(
    e.retryAfterSeconds ?? 0,
  ),
  ApiErrorCode.locationSharingDisabled => l10n.errorLocationSharingDisabled,
  // Client-side upload errors (`UploadErrorCode` in
  // core/services/cloudinary_service.dart).
  'UPLOAD_FAILED' => l10n.servicesErrorUploadFailed,
  'FILE_TOO_LARGE' => l10n.servicesErrorFileTooLarge,
  'UPLOAD_CANCELLED' => l10n.servicesErrorUploadCancelled,
  _ => null,
};

String? _byStatus(int? status, AppLocalizations l10n) => switch (status) {
  null => null,
  400 => l10n.errorBadRequest,
  401 => l10n.errorUnauthorized,
  403 => l10n.errorForbidden,
  404 => l10n.errorNotFound,
  422 => l10n.errorValidation,
  429 => l10n.errorTooManyRequests(0),
  >= 500 => l10n.errorServer,
  _ => null,
};
