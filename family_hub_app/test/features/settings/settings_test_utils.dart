// Shared fixtures and fakes for the settings feature tests.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/providers/core_providers.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/services/location_service.dart';
import 'package:family_hub/core/services/push_notification_service.dart';
import 'package:family_hub/core/utils/formatters.dart';
import 'package:family_hub/features/settings/application/location_upload_clock.dart';
import 'package:family_hub/features/settings/data/system_settings.dart';
import 'package:family_hub/features/settings/domain/notification_status.dart';
import 'package:family_hub/l10n/app_localizations.dart';
import 'package:family_hub/shared/models/models.dart';
import 'package:family_hub/shared/session/session_controller.dart';

import '../../shared/shared_fakes.dart';

export '../../shared/shared_fakes.dart'
    show ApiCall, ApiHandler, FakeApiClient, FakePushService, settle;

// ── Fixtures ────────────────────────────────────────────────────────────────

const familyId = 'f1';
const memberId = 'm1';
const userId = 'u1';

Map<String, dynamic> userJson([Map<String, dynamic> overrides = const {}]) => {
  'id': userId,
  'email': 'amit@example.com',
  'name': 'Amit Sharma',
  'emailVerified': true,
  'locale': 'en',
  'familyId': familyId,
  'memberId': memberId,
  'role': 'admin',
  'createdAt': '2026-01-01T00:00:00.000Z',
  ...overrides,
};

Map<String, dynamic> memberJson([Map<String, dynamic> overrides = const {}]) =>
    {
      'id': memberId,
      'familyId': familyId,
      'userId': userId,
      'name': 'Amit',
      'email': 'amit@example.com',
      'phone': '+919876543210',
      'avatarUrl': null,
      'dateOfBirth': '1985-01-31T18:30:00.000Z',
      'gender': 'male',
      'designation': 'Head of Family',
      'role': 'admin',
      'hasAccount': true,
      'locationSharing': 'never',
      'lastLocation': null,
      'guardianConsent': false,
      'createdAt': '2026-01-01T00:00:00.000Z',
      'updatedAt': '2026-01-01T00:00:00.000Z',
      ...overrides,
    };

Map<String, dynamic> familyJson([Map<String, dynamic> overrides = const {}]) =>
    {
      'id': familyId,
      'name': 'Sharma Family',
      'inviteCode': 'K7Q2M9XD',
      'country': 'IN',
      'currency': 'INR',
      'timezone': 'Asia/Kolkata',
      'ownerId': userId,
      'memberCount': 5,
      'createdAt': '2026-01-01T00:00:00.000Z',
      ...overrides,
    };

SessionState sessionWith({
  Map<String, dynamic> user = const {},
  Map<String, dynamic> member = const {},
  Map<String, dynamic> family = const {},
  bool withFamily = true,
}) => SessionState(
  user: AuthUser.fromJson(
    userJson({
      if (!withFamily) ...{'familyId': null, 'memberId': null, 'role': null},
      ...user,
    }),
  ),
  member: withFamily ? Member.fromJson(memberJson(member)) : null,
  family: withFamily ? Family.fromJson(familyJson(family)) : null,
);

/// `{ user, member }` as returned by `PATCH /me`.
Map<String, dynamic> meResponse({
  Map<String, dynamic> user = const {},
  Map<String, dynamic> member = const {},
}) => {'user': userJson(user), 'member': memberJson(member)};

// ── Fakes ───────────────────────────────────────────────────────────────────

/// Session whose restore returns [initial]; every other method is the real
/// [SessionController] (applyMe, leaveFamily, deleteAccount, logout …).
class FixedSession extends SessionController {
  FixedSession(this.initial);

  final SessionState initial;

  @override
  Future<SessionState> build() async => initial;
}

/// Scripted [LocationService].
class FakeLocationService extends LocationService {
  FakeLocationService({
    this.permission = LocationPermissionState.granted,
    this.fix,
  });

  LocationPermissionState permission;

  /// State after [ensurePermission] (defaults to [permission]).
  LocationPermissionState? afterRequest;
  GeoFix? fix;
  int checks = 0;
  int requests = 0;
  int fixes = 0;
  int settingsOpened = 0;

  @override
  Future<LocationPermissionState> checkPermission() async {
    checks++;
    return permission;
  }

  @override
  Future<LocationPermissionState> ensurePermission({
    bool background = false,
  }) async {
    requests++;
    if (afterRequest != null) permission = afterRequest!;
    return permission;
  }

  @override
  Future<GeoFix?> currentFix({Duration? timeout}) async {
    fixes++;
    return fix;
  }

  @override
  Future<bool> openSettings() async {
    settingsOpened++;
    return true;
  }
}

GeoFix testFix({
  double lat = 28.61,
  double lng = 77.2,
  double? accuracy = 12,
}) => GeoFix(
  lat: lat,
  lng: lng,
  accuracy: accuracy,
  at: DateTime.utc(2026, 9, 26, 10),
);

class FakeSystemSettings implements SystemSettingsGateway {
  FakeSystemSettings([this.status = NotificationStatus.enabled]);

  NotificationStatus status;
  int opened = 0;

  @override
  Future<NotificationStatus> notificationStatus() async => status;

  @override
  Future<bool> openAppSettings() async {
    opened++;
    return true;
  }
}

/// A controllable clock for throttling tests.
class TestClock {
  TestClock([DateTime? start]) : now = start ?? DateTime(2026, 9, 26, 10);

  DateTime now;

  void advance(Duration d) => now = now.add(d);

  DateTime call() => now;
}

// ── Harness ─────────────────────────────────────────────────────────────────

/// Everything a settings test needs, in one [ProviderContainer].
class SettingsHarness {
  SettingsHarness._({
    required this.container,
    required this.api,
    required this.tokens,
    required this.push,
    required this.location,
    required this.system,
    required this.clock,
  });

  static Future<SettingsHarness> create({
    SessionState? session,
    Map<String, ApiHandler>? handlers,
    FakeLocationService? location,
    FakeSystemSettings? system,
    Map<String, Object> prefs = const {},
    List<Override> overrides = const [],
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    final sp = await SharedPreferences.getInstance();
    final api = FakeApiClient(handlers);
    final tokens = FakeTokenStorage(
      const AuthTokens(accessToken: 'acc', refreshToken: 'ref'),
    );
    final push = FakePushService();
    final loc = location ?? FakeLocationService();
    final sys = system ?? FakeSystemSettings();
    final clock = TestClock();
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sp),
        apiClientProvider.overrideWithValue(api),
        tokenStorageProvider.overrideWithValue(tokens),
        pushNotificationServiceProvider.overrideWithValue(push),
        locationServiceProvider.overrideWithValue(loc),
        systemSettingsProvider.overrideWithValue(sys),
        settingsClockProvider.overrideWithValue(clock.call),
        fmtProvider.overrideWithValue(
          Fmt(locale: const Locale('en'), currency: 'INR', country: 'IN'),
        ),
        sessionControllerProvider.overrideWith(
          () => FixedSession(session ?? sessionWith()),
        ),
        ...overrides,
      ],
    );
    await container.read(sessionControllerProvider.future);
    return SettingsHarness._(
      container: container,
      api: api,
      tokens: tokens,
      push: push,
      location: loc,
      system: sys,
      clock: clock,
    );
  }

  final ProviderContainer container;
  final FakeApiClient api;
  final FakeTokenStorage tokens;
  final FakePushService push;
  final FakeLocationService location;
  final FakeSystemSettings system;
  final TestClock clock;

  SessionState get session =>
      container.read(sessionControllerProvider).value ?? SessionState.signedOut;

  void dispose() => container.dispose();
}

/// Paths every settings screen may navigate to; each renders a marker text
/// `route:<path>` so tests can assert navigation.
const _navigationTargets = <String>[
  AppRoutes.more,
  AppRoutes.members,
  AppRoutes.familySettings,
  AppRoutes.notices,
  AppRoutes.emergencyCards,
  AppRoutes.sosHistory,
  AppRoutes.settingsProfile,
  AppRoutes.settingsLanguage,
  AppRoutes.settingsAppearance,
  AppRoutes.settingsLocation,
  AppRoutes.settingsPrivacy,
  AppRoutes.settingsPassword,
  AppRoutes.settingsAbout,
];

/// Pumps [screen] at `/screen` inside a localised `MaterialApp.router`
/// sharing [h]'s container. Returns the router.
///
/// [textScale] / [textDirection] exercise large text and RTL layouts.
Future<GoRouter> pumpSettingsScreen(
  WidgetTester tester,
  SettingsHarness h,
  Widget screen, {
  double? textScale,
  TextDirection? textDirection,
  Size surfaceSize = const Size(800, 2400),
}) async {
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final router = GoRouter(
    initialLocation: '/screen',
    routes: [
      GoRoute(path: '/screen', builder: (_, _) => screen),
      for (final path in _navigationTargets)
        GoRoute(
          path: path,
          builder: (_, _) => Scaffold(body: Text('route:$path')),
        ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: h.container,
      child: MaterialApp.router(
        routerConfig: router,
        theme: AppTheme.light(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) {
          var app = child ?? const SizedBox.shrink();
          if (textDirection != null) {
            app = Directionality(textDirection: textDirection, child: app);
          }
          if (textScale != null) {
            app = MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: app,
            );
          }
          return app;
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

/// English strings for assertions.
Future<AppLocalizations> englishL10n() =>
    AppLocalizations.delegate.load(const Locale('en'));

/// Unwraps a future expected to fail.
Future<Object> errorOf(Future<Object?> f) async {
  try {
    await f;
  } catch (e) {
    return e;
  }
  fail('expected an error');
}
