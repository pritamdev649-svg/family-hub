// End-to-end check of the mock-mode wiring with the real providers:
// ProviderContainer → apiClientProvider → dioProvider (reachability, locale
// and auth interceptors) → mockBackendProvider (registerAllMocks) → the
// `/auth` mock handlers, with the core demo seed (MockSeed).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:family_hub/core/config/app_config.dart';
import 'package:family_hub/core/network/mock/mock_backend.dart';
import 'package:family_hub/core/providers/core_providers.dart';
import 'package:family_hub/shared/models/models.dart';
import 'package:family_hub/shared/session/session_controller.dart';

/// A fresh app container (empty prefs and secure storage, new in-memory
/// mock database), disposed after the test.
Future<ProviderContainer> _createContainer() async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);
  return container;
}

Future<ApiException> _apiError(Future<Object?> future) async {
  try {
    await future;
  } on ApiException catch (e) {
    return e;
  }
  fail('expected an ApiException');
}

Map<String, dynamic> _loginBody([String password = MockSeed.demoPassword]) => {
  'email': MockSeed.demoEmail,
  'password': password,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('tests run against the in-memory mock backend', () async {
    expect(AppConfig.useMockApi, isTrue);
    final container = await _createContainer();
    final backend = container.read(mockBackendProvider);
    expect(backend, isNotNull);
    // Every feature registrar ran; core + auth routes are present.
    expect(
      backend!.routes,
      containsAll(<String>[
        'GET /health',
        'POST /auth/login',
        'POST /auth/refresh',
        'POST /auth/logout',
        'GET /auth/me',
      ]),
    );
    expect(await container.read(apiClientProvider).get('/health'), {
      'status': 'ok',
      'db': 'up',
      'version': '1.0.0-mock',
    });
  });

  group('POST /auth/login through ApiClient', () {
    test('demo account → { user, tokens } in the contract shape', () async {
      final container = await _createContainer();
      final api = container.read(apiClientProvider);

      final data = await api.post('/auth/login', body: _loginBody());

      expect(data, isA<Map<String, dynamic>>());
      final json = data as Map<String, dynamic>;
      final userJson = json['user'] as Map<String, dynamic>;
      expect(userJson.containsKey('password'), isFalse);

      final user = AuthUser.fromJson(userJson);
      expect(user.id, MockSeed.amitUserId);
      expect(user.email, MockSeed.demoEmail);
      expect(user.emailVerified, isTrue);
      expect(user.familyId, MockSeed.familyId);
      expect(user.memberId, MockSeed.amitMemberId);
      expect(user.role, MemberRole.admin);

      final tokens = AuthTokens.fromJson(
        json['tokens'] as Map<String, dynamic>,
      );
      expect(
        tokens.accessToken,
        MockRequest.accessTokenFor(MockSeed.amitUserId),
      );
      expect(
        tokens.refreshToken,
        startsWith('${MockRequest.refreshPrefix}${MockSeed.amitUserId}.'),
      );
      expect(tokens.expiresIn, MockTokens.expiresIn);

      // Stored tokens authenticate the next request (AuthInterceptor).
      await container.read(tokenStorageProvider).save(tokens);
      final me = await container.read(authRepositoryProvider).me();
      expect(me.isComplete, isTrue);
      expect(me.member?.id, MockSeed.amitMemberId);
      expect(me.family?.name, 'Sharma Family');
      expect(me.family?.inviteCode, MockSeed.inviteCode); // admins only
    });

    test('email is trimmed and matched case-insensitively', () async {
      final container = await _createContainer();
      final data = await container
          .read(apiClientProvider)
          .post(
            '/auth/login',
            body: {
              'email': '  Demo@FamilyHub.APP ',
              'password': MockSeed.demoPassword,
            },
          );
      expect(((data as Map)['user'] as Map)['id'], MockSeed.amitUserId);
    });

    test('wrong password → 401 INVALID_CREDENTIALS, no refresh, no sign-out '
        'event', () async {
      final container = await _createContainer();
      var expiredEvents = 0;
      final sub = container
          .read(authEventsProvider)
          .sessionExpired
          .listen((_) => expiredEvents++);
      addTearDown(sub.cancel);

      final e = await _apiError(
        container
            .read(apiClientProvider)
            .post('/auth/login', body: _loginBody('wrong-password')),
      );

      expect(e.code, ApiErrorCode.invalidCredentials);
      expect(e.statusCode, 401);
      expect(e.isUnauthorized, isFalse);
      await pumpEventQueue();
      expect(expiredEvents, 0);
      expect(await container.read(tokenStorageProvider).read(), isNull);
      // The server answered, so the app is not offline.
      expect(
        container.read(connectivityStatusProvider),
        ConnectivityStatus.online,
      );
    });

    test('unknown email gives the same error as a wrong password', () async {
      final container = await _createContainer();
      final e = await _apiError(
        container
            .read(apiClientProvider)
            .post(
              '/auth/login',
              body: {'email': 'nobody@familyhub.app', 'password': 'demo1234'},
            ),
      );
      expect(e.code, ApiErrorCode.invalidCredentials);
    });

    test('missing fields → 422 VALIDATION_ERROR with field details', () async {
      final container = await _createContainer();
      final e = await _apiError(
        container
            .read(apiClientProvider)
            .post('/auth/login', body: {'email': 'not-an-email'}),
      );
      expect(e.code, ApiErrorCode.validation);
      expect(e.statusCode, 422);
      expect(e.fieldErrors.keys, containsAll(<String>['email', 'password']));
    });
  });

  test('POST /auth/refresh rotates tokens and detects reuse', () async {
    final container = await _createContainer();
    final api = container.read(apiClientProvider);
    final login = await api.post('/auth/login', body: _loginBody());
    final first = AuthTokens.fromJson(
      (login as Map)['tokens'] as Map<String, dynamic>,
    );

    final rotated = await api.post(
      '/auth/refresh',
      body: {'refreshToken': first.refreshToken},
    );
    final second = AuthTokens.fromJson(
      (rotated as Map)['tokens'] as Map<String, dynamic>,
    );
    expect(second.refreshToken, isNot(first.refreshToken));

    // Reusing the rotated-out token is rejected and revokes every token.
    final reuse = await _apiError(
      api.post('/auth/refresh', body: {'refreshToken': first.refreshToken}),
    );
    expect(reuse.code, ApiErrorCode.invalidRefreshToken);
    final revoked = await _apiError(
      api.post('/auth/refresh', body: {'refreshToken': second.refreshToken}),
    );
    expect(revoked.code, ApiErrorCode.invalidRefreshToken);
  });

  group('SessionController with the mock backend', () {
    test(
      'login → complete session; logout → signed out and token revoked',
      () async {
        final container = await _createContainer();
        container.listen(sessionControllerProvider, (_, _) {});

        expect(
          await container.read(sessionControllerProvider.future),
          SessionState.signedOut,
        );

        final notifier = container.read(sessionControllerProvider.notifier);
        await notifier.login(
          email: ' Demo@FamilyHub.app ',
          password: MockSeed.demoPassword,
        );

        final session = container.read(sessionControllerProvider).value;
        expect(session, isNotNull);
        expect(session!.isComplete, isTrue);
        expect(session.user?.id, MockSeed.amitUserId);
        expect(session.member?.id, MockSeed.amitMemberId);
        expect(session.member?.designation, 'Head of Family');
        expect(session.family?.id, MockSeed.familyId);
        expect(session.family?.currency, 'INR');
        expect(container.read(sessionUserIdProvider), MockSeed.amitUserId);
        expect(container.read(isAdminProvider), isTrue);
        expect(container.read(currentCountryProvider).code, 'IN');

        final stored = await container.read(tokenStorageProvider).read();
        expect(
          stored?.accessToken,
          MockRequest.accessTokenFor(MockSeed.amitUserId),
        );

        await notifier.logout();

        expect(
          container.read(sessionControllerProvider).value,
          SessionState.signedOut,
        );
        expect(container.read(sessionUserIdProvider), isNull);
        expect(await container.read(tokenStorageProvider).read(), isNull);
        final tokenDoc = container
            .read(mockBackendProvider)!
            .db
            .findOne(
              MockDb.refreshTokens,
              (t) => t['token'] == stored!.refreshToken,
            );
        expect(tokenDoc?['revokedAt'], isNotNull);

        // Signed out: protected endpoints answer 401 without a refresh loop.
        final e = await _apiError(
          container.read(apiClientProvider).get('/auth/me'),
        );
        expect(e.code, ApiErrorCode.unauthorized);
      },
    );

    test('wrong password leaves the session signed out', () async {
      final container = await _createContainer();
      container.listen(sessionControllerProvider, (_, _) {});
      await container.read(sessionControllerProvider.future);

      final e = await _apiError(
        container
            .read(sessionControllerProvider.notifier)
            .login(email: MockSeed.demoEmail, password: 'nope1234'),
      );
      expect(e.code, ApiErrorCode.invalidCredentials);
      expect(
        container.read(sessionControllerProvider).value,
        SessionState.signedOut,
      );
    });
  });
}
