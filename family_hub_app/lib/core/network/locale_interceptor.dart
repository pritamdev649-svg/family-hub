import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Adds `Accept-Language: <languageCode>` (e.g. `hi`, `ar`) so the backend
/// localizes error messages. The code is read per request, so a language
/// change in Settings applies immediately without rebuilding Dio.
class LocaleInterceptor extends Interceptor {
  LocaleInterceptor(this._languageCode);

  final String Function() _languageCode;

  static const header = 'Accept-Language';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // Respect an explicit per-request override.
    if (!options.headers.containsKey(header)) {
      options.headers[header] = _resolve();
    }
    handler.next(options);
  }

  String _resolve() {
    try {
      final code = _languageCode().trim();
      if (code.isNotEmpty) return code;
    } catch (e) {
      debugPrint('LocaleInterceptor: locale unavailable ($e)');
    }
    return PlatformDispatcher.instance.locale.languageCode;
  }
}
