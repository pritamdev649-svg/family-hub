import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/network/api_client.dart';
import 'package:family_hub/core/services/location_service.dart';
import 'package:family_hub/core/utils/formatters.dart';
import 'package:family_hub/features/sos/application/sos_controller.dart';
import 'package:family_hub/features/sos/application/sos_runtime.dart';
import 'package:family_hub/features/sos/data/sos_repository.dart';
import 'package:family_hub/l10n/app_localizations.dart';
import 'package:family_hub/shared/data/me_repository.dart';
import 'package:family_hub/shared/models/auth_user.dart';
import 'package:family_hub/shared/models/family.dart';
import 'package:family_hub/shared/models/member.dart';
import 'package:family_hub/shared/models/session_state.dart';
import 'package:family_hub/shared/providers/shared_providers.dart';

// ── Fixtures ────────────────────────────────────────────────────────────────

const family = Family(
  id: 'f1',
  name: 'Sharma Family',
  country: 'IN',
  currency: 'INR',
  timezone: 'Asia/Kolkata',
);

const amitUser = AuthUser(
  id: 'u-amit',
  email: 'demo@familyhub.app',
  name: 'Amit Sharma',
  emailVerified: true,
  familyId: 'f1',
  memberId: 'm-amit',
);

const amit = Member(
  id: 'm-amit',
  familyId: 'f1',
  userId: 'u-amit',
  name: 'Amit',
  phone: '+919876543210',
  role: MemberRole.admin,
  hasAccount: true,
  locationSharing: LocationSharingMode.sosOnly,
);

const priya = Member(
  id: 'm-priya',
  familyId: 'f1',
  userId: 'u-priya',
  name: 'Priya',
  phone: '+919876543211',
  role: MemberRole.admin,
  hasAccount: true,
  locationSharing: LocationSharingMode.sosOnly,
);

SessionState sessionFor(Member member, {AuthUser user = amitUser}) =>
    SessionState(user: user, member: member, family: family);

/// Fixed "now" used by the tests (UTC).
final testNow = DateTime.utc(2026, 9, 27, 10);

SosAlert alertFor(
  Member member, {
  String id = 'a1',
  SosStatus status = SosStatus.active,
  DateTime? startedAt,
  bool locationShared = true,
  GeoPoint? lastLocation,
  List<GeoPoint> trail = const [],
  SosResolution? resolution,
  DateTime? resolvedAt,
  String? resolvedById,
  String? message,
}) {
  final start = startedAt ?? testNow.subtract(const Duration(minutes: 1));
  return SosAlert(
    id: id,
    memberId: member.id,
    memberName: member.name,
    memberPhone: member.phone,
    status: status,
    startedAt: start,
    expiresAt: start.add(const Duration(minutes: 15)),
    locationShared: locationShared,
    lastLocation: lastLocation,
    trail: trail,
    resolution: resolution,
    resolvedAt: resolvedAt,
    resolvedById: resolvedById,
    message: message,
  );
}

const networkError = ApiException(code: ApiErrorCode.network);
const notActiveError = ApiException(
  code: ApiErrorCode.sosNotActive,
  statusCode: 409,
);

// ── Clock ───────────────────────────────────────────────────────────────────

/// Manually advanced clock (tests run in fake time; `DateTime.now()` is
/// not faked).
class TestClock {
  TestClock([DateTime? start]) : now = start ?? testNow;

  DateTime now;

  DateTime call() => now;

  void advance(Duration d) => now = now.add(d);
}

/// Advances [clock] and fake time together.
Future<void> advance(WidgetTester tester, TestClock clock, Duration d) async {
  clock.advance(d);
  await tester.pump(d);
}

// ── Fakes ───────────────────────────────────────────────────────────────────

/// In-memory [SosRepository] with scripted answers and recorded calls.
class FakeSosRepository implements SosRepository {
  FakeSosRepository({required this.clock, required this.me});

  final TestClock clock;
  Member me;

  /// Server-side alerts by id.
  final Map<String, SosAlert> alerts = {};

  final List<GeoPoint?> createCalls = [];
  final List<(String, GeoPoint)> locationCalls = [];
  final List<(String, SosResolution)> resolveCalls = [];
  final List<String> getCalls = [];
  int activeCalls = 0;

  /// Errors thrown by the next `create` calls (consumed in order).
  final List<Object> createErrors = [];

  /// Error thrown by every `sendLocation` while set.
  Object? locationError;
  Object? resolveError;
  Object? activeError;

  /// When set, `create` waits for it.
  Completer<void>? createGate;

  /// When set, `active` waits for it (a slow refetch).
  Completer<void>? activeGate;

  Paged<SosAlert> historyPage = const Paged<SosAlert>.empty();
  final List<(int, int)> historyCalls = [];

  int _ids = 0;

  @override
  Future<SosAlert> create({GeoPoint? location, String? message}) async {
    createCalls.add(location);
    await Future<void>.delayed(Duration.zero);
    final gate = createGate;
    if (gate != null) await gate.future;
    if (createErrors.isNotEmpty) throw createErrors.removeAt(0);
    for (final a in alerts.values) {
      if (a.memberId == me.id && a.status == SosStatus.active) return a;
    }
    final shared = me.locationSharing != LocationSharingMode.never;
    final alert = SosAlert(
      id: 'new-${++_ids}',
      memberId: me.id,
      memberName: me.name,
      status: SosStatus.active,
      startedAt: clock.now,
      expiresAt: clock.now.add(const Duration(minutes: 15)),
      locationShared: shared,
      lastLocation: shared ? location : null,
    );
    alerts[alert.id] = alert;
    return alert;
  }

  @override
  Future<List<SosAlert>> active() async {
    activeCalls++;
    await Future<void>.delayed(Duration.zero);
    final gate = activeGate;
    if (gate != null) await gate.future;
    final error = activeError;
    if (error != null) throw error;
    return [
      for (final a in alerts.values)
        if (a.isActiveAt(clock.now)) a,
    ]..sort(SosAlert.compareNewestFirst);
  }

  @override
  Future<Paged<SosAlert>> history({int page = 1, int limit = 20}) async {
    historyCalls.add((page, limit));
    await Future<void>.delayed(Duration.zero);
    return historyPage;
  }

  @override
  Future<SosAlert> get(String id) async {
    getCalls.add(id);
    await Future<void>.delayed(Duration.zero);
    final alert = alerts[id];
    if (alert == null) {
      throw const ApiException(code: ApiErrorCode.notFound, statusCode: 404);
    }
    return alert;
  }

  @override
  Future<SosAlert> sendLocation(String id, GeoPoint point) async {
    locationCalls.add((id, point));
    await Future<void>.delayed(Duration.zero);
    final error = locationError;
    if (error != null) throw error;
    final alert = alerts[id];
    if (alert == null || !alert.isActiveAt(clock.now)) throw notActiveError;
    final updated = alert.copyWith(lastLocation: () => point);
    alerts[id] = updated;
    return updated;
  }

  @override
  Future<SosAlert> resolve(String id, SosResolution resolution) async {
    resolveCalls.add((id, resolution));
    await Future<void>.delayed(Duration.zero);
    final error = resolveError;
    if (error != null) throw error;
    final alert = alerts[id];
    if (alert == null) {
      throw const ApiException(code: ApiErrorCode.notFound, statusCode: 404);
    }
    if (alert.status == SosStatus.resolved) return alert;
    final resolved = alert.copyWith(
      status: SosStatus.resolved,
      resolution: () => resolution,
      resolvedAt: () => clock.now,
      resolvedById: () => me.id,
    );
    alerts[id] = resolved;
    return resolved;
  }
}

/// [LocationService] with a scripted permission, one-shot fix and a
/// controllable tracking stream.
class FakeLocationService extends LocationService {
  FakeLocationService({
    this.permission = LocationPermissionState.granted,
    this.fix,
  });

  LocationPermissionState permission;

  /// Permission after [ensurePermission] (defaults to [permission]).
  LocationPermissionState? afterPrompt;
  GeoFix? fix;

  /// When set, [ensurePermission] waits for the member to answer the
  /// system prompt (completing it sets [permission]).
  Completer<LocationPermissionState>? promptGate;

  int checks = 0;
  int prompts = 0;
  int fixes = 0;
  int tracks = 0;
  int cancels = 0;
  int settingsOpened = 0;
  StreamController<GeoFix>? _tracking;

  /// Whether a tracking stream is listened to right now.
  bool get isTracking => _tracking != null;

  @override
  Future<LocationPermissionState> checkPermission() async {
    checks++;
    return permission;
  }

  @override
  Future<LocationPermissionState> ensurePermission({
    bool background = false,
  }) async {
    prompts++;
    final gate = promptGate;
    if (gate != null) permission = await gate.future;
    if (afterPrompt != null) permission = afterPrompt!;
    return permission;
  }

  @override
  Future<GeoFix?> currentFix({Duration? timeout}) async {
    fixes++;
    return fix;
  }

  @override
  Stream<GeoFix> track({
    required String notificationTitle,
    required String notificationText,
    String? channelName,
  }) {
    tracks++;
    late final StreamController<GeoFix> controller;
    controller = StreamController<GeoFix>(
      onCancel: () {
        cancels++;
        if (identical(_tracking, controller)) _tracking = null;
      },
    );
    _tracking = controller;
    return controller.stream;
  }

  /// Emits a fix on the current tracking stream.
  void emit(GeoFix fix) => _tracking?.add(fix);

  void emitError(LocationPermissionState reason) =>
      _tracking?.addError(LocationUnavailableException(reason));

  @override
  Future<bool> openSettings() async {
    settingsOpened++;
    return true;
  }
}

GeoFix fixAt(DateTime at, {double lat = 28.61, double lng = 77.2}) =>
    GeoFix(lat: lat, lng: lng, accuracy: 8, at: at);

/// `PATCH /me` fake: switches the sharing mode.
class FakeMeRepository extends MeRepository {
  FakeMeRepository({required this.member}) : super(ApiClient(Dio()));

  Member member;
  Object? error;
  final List<MePatch> calls = [];

  @override
  Future<({AuthUser user, Member? member})> updateMe(MePatch patch) async {
    calls.add(patch);
    await Future<void>.delayed(Duration.zero);
    final e = error;
    if (e != null) throw e;
    final mode = patch.fields['locationSharing'];
    if (mode != null) {
      member = member.copyWith(
        locationSharing: LocationSharingMode.fromWire(mode),
      );
    }
    return (user: amitUser, member: member);
  }
}

/// Session without persistence / network: starts signed in as [initial].
class FakeSessionController extends SessionController {
  FakeSessionController(this.initial);

  final SessionState initial;
  int applyMeCalls = 0;
  int refreshCalls = 0;

  @override
  Future<SessionState> build() async => initial;

  @override
  Future<void> applyMe([AuthUser? user, Member? member, Family? family]) async {
    applyMeCalls++;
    final current = state.value ?? initial;
    state = AsyncData(
      current.copyWith(
        user: user == null ? null : () => user,
        member: member == null ? null : () => member,
        family: family == null ? null : () => family,
      ),
    );
  }

  @override
  Future<void> refreshMe() async => refreshCalls++;

  /// Replaces the member (e.g. the sharing mode changed elsewhere).
  void setMember(Member member) {
    state = AsyncData((state.value ?? initial).copyWith(member: () => member));
  }
}

/// Foreground flag the tests can flip.
class FakeForeground extends SosAppForeground {
  @override
  bool build() => true;

  void set(bool value) => state = value;
}

// ── Harness ─────────────────────────────────────────────────────────────────

/// Everything the SOS feature needs, faked.
class SosHarness {
  SosHarness({
    Member member = amit,
    LocationPermissionState permission = LocationPermissionState.granted,
    GeoFix? fix,
  }) : clock = TestClock() {
    session = FakeSessionController(sessionFor(member));
    repository = FakeSosRepository(clock: clock, me: member);
    location = FakeLocationService(permission: permission, fix: fix);
    me = FakeMeRepository(member: member);
  }

  final TestClock clock;
  late final FakeSessionController session;
  late final FakeSosRepository repository;
  late final FakeLocationService location;
  late final FakeMeRepository me;

  List<Override> get overrides => [
    sessionControllerProvider.overrideWith(() => session),
    sosRepositoryProvider.overrideWithValue(repository),
    locationServiceProvider.overrideWithValue(location),
    meRepositoryProvider.overrideWithValue(me),
    sosClockProvider.overrideWithValue(clock.call),
    sosAppForegroundProvider.overrideWith(FakeForeground.new),
    sosTrackingTextsProvider.overrideWithValue((
      title: 'Sharing',
      text: 'Your family can see you',
      channel: 'Live location',
    )),
    fmtProvider.overrideWithValue(
      Fmt(locale: const Locale('en'), currency: 'INR', country: 'IN'),
    ),
    membersProvider.overrideWith((ref) async => const [amit, priya]),
  ];

  /// A container whose session is loaded. Like the app (where the home
  /// shell's banner always watches it), the SOS controller is listened to:
  /// Riverpod pauses the subscriptions of unlistened providers.
  Future<ProviderContainer> container({bool listenController = true}) async {
    final c = ProviderContainer(overrides: overrides, retry: (_, _) => null);
    await c.read(sessionControllerProvider.future);
    if (listenController) c.listen(sosControllerProvider, (_, _) {});
    return c;
  }
}

/// Pumps [child] (or the SOS routes at [location]) inside a real
/// [GoRouter] with the app theme and localizations.
Future<GoRouter> pumpSosApp(
  WidgetTester tester, {
  required List<Override> overrides,
  required List<RouteBase> routes,
  required String location,
}) async {
  final router = GoRouter(initialLocation: location, routes: routes);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: overrides,
      child: MediaQuery(
        // Static pulsing indicators so the frames settle.
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp.router(
          theme: AppTheme.light(),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return router;
}

/// Lets pending microtasks / zero-delay futures run in fake time.
Future<void> settle(WidgetTester tester, [int times = 5]) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(Duration.zero);
  }
}
