import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/network/api_exception.dart';
import 'package:family_hub/core/services/location_service.dart';
import 'package:family_hub/features/sos/application/sos_location_uploader.dart';
import 'package:family_hub/features/sos/domain/sos_alert.dart';

import 'sos_test_utils.dart';

/// Drives a [SosLocationUploader] in fake time with a manual clock.
class _Rig {
  _Rig({DateTime? lastSentAt}) {
    uploader = SosLocationUploader(
      alertId: 'a1',
      fixes: fixes.stream,
      upload: (id, point) async {
        uploads.add(point);
        await Future<void>.delayed(Duration.zero);
        final e = error;
        if (e != null) throw e;
        return alertFor(amit, id: id, lastLocation: point);
      },
      minInterval: const Duration(seconds: 5),
      now: clock.call,
      lastSentAt: lastSentAt,
      onUploaded: (alert, at) => uploadedAt.add(at),
      onStopped: stops.add,
      onUnavailable: unavailable.add,
    )..start();
  }

  final clock = TestClock();
  final fixes = StreamController<GeoFix>(sync: true);
  final List<GeoPoint> uploads = [];
  final List<DateTime> uploadedAt = [];
  final List<SosUploadStop> stops = [];
  final List<LocationPermissionState> unavailable = [];
  Object? error;
  late final SosLocationUploader uploader;

  void emit(double lat) => fixes.add(fixAt(clock.now, lat: lat));
}

void main() {
  testWidgets('first fix is sent at once, faster fixes are coalesced', (
    tester,
  ) async {
    final rig = _Rig();
    rig.emit(1);
    await settle(tester);
    expect(rig.uploads.map((p) => p.lat), [1]);
    expect(rig.uploadedAt, [rig.clock.now]);

    await advance(tester, rig.clock, const Duration(seconds: 1));
    rig.emit(2);
    await advance(tester, rig.clock, const Duration(seconds: 1));
    rig.emit(3);
    await settle(tester);
    expect(rig.uploads, hasLength(1), reason: 'within the 5 s interval');

    // 5 s after the first upload the newest pending fix goes out.
    await advance(tester, rig.clock, const Duration(seconds: 3));
    await settle(tester);
    expect(rig.uploads.map((p) => p.lat), [1, 3]);

    rig.uploader.stop();
    unawaited(rig.fixes.close());
  });

  testWidgets('lastSentAt delays the first upload', (tester) async {
    final rig = _Rig(lastSentAt: testNow);
    rig.emit(1);
    await settle(tester);
    expect(rig.uploads, isEmpty);
    await advance(tester, rig.clock, const Duration(seconds: 5));
    await settle(tester);
    expect(rig.uploads, hasLength(1));
    rig.uploader.stop();
  });

  testWidgets('a transient failure is retried after the interval', (
    tester,
  ) async {
    final rig = _Rig()..error = networkError;
    rig.emit(1);
    await settle(tester);
    expect(rig.uploads, hasLength(1));
    expect(rig.uploadedAt, isEmpty);
    expect(rig.stops, isEmpty);

    rig.error = null;
    await advance(tester, rig.clock, const Duration(seconds: 5));
    await settle(tester);
    expect(rig.uploads.map((p) => p.lat), [1, 1], reason: 'same fix again');
    expect(rig.uploadedAt, hasLength(1));
    rig.uploader.stop();
  });

  testWidgets('SOS_NOT_ACTIVE stops uploads and the location stream', (
    tester,
  ) async {
    final rig = _Rig()..error = notActiveError;
    rig.emit(1);
    await settle(tester);
    expect(rig.stops, [SosUploadStop.alertEnded]);
    expect(rig.uploader.isStopped, isTrue);
    expect(rig.fixes.hasListener, isFalse, reason: 'tracking cancelled');

    rig.fixes.add(fixAt(rig.clock.now));
    await advance(tester, rig.clock, const Duration(seconds: 10));
    expect(rig.uploads, hasLength(1));
  });

  testWidgets('LOCATION_SHARING_DISABLED reports sharingDisabled', (
    tester,
  ) async {
    final rig = _Rig()
      ..error = const ApiException(
        code: ApiErrorCode.locationSharingDisabled,
        statusCode: 403,
      );
    rig.emit(1);
    await settle(tester);
    expect(rig.stops, [SosUploadStop.sharingDisabled]);
  });

  testWidgets('stream errors are reported, the stream keeps running', (
    tester,
  ) async {
    final rig = _Rig();
    rig.fixes.addError(
      const LocationUnavailableException(
        LocationPermissionState.serviceDisabled,
      ),
    );
    await settle(tester);
    expect(rig.unavailable, [LocationPermissionState.serviceDisabled]);
    rig.emit(4);
    await settle(tester);
    expect(rig.uploads.map((p) => p.lat), [4]);

    unawaited(rig.fixes.close());
    await settle(tester);
    expect(rig.stops, [SosUploadStop.streamEnded]);
  });

  testWidgets('stop() is silent and idempotent', (tester) async {
    final rig = _Rig();
    rig.uploader.stop();
    rig.uploader.stop();
    rig.fixes.add(fixAt(rig.clock.now));
    await settle(tester);
    expect(rig.uploads, isEmpty);
    expect(rig.stops, isEmpty);
  });
}
