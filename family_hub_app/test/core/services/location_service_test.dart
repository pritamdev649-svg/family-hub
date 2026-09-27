import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:family_hub/core/services/location_service.dart';

Position _position({
  double lat = 28.61,
  double lng = 77.2,
  double accuracy = 12.5,
  DateTime? at,
}) => Position(
  latitude: lat,
  longitude: lng,
  timestamp: at ?? DateTime.utc(2026, 9, 26, 10),
  accuracy: accuracy,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

class _FakePlatform extends LocationPlatform {
  _FakePlatform();

  bool serviceEnabled = true;
  LocationPermission permission = LocationPermission.whileInUse;
  LocationPermission afterRequest = LocationPermission.whileInUse;
  int requestCount = 0;
  Completer<LocationPermission>? requestGate;
  Object? requestError;

  Future<Position> Function()? current;
  Position? lastKnown;
  Object? lastKnownError;

  late StreamController<Position> positions;
  LocationSettings? streamSettings;
  bool streamCancelled = false;

  bool openedLocationSettings = false;
  bool openedAppSettings = false;

  TargetPlatform targetPlatform = TargetPlatform.android;

  @override
  Future<bool> isServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async {
    requestCount++;
    if (requestError != null) throw requestError!;
    final gate = requestGate;
    if (gate != null) return gate.future;
    permission = afterRequest;
    return afterRequest;
  }

  @override
  Future<Position> currentPosition(LocationSettings settings) =>
      current?.call() ?? Future.value(_position());

  @override
  Future<Position?> lastKnownPosition() async {
    if (lastKnownError != null) throw lastKnownError!;
    return lastKnown;
  }

  @override
  Stream<Position> positionStream(LocationSettings settings) {
    streamSettings = settings;
    positions = StreamController<Position>(
      onCancel: () => streamCancelled = true,
    );
    return positions.stream;
  }

  @override
  Future<bool> openAppSettings() async => openedAppSettings = true;

  @override
  Future<bool> openLocationSettings() async => openedLocationSettings = true;

  @override
  bool get isWeb => false;

  @override
  TargetPlatform get platform => targetPlatform;
}

void main() {
  late _FakePlatform platform;
  late LocationService service;

  setUp(() {
    platform = _FakePlatform();
    service = LocationService(
      platform: platform,
      fixTimeout: const Duration(milliseconds: 50),
    );
  });

  group('GeoFix', () {
    test('fromPosition keeps valid values and drops unknown accuracy', () {
      final fix = GeoFix.fromPosition(_position(accuracy: -1))!;
      expect(fix.lat, 28.61);
      expect(fix.lng, 77.2);
      expect(fix.accuracy, isNull);
      expect(fix.at.isUtc, isTrue);
      expect(fix.toJson(), {'lat': 28.61, 'lng': 77.2});
    });

    test('fromPosition rejects out-of-range or NaN coordinates', () {
      expect(GeoFix.fromPosition(_position(lat: 91)), isNull);
      expect(GeoFix.fromPosition(_position(lng: -181)), isNull);
      expect(GeoFix.fromPosition(_position(lat: double.nan)), isNull);
    });

    test('toJson includes accuracy when known; value equality', () {
      final a = GeoFix.fromPosition(_position())!;
      final b = GeoFix.fromPosition(_position())!;
      expect(a.toJson(), {'lat': 28.61, 'lng': 77.2, 'accuracy': 12.5});
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.toGeoPoint().recordedAt, a.at);
    });
  });

  group('ensurePermission', () {
    test('service disabled wins and does not prompt', () async {
      platform.serviceEnabled = false;
      platform.permission = LocationPermission.denied;
      expect(
        await service.ensurePermission(),
        LocationPermissionState.serviceDisabled,
      );
      expect(platform.requestCount, 0);
    });

    test('already granted does not prompt', () async {
      platform.permission = LocationPermission.always;
      expect(await service.ensurePermission(), LocationPermissionState.granted);
      expect(platform.requestCount, 0);
    });

    test('denied prompts and maps the answer', () async {
      platform.permission = LocationPermission.denied;
      platform.afterRequest = LocationPermission.whileInUse;
      expect(
        await service.ensurePermission(background: true),
        LocationPermissionState.granted,
      );
      expect(platform.requestCount, 1);

      platform.permission = LocationPermission.denied;
      platform.afterRequest = LocationPermission.denied;
      expect(await service.ensurePermission(), LocationPermissionState.denied);
    });

    test('deniedForever is reported without prompting', () async {
      platform.permission = LocationPermission.deniedForever;
      expect(
        await service.ensurePermission(),
        LocationPermissionState.deniedForever,
      );
      expect(platform.requestCount, 0);
    });

    test('concurrent calls share a single system prompt', () async {
      platform.permission = LocationPermission.denied;
      platform.requestGate = Completer<LocationPermission>();
      final a = service.ensurePermission();
      final b = service.ensurePermission();
      await Future<void>.delayed(Duration.zero);
      platform.requestGate!.complete(LocationPermission.whileInUse);
      expect(await a, LocationPermissionState.granted);
      expect(await b, LocationPermissionState.granted);
      expect(platform.requestCount, 1);
    });

    test('plugin errors become denied instead of throwing', () async {
      platform.permission = LocationPermission.denied;
      platform.requestError = const PermissionRequestInProgressException('x');
      expect(await service.ensurePermission(), LocationPermissionState.denied);
    });
  });

  group('currentFix', () {
    test('returns null without permission and never prompts', () async {
      platform.permission = LocationPermission.denied;
      expect(await service.currentFix(), isNull);
      expect(platform.requestCount, 0);
    });

    test('returns a fresh fix', () async {
      final fix = await service.currentFix();
      expect(fix, isNotNull);
      expect(fix!.isLastKnown, isFalse);
      expect(fix.accuracy, 12.5);
    });

    test('falls back to last known position on timeout', () async {
      platform.current = () => Completer<Position>().future; // never answers
      platform.lastKnown = _position(lat: 10, lng: 20);
      final fix = await service.currentFix();
      expect(fix, isNotNull);
      expect(fix!.isLastKnown, isTrue);
      expect(fix.lat, 10);
    });

    test('falls back to last known position when the service is off', () async {
      platform.serviceEnabled = false;
      platform.lastKnown = _position(lat: 1, lng: 2);
      final fix = await service.currentFix();
      expect(fix?.isLastKnown, isTrue);
    });

    test('returns null when nothing is available', () async {
      platform.current = () => Future.error(Exception('gps failure'));
      platform.lastKnownError = Exception('no cache');
      expect(await service.currentFix(), isNull);
    });
  });

  group('track', () {
    test('emits a LocationUnavailableException when not granted', () async {
      platform.permission = LocationPermission.deniedForever;
      final events = <Object>[];
      final done = Completer<void>();
      service
          .track(notificationTitle: 't', notificationText: 'x')
          .listen(events.add, onError: events.add, onDone: done.complete);
      await done.future;
      expect(events, hasLength(1));
      expect(
        (events.single as LocationUnavailableException).reason,
        LocationPermissionState.deniedForever,
      );
      expect(platform.streamSettings, isNull);
    });

    test('streams fixes with Android foreground-service settings', () async {
      final fixes = <GeoFix>[];
      final errors = <Object>[];
      final sub = service
          .track(
            notificationTitle: 'Sharing',
            notificationText: 'Family can see you',
            channelName: 'Live location',
          )
          .listen(fixes.add, onError: errors.add);
      await Future<void>.delayed(Duration.zero);

      final settings = platform.streamSettings;
      expect(settings, isA<AndroidSettings>());
      final android = settings! as AndroidSettings;
      expect(android.distanceFilter, service.trackingDistanceFilterMeters);
      expect(
        android.foregroundNotificationConfig?.notificationTitle,
        'Sharing',
      );
      expect(
        android.foregroundNotificationConfig?.notificationChannelName,
        'Live location',
      );

      platform.positions.add(_position(lat: 1, lng: 1));
      platform.positions.add(_position(lat: 91, lng: 1)); // invalid, dropped
      platform.positions.addError(const LocationServiceDisabledException());
      platform.positions.add(_position(lat: 2, lng: 2));
      await Future<void>.delayed(Duration.zero);

      expect(fixes.map((f) => f.lat), [1, 2]);
      expect(errors, hasLength(1));
      expect(
        (errors.single as LocationUnavailableException).reason,
        LocationPermissionState.serviceDisabled,
      );

      await sub.cancel();
      expect(platform.streamCancelled, isTrue);
    });

    test('uses Apple background settings on iOS', () async {
      platform.targetPlatform = TargetPlatform.iOS;
      final sub = service
          .track(notificationTitle: 't', notificationText: 'x')
          .listen((_) {});
      await Future<void>.delayed(Duration.zero);
      final settings = platform.streamSettings;
      expect(settings, isA<AppleSettings>());
      final apple = settings! as AppleSettings;
      expect(apple.allowBackgroundLocationUpdates, isTrue);
      expect(apple.showBackgroundLocationIndicator, isTrue);
      expect(apple.pauseLocationUpdatesAutomatically, isFalse);
      await sub.cancel();
    });

    test(
      'cancelling before permission resolves never starts the stream',
      () async {
        final sub = service
            .track(notificationTitle: 't', notificationText: 'x')
            .listen((_) {});
        await sub.cancel();
        await Future<void>.delayed(Duration.zero);
        expect(platform.streamSettings, isNull);
      },
    );
  });

  group('openSettings', () {
    test('opens location settings when the service is off', () async {
      platform.serviceEnabled = false;
      expect(await service.openSettings(), isTrue);
      expect(platform.openedLocationSettings, isTrue);
      expect(platform.openedAppSettings, isFalse);
    });

    test('opens app settings otherwise', () async {
      expect(await service.openSettings(), isTrue);
      expect(platform.openedAppSettings, isTrue);
    });
  });

  test('state helpers', () {
    expect(LocationPermissionState.granted.isGranted, isTrue);
    expect(LocationPermissionState.deniedForever.needsSettings, isTrue);
    expect(LocationPermissionState.serviceDisabled.needsSettings, isTrue);
    expect(LocationPermissionState.denied.needsSettings, isFalse);
  });
}
