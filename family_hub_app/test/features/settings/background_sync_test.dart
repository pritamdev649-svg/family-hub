import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/network/api_exception.dart';
import 'package:family_hub/core/services/location_service.dart';
import 'package:family_hub/features/settings/application/background_sync.dart';
import 'package:family_hub/features/settings/application/location_upload_clock.dart';

import 'settings_test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SettingsHarness h;
  tearDown(() => h.dispose());

  Future<SettingsHarness> harness({
    String mode = 'always',
    FakeLocationService? location,
    ApiHandler? upload,
  }) => SettingsHarness.create(
    session: sessionWith(member: {'locationSharing': mode}),
    location: location ?? FakeLocationService(fix: testFix()),
    handlers: {
      'PUT /me/location':
          upload ?? (_) => {'recordedAt': '2026-09-26T10:00:00.000Z'},
    },
  );

  BackgroundLocationSync sync() {
    // Keep the auto-dispose provider alive for the test.
    final sub = h.container.listen(backgroundSyncProvider, (_, _) {});
    addTearDown(sub.close);
    return sub.read();
  }

  test('"always": uploads, then at most once per 10 minutes', () async {
    h = await harness();
    final s = sync();

    expect(await s.syncIfDue(), isTrue);
    expect(h.api.callsTo('PUT /me/location').single.json, {
      'lat': 28.61,
      'lng': 77.2,
      'accuracy': 12.0,
    });

    h.clock.advance(const Duration(minutes: 9, seconds: 59));
    expect(await s.syncIfDue(), isFalse);
    expect(h.api.callsTo('PUT /me/location'), hasLength(1));

    h.clock.advance(const Duration(seconds: 1));
    expect(await s.syncIfDue(), isTrue);
    expect(h.api.callsTo('PUT /me/location'), hasLength(2));
  });

  for (final mode in ['never', 'sos_only']) {
    test('"$mode" never reads the location', () async {
      h = await harness(mode: mode);
      expect(await sync().syncIfDue(), isFalse);
      expect(h.location.checks, 0);
      expect(h.location.fixes, 0);
      expect(h.api.calls, isEmpty);
    });
  }

  test('never prompts: missing permission is skipped silently', () async {
    final location = FakeLocationService(
      permission: LocationPermissionState.denied,
      fix: testFix(),
    );
    h = await harness(location: location);

    expect(await sync().syncIfDue(), isFalse);
    expect(location.requests, 0, reason: 'no permission prompt');
    expect(location.fixes, 0);
    expect(h.api.calls, isEmpty);
  });

  test('no GPS fix → nothing uploaded', () async {
    h = await harness(location: FakeLocationService());
    expect(await sync().syncIfDue(), isFalse);
    expect(h.api.calls, isEmpty);
  });

  test('API errors are swallowed and retried on the next resume', () async {
    var fail = true;
    h = await harness(
      upload: (_) {
        if (fail) {
          throw const ApiException(
            code: ApiErrorCode.locationSharingDisabled,
            statusCode: 403,
          );
        }
        return {'recordedAt': '2026-09-26T10:00:00.000Z'};
      },
    );
    final s = sync();

    expect(await s.syncIfDue(), isFalse);
    expect(h.container.read(locationUploadClockProvider), isNull);

    fail = false;
    expect(await s.syncIfDue(), isTrue, reason: 'a failure is not throttled');
  });

  test('concurrent triggers share one upload', () async {
    h = await harness();
    final s = sync();
    final results = await Future.wait([s.syncIfDue(), s.syncIfDue()]);
    expect(results, [isTrue, isTrue]);
    expect(h.api.callsTo('PUT /me/location'), hasLength(1));
  });

  test('a manual share also resets the throttle window', () async {
    h = await harness();
    h.container.read(locationUploadClockProvider.notifier).record();
    expect(await sync().syncIfDue(), isFalse);
    expect(h.api.calls, isEmpty);
  });

  testWidgets('uploads on start and when the app resumes', (tester) async {
    h = await harness();
    final sub = h.container.listen(backgroundSyncProvider, (_, _) {});
    addTearDown(sub.close);

    // The start-up sync runs at the end of the next frame.
    tester.binding.scheduleFrame();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    expect(h.api.callsTo('PUT /me/location'), hasLength(1));

    h.clock.advance(const Duration(minutes: 11));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 10));
    expect(h.api.callsTo('PUT /me/location'), hasLength(2));
  });

  // ── Session freshness + fix quality (f-settings-harden) ───────────────────

  Map<String, dynamic> authMe(String mode) => {
    'user': userJson(),
    'member': memberJson({'locationSharing': mode}),
    'family': familyJson(),
  };

  test('resume re-reads the session at most every 2 minutes', () async {
    h = await harness();
    h.api.on('GET /auth/me', (_) => authMe('always'));
    final s = sync();

    await s.onResume();
    expect(
      h.api.callsTo('GET /auth/me'),
      isEmpty,
      reason: 'the session was just restored when the shell started',
    );
    expect(h.api.callsTo('PUT /me/location'), hasLength(1));

    h.clock.advance(BackgroundLocationSync.sessionRefreshInterval);
    await s.onResume();
    expect(h.api.callsTo('GET /auth/me'), hasLength(1));

    h.clock.advance(const Duration(minutes: 1));
    await s.onResume();
    expect(h.api.callsTo('GET /auth/me'), hasLength(1));
  });

  test('a mode changed elsewhere is picked up before uploading', () async {
    h = await harness();
    // On another phone the member switched to "never".
    h.api.on('GET /auth/me', (_) => authMe('never'));
    final s = sync();
    h.clock.advance(const Duration(minutes: 5));

    await s.onResume();

    expect(h.session.member!.locationSharing.name, 'never');
    expect(h.api.callsTo('PUT /me/location'), isEmpty);
  });

  test('a failing session refresh is ignored; location still syncs', () async {
    h = await harness();
    h.api.on('GET /auth/me', (_) => throw const ApiException.network());
    final s = sync();
    h.clock.advance(const Duration(minutes: 5));

    await s.onResume();
    expect(h.api.callsTo('GET /auth/me'), hasLength(1));

    expect(h.session.isSignedIn, isTrue);
    expect(h.api.callsTo('PUT /me/location'), hasLength(1));
  });

  test('LOCATION_SHARING_DISABLED resyncs the session', () async {
    h = await harness(
      upload: (_) => throw const ApiException(
        code: ApiErrorCode.locationSharingDisabled,
        statusCode: 403,
      ),
    );
    h.api.on('GET /auth/me', (_) => authMe('sos_only'));

    expect(await sync().syncIfDue(), isFalse);
    await settle();

    expect(h.api.callsTo('GET /auth/me'), hasLength(1));
    expect(h.session.member!.locationSharing.name, 'sosOnly');
  });

  test('an old cached position is not uploaded', () async {
    final location = FakeLocationService();
    h = await harness(location: location);
    location.fix = GeoFix(
      lat: 1,
      lng: 2,
      at: h.clock.now.toUtc().subtract(const Duration(hours: 1)),
      isLastKnown: true,
    );

    expect(await sync().syncIfDue(), isFalse);
    expect(h.api.calls, isEmpty);
  });
}
