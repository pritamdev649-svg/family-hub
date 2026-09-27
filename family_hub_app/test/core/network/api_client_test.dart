import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/network/api_client.dart';
import 'package:family_hub/core/network/auth_events.dart';
import 'package:family_hub/core/network/dio_factory.dart';
import 'package:family_hub/core/network/mock/mock_backend.dart';
import 'package:family_hub/core/storage/token_storage.dart';

/// Full client stack (ApiClient → Dio → locale/auth interceptors → mock
/// backend) with zero latency.
class _Harness {
  _Harness() {
    FlutterSecureStorage.setMockInitialValues({});
    tokens = TokenStorage();
    events = AuthEvents();
    backend = MockBackend(MockDb(seedCore: false));
    dio = createDio(
      tokenStorage: tokens,
      authEvents: events,
      languageCode: () => 'hi',
      mockBackend: backend,
      onReachability: reachability.add,
      mockMinLatency: Duration.zero,
      mockMaxLatency: Duration.zero,
    );
    api = ApiClient(dio);
  }

  late final TokenStorage tokens;
  late final AuthEvents events;
  late final MockBackend backend;
  late final Dio dio;
  late final ApiClient api;
  final reachability = <bool>[];
  int refreshCalls = 0;

  /// `/auth/refresh` that rotates `r<n>` → access `a<n+1>`.
  void registerRefresh({MockException? fail}) {
    backend.on('POST', '/auth/refresh', (req) async {
      refreshCalls++;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      if (fail != null) throw fail;
      final n = refreshCalls;
      return MockResponse.ok({
        'tokens': {
          'accessToken': 'a$n',
          'refreshToken': 'r$n',
          'expiresIn': 900,
        },
      });
    });
  }
}

Future<ApiException> _apiError(Future<Object?> f) async {
  try {
    await f;
  } on ApiException catch (e) {
    return e;
  }
  fail('expected an ApiException');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ApiClient envelope', () {
    late _Harness h;
    setUp(() => h = _Harness());

    test('returns unwrapped data for every verb', () async {
      for (final m in ['GET', 'POST', 'PATCH', 'PUT', 'DELETE']) {
        h.backend.on(m, '/things', (r) => MockResponse.ok({'m': r.method}));
      }
      expect(await h.api.get('/things'), {'m': 'GET'});
      expect(await h.api.post('/things', body: {'x': 1}), {'m': 'POST'});
      expect(await h.api.patch('/things'), {'m': 'PATCH'});
      expect(await h.api.put('/things'), {'m': 'PUT'});
      expect(await h.api.delete('/things'), {'m': 'DELETE'});
      expect(h.reachability, everyElement(isTrue));
    });

    test('null data and 201 created', () async {
      h.backend.on('DELETE', '/x/:id', (r) => const MockResponse.ok());
      h.backend.on('POST', '/x', (r) => MockResponse.created(r.body));
      expect(await h.api.delete('/x/1'), isNull);
      expect(await h.api.post('/x', body: {'a': 'b'}), {'a': 'b'});
    });

    test('sends Accept-Language and drops null query values', () async {
      h.backend.on(
        'GET',
        '/echo',
        (r) => MockResponse.ok({
          'lang': r.headers['accept-language'],
          'query': r.query,
        }),
      );
      final res = await h.api.get(
        '/echo',
        query: {'status': 'pending', 'assigneeId': null, 'empty': ''},
      );
      expect(res, {
        'lang': 'hi',
        'query': {'status': 'pending'},
      });
    });

    test('error envelope → ApiException with code, status, details', () async {
      h.backend.on(
        'POST',
        '/tasks',
        (r) => throw const MockException.validation({'title': 'Required'}),
      );
      final e = await _apiError(h.api.post('/tasks', body: {}));
      expect(e.code, ApiErrorCode.validation);
      expect(e.statusCode, 422);
      expect(e.isValidation, isTrue);
      expect(e.fieldErrors, {'title': 'Required'});
    });

    test('unknown route → NOT_FOUND; handler crash → INTERNAL_ERROR', () async {
      expect(
        (await _apiError(h.api.get('/missing'))).code,
        ApiErrorCode.notFound,
      );
      h.backend.on('GET', '/boom', (r) => throw StateError('bug'));
      final e = await _apiError(h.api.get('/boom'));
      expect(e.code, ApiErrorCode.internal);
      expect(e.isServer, isTrue);
    });

    test('429 exposes retryAfterSeconds', () async {
      h.backend.on(
        'POST',
        '/auth/login',
        (r) => throw MockException.tooManyRequests(42),
      );
      final e = await _apiError(h.api.post('/auth/login'));
      expect(e.code, ApiErrorCode.tooManyRequests);
      expect(e.retryAfterSeconds, 42);
    });

    test('getPaged parses items + meta and sends page/limit', () async {
      final all = List.generate(45, (i) => {'id': '$i'});
      h.backend.on('GET', '/items', (r) => MockResponse.paged(all, r));
      final page2 = await h.api.getPaged(
        '/items',
        (j) => j['id'] as String,
        page: 2,
      );
      expect(page2.items.first, '20');
      expect(page2.items.length, 20);
      expect(page2.page, 2);
      expect(page2.total, 45);
      expect(page2.hasMore, isTrue);

      final page3 = await h.api.getPaged(
        '/items',
        (j) => j['id'] as String,
        page: 3,
      );
      final merged = page2.append(page3);
      expect(merged.items.length, 25);
      expect(merged.hasMore, isFalse);
      expect(merged.page, 3);
    });

    test('Paged helpers', () {
      const p = Paged<int>(
        items: [1, 2, 3],
        page: 1,
        limit: 3,
        total: 5,
        hasMore: true,
      );
      const next = Paged<int>(
        items: [3, 4],
        page: 2,
        limit: 3,
        total: 5,
        hasMore: false,
      );
      expect(p.append(next, identity: (i) => i).items, [1, 2, 3, 4]);
      expect(p.copyWith(items: [1, 3]).total, 4);
      expect(p.map((i) => '$i').items, ['1', '2', '3']);
      expect(const Paged<int>.empty().nextPage, 1);
    });
  });

  group('AuthInterceptor', () {
    late _Harness h;
    setUp(() => h = _Harness());

    void registerSecure() {
      // Mirrors the server: only the latest issued access token is valid.
      h.backend.on('GET', '/secure', (r) {
        final token = r.accessToken;
        if (token == null) throw const MockException.unauthorized();
        if (token == 'old') {
          throw const MockException.unauthorized('TOKEN_EXPIRED', 'expired');
        }
        return MockResponse.ok(token);
      });
    }

    test(
      'attaches the bearer token; no token → 401 UNAUTHORIZED, no refresh',
      () async {
        registerSecure();
        h.registerRefresh();
        final e = await _apiError(h.api.get('/secure'));
        expect(e.code, ApiErrorCode.unauthorized);
        expect(e.isUnauthorized, isTrue);
        expect(h.refreshCalls, 0);

        await h.tokens.save(
          const AuthTokens(accessToken: 'good', refreshToken: 'r0'),
        );
        expect(await h.api.get('/secure'), 'good');
      },
    );

    test(
      'TOKEN_EXPIRED → one refresh for concurrent requests, then retry',
      () async {
        registerSecure();
        h.registerRefresh();
        await h.tokens.save(
          const AuthTokens(accessToken: 'old', refreshToken: 'r0'),
        );

        final results = await Future.wait([
          h.api.get('/secure'),
          h.api.get('/secure'),
          h.api.get('/secure'),
        ]);
        expect(results, ['a1', 'a1', 'a1']);
        expect(h.refreshCalls, 1, reason: 'single-flight refresh');
        final stored = await h.tokens.read();
        expect(stored?.accessToken, 'a1');
        expect(stored?.refreshToken, 'r1');

        // Survives an app restart (read back from secure storage).
        final reloaded = TokenStorage();
        expect((await reloaded.read())?.refreshToken, 'r1');
      },
    );

    test('retries only once', () async {
      h.backend.on(
        'GET',
        '/always-expired',
        (r) => throw const MockException.unauthorized('TOKEN_EXPIRED'),
      );
      h.registerRefresh();
      await h.tokens.save(
        const AuthTokens(accessToken: 'old', refreshToken: 'r0'),
      );
      final e = await _apiError(h.api.get('/always-expired'));
      expect(e.code, ApiErrorCode.tokenExpired);
      expect(h.refreshCalls, 1);
    });

    test(
      'rejected refresh → tokens cleared, sessionExpired emitted once',
      () async {
        registerSecure();
        h.registerRefresh(
          fail: const MockException.unauthorized('INVALID_REFRESH_TOKEN'),
        );
        await h.tokens.save(
          const AuthTokens(accessToken: 'old', refreshToken: 'r0'),
        );
        var expired = 0;
        final sub = h.events.sessionExpired.listen((_) => expired++);

        final errors = await Future.wait([
          _apiError(h.api.get('/secure')),
          _apiError(h.api.get('/secure')),
        ]);
        await pumpEventQueue();
        // A request queued behind the failed refresh goes out without a token
        // and gets UNAUTHORIZED; either way every caller sees a dead session.
        expect(errors.every((e) => e.isUnauthorized), isTrue);
        expect(
          errors.map((e) => e.code),
          contains(ApiErrorCode.sessionExpired),
        );
        expect(expired, 1);
        expect(await h.tokens.read(), isNull);
        expect(h.refreshCalls, 1);
        await sub.cancel();
      },
    );

    test('transient refresh failure keeps the session', () async {
      registerSecure();
      h.registerRefresh(
        fail: const MockException(503, 'INTERNAL_ERROR', 'down'),
      );
      await h.tokens.save(
        const AuthTokens(accessToken: 'old', refreshToken: 'r0'),
      );
      var expired = 0;
      final sub = h.events.sessionExpired.listen((_) => expired++);

      final e = await _apiError(h.api.get('/secure'));
      await pumpEventQueue();
      expect(e.code, ApiErrorCode.internal);
      expect(expired, 0);
      expect((await h.tokens.read())?.accessToken, 'old');
      await sub.cancel();
    });

    test('never sends the token to other hosts', () async {
      await h.tokens.save(
        const AuthTokens(accessToken: 'secret', refreshToken: 'r0'),
      );
      String? seenAuth;
      // Runs after the mock interceptor, which ignores non-mock hosts.
      h.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, handler) {
            seenAuth = o.headers['Authorization'] as String?;
            handler.resolve(
              Response<dynamic>(
                requestOptions: o,
                statusCode: 200,
                data: {'success': true, 'data': null},
              ),
            );
          },
        ),
      );
      await h.api.get('https://api.cloudinary.com/v1_1/demo/image/upload');
      expect(seenAuth, isNull);
    });

    test('INVALID_CREDENTIALS (401) never triggers a refresh', () async {
      h.backend.on(
        'POST',
        '/auth/change-password',
        (r) => throw const MockException.unauthorized('INVALID_CREDENTIALS'),
      );
      h.registerRefresh();
      await h.tokens.save(
        const AuthTokens(accessToken: 'good', refreshToken: 'r0'),
      );
      final e = await _apiError(h.api.post('/auth/change-password'));
      expect(e.code, ApiErrorCode.invalidCredentials);
      expect(e.isUnauthorized, isFalse);
      expect(h.refreshCalls, 0);
    });
  });

  group('ApiException mapping', () {
    final o = RequestOptions(path: '/x');

    test('Dio transport errors', () {
      expect(
        ApiException.fromDio(
          DioException.connectionError(requestOptions: o, reason: 'x'),
        ).code,
        ApiErrorCode.network,
      );
      expect(
        ApiException.fromDio(
          DioException.connectionTimeout(
            timeout: Duration.zero,
            requestOptions: o,
          ),
        ).isNetwork,
        isTrue,
      );
      expect(
        ApiException.fromDio(
          DioException.requestCancelled(requestOptions: o, reason: null),
        ).isCancelled,
        isTrue,
      );
      expect(
        ApiException.from(TimeoutException('t')).code,
        ApiErrorCode.timeout,
      );
      expect(ApiException.from(StateError('x')).code, ApiErrorCode.unknown);
    });

    test('non-envelope HTTP errors map by status', () {
      ApiException status(int s) => ApiException.fromResponse(
        Response<dynamic>(requestOptions: o, statusCode: s, data: '<html>'),
      );
      expect(status(502).code, ApiErrorCode.internal);
      expect(status(404).code, ApiErrorCode.notFound);
      expect(status(401).code, ApiErrorCode.unauthorized);
      expect(status(418).code, ApiErrorCode.unknown);
    });

    test('malformed success body → UNKNOWN', () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'))
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (opt, handler) => handler.resolve(
              Response<dynamic>(
                requestOptions: opt,
                statusCode: 200,
                data: 'oops',
              ),
            ),
          ),
        );
      final e = await _apiError(ApiClient(dio).get('/x'));
      expect(e.code, ApiErrorCode.unknown);
    });
  });
}
