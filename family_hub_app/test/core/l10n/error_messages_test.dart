import 'dart:async' show TimeoutException;

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/l10n/error_messages.dart';
import 'package:family_hub/core/network/api_exception.dart';
import 'package:family_hub/l10n/app_localizations.dart';

Duration? _noRetry(int _, Object _) => null;

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  test('maps contract codes to their localized message', () {
    expect(
      localizedErrorMessage(
        const ApiException(code: ApiErrorCode.forbidden, statusCode: 403),
        l10n,
      ),
      l10n.errorForbidden,
    );
    expect(
      localizedErrorMessage(const ApiException.network(), l10n),
      l10n.errorNetwork,
    );
  });

  test('unwraps the ProviderException of a dependent provider', () {
    // Riverpod 3 wraps the error when a provider reads a failed provider
    // synchronously (ref.watch / requireValue).
    final failing = Provider<int>(
      (ref) => throw const ApiException(
        code: ApiErrorCode.notFound,
        statusCode: 404,
      ),
      retry: _noRetry,
    );
    final dependent = Provider<int>(
      (ref) => ref.watch(failing),
      retry: _noRetry,
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);

    Object? error;
    try {
      container.read(dependent);
    } catch (e) {
      error = e;
    }

    expect(error, isA<ProviderException>());
    expect(unwrapProviderError(error!), isA<ApiException>());
    expect(localizedErrorMessage(error, l10n), l10n.errorNotFound);
  });

  test('Dio and timeout errors are classified like ApiException', () {
    final dio = DioException.connectionError(
      requestOptions: RequestOptions(path: '/x'),
      reason: 'offline',
    );
    expect(localizedErrorMessage(dio, l10n), l10n.errorNetwork);
    expect(
      localizedErrorMessage(TimeoutException('slow'), l10n),
      l10n.errorTimeout,
    );
  });

  test('unknown code: server message, then status, then errorUnknown', () {
    expect(
      localizedErrorMessage(
        const ApiException(
          code: 'SOMETHING_NEW',
          message: 'Localized by the server',
          statusCode: 409,
        ),
        l10n,
      ),
      'Localized by the server',
    );
    expect(
      localizedErrorMessage(
        const ApiException(code: 'SOMETHING_NEW', statusCode: 403),
        l10n,
      ),
      l10n.errorForbidden,
    );
    expect(localizedErrorMessage(StateError('bug'), l10n), l10n.errorUnknown);
  });
}
