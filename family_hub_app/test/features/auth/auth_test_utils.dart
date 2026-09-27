// Fakes and harnesses shared by the auth feature tests.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/providers/core_providers.dart';
import 'package:family_hub/core/services/push_notification_service.dart';
import 'package:family_hub/core/utils/formatters.dart';
import 'package:family_hub/features/auth/application/auth_cooldown.dart';
import 'package:family_hub/features/auth/auth_routes.dart';
import 'package:family_hub/l10n/app_localizations.dart';
import 'package:family_hub/shared/data/auth_repository.dart';
import 'package:family_hub/shared/data/family_repository.dart';
import 'package:family_hub/shared/data/me_repository.dart' show DevicePlatform;
import 'package:family_hub/shared/models/models.dart';
import 'package:family_hub/shared/session/session_controller.dart';

const testTokens = AuthTokens(
  accessToken: 'acc',
  refreshToken: 'ref',
  expiresIn: 900,
);

const testFamily = Family(
  id: 'f1',
  name: 'Sharma Family',
  country: 'IN',
  currency: 'INR',
  timezone: 'Asia/Kolkata',
);

const testMember = Member(
  id: 'm1',
  familyId: 'f1',
  name: 'Amit',
  role: MemberRole.admin,
  hasAccount: true,
);

AuthUser testUser({
  String id = 'u1',
  String email = 'amit@example.com',
  bool verified = true,
  bool withFamily = true,
}) => AuthUser(
  id: id,
  email: email,
  name: 'Amit',
  emailVerified: verified,
  familyId: withFamily ? 'f1' : null,
  memberId: withFamily ? 'm1' : null,
  role: withFamily ? MemberRole.admin : null,
);

SessionState completeSession({bool verified = true}) => SessionState(
  user: testUser(verified: verified),
  member: testMember,
  family: testFamily,
);

/// English [AppLocalizations] for pure (non-widget) tests.
AppLocalizations get enL10n => lookupAppLocalizations(const Locale('en'));

/// Queue of errors per method name: the next call throws the first one.
mixin _FailureQueue {
  final List<String> calls = [];
  final Map<String, List<Object>> _failures = {};

  /// Makes the next call of [method] throw [error].
  void failNext(String method, Object error) =>
      (_failures[method] ??= []).add(error);

  /// A call completer per method: when set, the call waits for it (to test
  /// busy states / double submits).
  final Map<String, Completer<void>> gates = {};

  Future<void> step(String method) async {
    calls.add(method);
    await Future<void>.delayed(Duration.zero);
    final gate = gates[method];
    if (gate != null) await gate.future;
    final queue = _failures[method];
    if (queue != null && queue.isNotEmpty) throw queue.removeAt(0);
  }

  int count(String method) => calls.where((c) => c == method).length;
}

/// [AuthRepository] whose "server" account is [account]. `last*` fields
/// record the arguments of the latest call (also when it failed).
class FakeAuthRepository extends Fake
    with _FailureQueue
    implements AuthRepository {
  FakeAuthRepository({SessionState? account, this.tokensStored = false})
    : account = account ?? completeSession();

  /// What login / register / `GET /auth/me` return.
  SessionState account;
  bool tokensStored;
  int resendSeconds = 60;

  RegisterRequest? lastRegister;
  String? lastLoginEmail;
  String? lastLoginPassword;
  String? lastOtp;
  String? lastForgotEmail;
  Map<String, String>? lastReset;

  @override
  Future<AuthResult> register(RegisterRequest request) async {
    lastRegister = request;
    await step('register');
    tokensStored = true;
    return AuthResult(
      user: account.user!,
      tokens: testTokens,
      member: account.member,
      family: account.family,
    );
  }

  @override
  Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    lastLoginEmail = email;
    lastLoginPassword = password;
    await step('login');
    tokensStored = true;
    return AuthResult(user: account.user!, tokens: testTokens);
  }

  @override
  Future<void> logout({
    String? deviceToken,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    calls.add('logout');
    tokensStored = false;
  }

  @override
  Future<AuthUser> verifyEmail(String otp) async {
    lastOtp = otp;
    await step('verifyEmail');
    final user = account.user!.copyWith(emailVerified: true);
    account = account.copyWith(user: () => user);
    return user;
  }

  @override
  Future<int> resendVerification() async {
    await step('resendVerification');
    return resendSeconds;
  }

  @override
  Future<void> forgotPassword(String email) async {
    lastForgotEmail = email;
    await step('forgotPassword');
  }

  @override
  Future<void> resetPassword({
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    lastReset = {'email': email, 'otp': otp, 'newPassword': newPassword};
    await step('resetPassword');
  }

  @override
  Future<SessionState> me() async {
    await step('me');
    return account;
  }

  @override
  Future<bool> hasTokens() async => tokensStored;

  @override
  Future<void> clearTokens() async => tokensStored = false;
}

/// [FamilyRepository] for create / join.
class FakeFamilyRepository extends Fake
    with _FailureQueue
    implements FamilyRepository {
  FakeFamilyRepository(this.result);

  /// The session returned by create / join.
  SessionState result;
  CreateFamilyRequest? lastCreate;
  String? lastJoinCode;

  @override
  Future<SessionState> createFamily(CreateFamilyRequest request) async {
    lastCreate = request;
    await step('createFamily');
    return result;
  }

  @override
  Future<SessionState> joinFamily(String inviteCode) async {
    lastJoinCode = inviteCode;
    await step('joinFamily');
    return result;
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

class NoopPushService extends PushNotificationService {
  NoopPushService() : super(deviceApi: _NoopDeviceApi());

  @override
  Future<void> registerDevice({String? locale}) async {}

  @override
  Future<void> unregisterDevice() async {}
}

/// A controllable clock for cooldowns.
class TestClock {
  TestClock([DateTime? start]) : now = start ?? DateTime(2026, 9, 27, 10);

  DateTime now;

  DateTime call() => now;

  void advance(Duration d) => now = now.add(d);
}

/// A container with the real session controller on top of fake
/// repositories (and no push / secure storage).
Future<ProviderContainer> createAuthContainer({
  FakeAuthRepository? auth,
  FakeFamilyRepository? family,
  TestClock? clock,
  AuthEvents? events,
  List<Override> overrides = const [],
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: authOverrides(
      prefs: prefs,
      auth: auth ?? FakeAuthRepository(),
      family: family,
      clock: clock,
      events: events,
      extra: overrides,
    ),
  );
  addTearDown(container.dispose);
  return container;
}

List<Override> authOverrides({
  required SharedPreferences prefs,
  required FakeAuthRepository auth,
  FakeFamilyRepository? family,
  TestClock? clock,
  AuthEvents? events,
  List<Override> extra = const [],
}) => [
  sharedPreferencesProvider.overrideWithValue(prefs),
  authRepositoryProvider.overrideWithValue(auth),
  if (family != null) familyRepositoryProvider.overrideWithValue(family),
  pushNotificationServiceProvider.overrideWithValue(NoopPushService()),
  authEventsProvider.overrideWithValue(events ?? AuthEvents()),
  if (clock != null) authClockProvider.overrideWithValue(clock.call),
  fmtProvider.overrideWithValue(
    Fmt(locale: const Locale('en'), currency: 'INR', country: 'IN'),
  ),
  ...extra,
];

/// Signs the container's session in as [session] (through the fake
/// repository's login).
Future<void> signIn(ProviderContainer c, FakeAuthRepository auth) async {
  await c.read(sessionControllerProvider.future);
  await c
      .read(sessionControllerProvider.notifier)
      .login(email: auth.account.user!.email, password: 'secret123');
}

/// Pumps the auth routes in a router starting at [location], with the fake
/// repositories. Returns the container and the router.
Future<({ProviderContainer container, GoRouter router})> pumpAuthApp(
  WidgetTester tester, {
  required String location,
  FakeAuthRepository? auth,
  FakeFamilyRepository? family,
  TestClock? clock,
  AuthEvents? events,
  bool signedIn = false,
  List<Override> overrides = const [],
  double textScale = 1,
  TextDirection? textDirection,
  ThemeData? theme,
}) async {
  useTallScreen(tester);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final repo = auth ?? FakeAuthRepository();
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: authOverrides(
      prefs: prefs,
      auth: repo,
      family: family,
      clock: clock,
      events: events,
      extra: overrides,
    ),
  );
  addTearDown(container.dispose);
  if (signedIn) {
    repo.tokensStored = true;
  }
  // Resolve the session before the first frame (no splash in these tests).
  await tester.runAsync(() => container.read(sessionControllerProvider.future));

  final router = GoRouter(
    initialLocation: location,
    routes: [
      ...authRoutes,
      GoRoute(
        path: '/home',
        builder: (_, _) => const Scaffold(body: Text('HOME')),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: theme ?? AppTheme.light(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
        builder: (context, child) {
          Widget app = MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          );
          if (textDirection != null) {
            app = Directionality(textDirection: textDirection, child: app);
          }
          return app;
        },
      ),
    ),
  );
  await tester.pump();
  return (container: container, router: router);
}

/// Lets futures (fake repositories use `Future.delayed(Duration.zero)`) and
/// short animations finish. `pumpAndSettle` is avoided because spinners
/// animate forever.
Future<void> settle(WidgetTester tester, [int frames = 12]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// A phone-width but very tall test surface (400 × 1600 logical pixels), so
/// long forms fit without scrolling while narrow-screen layout is still
/// exercised.
void useTallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 4800);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}
