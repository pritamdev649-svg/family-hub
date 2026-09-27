import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:family_hub/core/providers/core_providers.dart';
import 'package:family_hub/core/services/push_notification_service.dart';
import 'package:family_hub/shared/data/me_repository.dart' show DevicePlatform;

/// One recorded API call.
class ApiCall {
  ApiCall(this.method, this.path, this.body, this.query);

  final String method;
  final String path;
  final Object? body;
  final Map<String, dynamic>? query;

  Map<String, dynamic> get json => (body as Map).cast<String, dynamic>();

  @override
  String toString() => '$method $path';
}

typedef ApiHandler = FutureOr<Object?> Function(ApiCall call);

/// [ApiClient] whose responses come from [handlers] keyed by
/// `'<METHOD> <path>'`. Unhandled calls throw `NOT_FOUND`. A handler may
/// throw an [ApiException] to simulate an error envelope.
class FakeApiClient extends ApiClient {
  FakeApiClient([Map<String, ApiHandler>? handlers])
    : handlers = handlers ?? {},
      super(Dio());

  final Map<String, ApiHandler> handlers;
  final List<ApiCall> calls = [];

  /// Log shared with other fakes to assert ordering across collaborators.
  List<String>? eventLog;

  void on(String route, ApiHandler handler) => handlers[route] = handler;

  List<ApiCall> callsTo(String route) =>
      calls.where((c) => '${c.method} ${c.path}' == route).toList();

  Future<dynamic> _handle(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) async {
    final call = ApiCall(method, path, body, query);
    calls.add(call);
    eventLog?.add('api $method $path');
    await Future<void>.delayed(Duration.zero);
    final handler = handlers['$method $path'];
    if (handler == null) {
      throw ApiException(
        code: ApiErrorCode.notFound,
        message: 'No fake for $method $path',
        statusCode: 404,
      );
    }
    return handler(call);
  }

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _handle('GET', path, query: query);

  @override
  Future<dynamic> post(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) => _handle('POST', path, body: body, query: query);

  @override
  Future<dynamic> patch(String path, {Object? body}) =>
      _handle('PATCH', path, body: body);

  @override
  Future<dynamic> put(String path, {Object? body}) =>
      _handle('PUT', path, body: body);

  @override
  Future<dynamic> delete(String path, {Object? body}) =>
      _handle('DELETE', path, body: body);
}

/// In-memory [TokenStorage].
class FakeTokenStorage extends TokenStorage {
  FakeTokenStorage([this.tokens]);

  AuthTokens? tokens;
  List<String>? eventLog;
  int clears = 0;

  @override
  AuthTokens? get cached => tokens;

  @override
  Future<AuthTokens?> read() async => tokens;

  @override
  Future<void> save(AuthTokens tokens) async {
    this.tokens = tokens;
    eventLog?.add('tokens saved');
  }

  @override
  Future<void> clear() async {
    tokens = null;
    clears++;
    eventLog?.add('tokens cleared');
  }
}

class _NoopDeviceApi implements PushDeviceApi {
  @override
  Future<void> register({
    required String token,
    required DevicePlatform platform,
    String? locale,
  }) async {}

  @override
  Future<void> unregister(String token) async {}
}

/// Records push (un)registrations instead of talking to Firebase.
class FakePushService extends PushNotificationService {
  FakePushService() : super(deviceApi: _NoopDeviceApi());

  int registrations = 0;
  int unregistrations = 0;
  List<String>? eventLog;

  @override
  Future<void> registerDevice({String? locale}) async {
    registrations++;
    eventLog?.add('push register');
  }

  @override
  Future<void> unregisterDevice() async {
    unregistrations++;
    eventLog?.add('push unregister');
  }
}

/// Everything a session test needs, wired into one [ProviderContainer].
class SessionHarness {
  SessionHarness._(
    this.container,
    this.api,
    this.tokens,
    this.push,
    this.prefs,
    this.events,
  );

  static Future<SessionHarness> create({
    AuthTokens? tokens,
    Map<String, Object> prefs = const {},
    Map<String, ApiHandler>? handlers,
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    final sp = await SharedPreferences.getInstance();
    final api = FakeApiClient(handlers);
    final tokenStorage = FakeTokenStorage(tokens);
    final push = FakePushService();
    final events = AuthEvents();
    final log = <String>[];
    api.eventLog = log;
    tokenStorage.eventLog = log;
    push.eventLog = log;
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sp),
        apiClientProvider.overrideWithValue(api),
        tokenStorageProvider.overrideWithValue(tokenStorage),
        authEventsProvider.overrideWithValue(events),
        pushNotificationServiceProvider.overrideWithValue(push),
      ],
    );
    final h = SessionHarness._(container, api, tokenStorage, push, sp, events);
    h.log = log;
    return h;
  }

  final ProviderContainer container;
  final FakeApiClient api;
  final FakeTokenStorage tokens;
  final FakePushService push;
  final SharedPreferences prefs;
  final AuthEvents events;
  late final List<String> log;

  LocalCache get cache => LocalCache(prefs);

  void dispose() {
    container.dispose();
    events.dispose();
  }
}

/// Lets fire-and-forget futures (push registration, listeners) run.
Future<void> settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
