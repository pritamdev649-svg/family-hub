import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import 'package:family_hub/core/config/app_config.dart';
import 'package:family_hub/shared/models/geo_point.dart';

/// Result of a location permission check / request.
enum LocationPermissionState {
  /// Location may be read (while-in-use or always).
  granted,

  /// Not granted yet (or the user dismissed the prompt) - asking again is OK.
  denied,

  /// The OS will no longer show the prompt - only the system settings can
  /// grant access now (see [LocationService.openSettings]).
  deniedForever,

  /// The device-wide location switch (GPS / Location services) is off.
  serviceDisabled,
}

extension LocationPermissionStateX on LocationPermissionState {
  bool get isGranted => this == LocationPermissionState.granted;

  /// Whether the user has to leave the app to fix it (settings screen).
  bool get needsSettings =>
      this == LocationPermissionState.deniedForever ||
      this == LocationPermissionState.serviceDisabled;
}

/// One location fix, independent of the geolocator plugin types.
@immutable
class GeoFix {
  const GeoFix({
    required this.lat,
    required this.lng,
    required this.at,
    this.accuracy,
    this.isLastKnown = false,
  });

  /// Converts a plugin [Position]. Returns `null` for coordinates that are
  /// not usable (NaN, out of range) so callers never send junk to the API.
  static GeoFix? fromPosition(Position p, {bool isLastKnown = false}) {
    final lat = p.latitude;
    final lng = p.longitude;
    if (!lat.isFinite || !lng.isFinite || lat.abs() > 90 || lng.abs() > 180) {
      return null;
    }
    final acc = p.accuracy;
    return GeoFix(
      lat: lat,
      lng: lng,
      // iOS reports a negative accuracy for invalid fixes and Android omits
      // it (0.0) when unknown - both mean "no accuracy information".
      accuracy: acc.isFinite && acc > 0 ? acc : null,
      at: p.timestamp.toUtc(),
      isLastKnown: isLastKnown,
    );
  }

  final double lat;
  final double lng;

  /// Horizontal accuracy radius in metres, `null` when unknown.
  final double? accuracy;

  /// When the fix was measured (UTC).
  final DateTime at;

  /// `true` when this is the OS-cached last known position (fallback used
  /// when a fresh fix could not be obtained in time). It may be stale.
  final bool isLastKnown;

  /// Body for `PUT /me/location` and `POST /sos/:id/location`
  /// (`{ lat, lng, accuracy? }`), also usable as the SOS `location` object.
  Map<String, dynamic> toJson() => {
    'lat': lat,
    'lng': lng,
    if (accuracy != null) 'accuracy': accuracy,
  };

  /// As the shared domain type (e.g. to show the fix on an SOS card before
  /// the server echoes it back).
  GeoPoint toGeoPoint() =>
      GeoPoint(lat: lat, lng: lng, accuracy: accuracy, recordedAt: at);

  @override
  bool operator ==(Object other) =>
      other is GeoFix &&
      other.lat == lat &&
      other.lng == lng &&
      other.accuracy == accuracy &&
      other.at == at &&
      other.isLastKnown == isLastKnown;

  @override
  int get hashCode => Object.hash(lat, lng, accuracy, at, isLastKnown);

  @override
  String toString() =>
      'GeoFix($lat, $lng, ±${accuracy?.toStringAsFixed(1) ?? '?'}m, $at'
      '${isLastKnown ? ', lastKnown' : ''})';
}

/// Error emitted by [LocationService.track] when location cannot be read.
class LocationUnavailableException implements Exception {
  const LocationUnavailableException(this.reason, [this.cause]);

  final LocationPermissionState reason;
  final Object? cause;

  @override
  String toString() => 'LocationUnavailableException($reason, $cause)';
}

/// Thin seam over the static [Geolocator] API so the service is testable.
class LocationPlatform {
  const LocationPlatform();

  Future<bool> isServiceEnabled() => Geolocator.isLocationServiceEnabled();
  Future<LocationPermission> checkPermission() => Geolocator.checkPermission();
  Future<LocationPermission> requestPermission() =>
      Geolocator.requestPermission();
  Future<Position> currentPosition(LocationSettings settings) =>
      Geolocator.getCurrentPosition(locationSettings: settings);
  Future<Position?> lastKnownPosition() => Geolocator.getLastKnownPosition();
  Stream<Position> positionStream(LocationSettings settings) =>
      Geolocator.getPositionStream(locationSettings: settings);
  Future<bool> openAppSettings() => Geolocator.openAppSettings();
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  /// Web has no last-known-position API and no foreground service.
  bool get isWeb => kIsWeb;
  TargetPlatform get platform => defaultTargetPlatform;
}

/// Device location: permission flow, one-shot fixes and live tracking
/// (used by SOS and the "always share" location mode).
///
/// Privacy: this service never uploads anything itself - callers decide what
/// to send, based on the member's `locationSharing` mode.
class LocationService {
  LocationService({
    LocationPlatform platform = const LocationPlatform(),
    this.fixTimeout = const Duration(seconds: 12),
    this.trackingDistanceFilterMeters = 5,
    this.trackingInterval = AppConfig.sosLocationInterval,
  }) : _platform = platform;

  final LocationPlatform _platform;

  /// Max wait for a fresh fix in [currentFix] before falling back to the
  /// last known position.
  final Duration fixTimeout;

  /// Minimum movement (metres) between two [track] updates. Small, so a
  /// person walking is followed closely, but GPS jitter while standing
  /// still does not flood the API.
  final int trackingDistanceFilterMeters;

  /// Desired interval between Android tracking updates.
  final Duration trackingInterval;

  Future<LocationPermissionState>? _pendingRequest;

  /// Current state without showing any system prompt.
  Future<LocationPermissionState> checkPermission() async {
    try {
      if (!await _platform.isServiceEnabled()) {
        return LocationPermissionState.serviceDisabled;
      }
      return _map(await _platform.checkPermission());
    } catch (e) {
      _log('checkPermission failed: $e');
      return LocationPermissionState.denied;
    }
  }

  /// Checks and, when needed and still possible, requests location
  /// permission. Concurrent calls share one system prompt.
  ///
  /// [background]: the caller wants to keep tracking after the app goes to
  /// the background (SOS). While-in-use permission is sufficient for that on
  /// both platforms because tracking is always started from the foreground:
  /// Android keeps it alive with a `location` foreground service (no
  /// ACCESS_BACKGROUND_LOCATION needed, which also keeps Play review simple)
  /// and iOS continues with `allowsBackgroundLocationUpdates` + the blue
  /// status-bar indicator. So the flag never forces an "Always" prompt - a
  /// privacy-by-default choice.
  Future<LocationPermissionState> ensurePermission({bool background = false}) {
    return _pendingRequest ??= _ensurePermission(
      background: background,
    ).whenComplete(() => _pendingRequest = null);
  }

  Future<LocationPermissionState> _ensurePermission({
    required bool background,
  }) async {
    try {
      if (!await _platform.isServiceEnabled()) {
        return LocationPermissionState.serviceDisabled;
      }
      var permission = await _platform.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.unableToDetermine) {
        permission = await _platform.requestPermission();
      }
      return _map(permission);
    } on PermissionDefinitionsNotFoundException catch (e) {
      // Misconfigured Info.plist / AndroidManifest - a build problem.
      assert(false, 'Location permission definitions missing: $e');
      _log('permission definitions missing: $e');
      return LocationPermissionState.denied;
    } on PermissionRequestInProgressException catch (e) {
      _log('permission request already running: $e');
      return LocationPermissionState.denied;
    } catch (e) {
      _log('ensurePermission failed: $e');
      return LocationPermissionState.denied;
    }
  }

  /// A single fix. Never prompts for permission (call [ensurePermission]
  /// first) and never throws: returns `null` when location is unavailable.
  ///
  /// Waits up to [timeout] (default [fixTimeout]) for a fresh fix, then
  /// falls back to the OS last known position (flagged
  /// [GeoFix.isLastKnown]).
  Future<GeoFix?> currentFix({Duration? timeout}) async {
    final state = await checkPermission();
    if (state == LocationPermissionState.denied ||
        state == LocationPermissionState.deniedForever) {
      return null;
    }
    if (state == LocationPermissionState.granted) {
      try {
        final position = await _platform
            .currentPosition(
              const LocationSettings(accuracy: LocationAccuracy.high),
            )
            .timeout(timeout ?? fixTimeout);
        final fix = GeoFix.fromPosition(position);
        if (fix != null) return fix;
      } on TimeoutException {
        _log('currentFix timed out, trying last known position');
      } catch (e) {
        _log('currentFix failed: $e');
      }
    }
    // Service disabled or no fresh fix: the cached position may still help
    // (e.g. SOS sent from indoors).
    return _lastKnown();
  }

  Future<GeoFix?> _lastKnown() async {
    if (_platform.isWeb) return null;
    try {
      final position = await _platform.lastKnownPosition();
      return position == null
          ? null
          : GeoFix.fromPosition(position, isLastKnown: true);
    } catch (e) {
      _log('lastKnownPosition failed: $e');
      return null;
    }
  }

  /// Live location updates until the subscription is cancelled.
  ///
  /// Never prompts: when permission is missing the stream emits a single
  /// [LocationUnavailableException] and closes. Plugin errors while
  /// tracking (e.g. the user switches GPS off) are forwarded as
  /// [LocationUnavailableException] without closing the stream, so tracking
  /// resumes when GPS comes back.
  ///
  /// Android runs a foreground service showing [notificationTitle] /
  /// [notificationText] (localized by the caller) in channel [channelName];
  /// iOS shows the blue background-location indicator. Both make the
  /// sharing visible to the member, as the product requires.
  Stream<GeoFix> track({
    required String notificationTitle,
    required String notificationText,
    String? channelName,
  }) {
    StreamSubscription<Position>? subscription;
    var cancelled = false;
    late final StreamController<GeoFix> controller;

    Future<void> start() async {
      final state = await checkPermission();
      if (cancelled) return;
      if (!state.isGranted) {
        controller.addError(LocationUnavailableException(state));
        await controller.close();
        return;
      }
      final settings = _trackingSettings(
        notificationTitle: notificationTitle,
        notificationText: notificationText,
        channelName: channelName,
      );
      try {
        subscription = _platform
            .positionStream(settings)
            .listen(
              (position) {
                final fix = GeoFix.fromPosition(position);
                if (fix != null && !controller.isClosed) controller.add(fix);
              },
              onError: (Object error, StackTrace stackTrace) {
                if (controller.isClosed) return;
                controller.addError(_mapError(error), stackTrace);
              },
              onDone: () {
                if (!controller.isClosed) controller.close();
              },
            );
        if (controller.isPaused) subscription?.pause();
      } catch (e, st) {
        controller.addError(_mapError(e), st);
        await controller.close();
      }
    }

    controller = StreamController<GeoFix>(
      onListen: () => unawaited(start()),
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () async {
        cancelled = true;
        final sub = subscription;
        subscription = null;
        await sub?.cancel();
      },
    );
    return controller.stream;
  }

  /// Opens the screen that can fix the current problem: the device location
  /// settings when GPS is off, otherwise the app's permission settings.
  Future<bool> openSettings() async {
    try {
      if (!_platform.isWeb && !await _platform.isServiceEnabled()) {
        return await _platform.openLocationSettings();
      }
      return await _platform.openAppSettings();
    } catch (e) {
      _log('openSettings failed: $e');
      return false;
    }
  }

  LocationSettings _trackingSettings({
    required String notificationTitle,
    required String notificationText,
    String? channelName,
  }) {
    if (_platform.isWeb) {
      return LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: trackingDistanceFilterMeters,
      );
    }
    switch (_platform.platform) {
      case TargetPlatform.android:
        return AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: trackingDistanceFilterMeters,
          intervalDuration: trackingInterval,
          foregroundNotificationConfig: ForegroundNotificationConfig(
            notificationTitle: notificationTitle,
            notificationText: notificationText,
            notificationChannelName: channelName ?? notificationTitle,
            notificationIcon: const AndroidResource(
              name: 'ic_stat_notification',
              defType: 'drawable',
            ),
            enableWakeLock: true,
            setOngoing: true,
          ),
        );
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return AppleSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: trackingDistanceFilterMeters,
          activityType: ActivityType.other,
          pauseLocationUpdatesAutomatically: false,
          allowBackgroundLocationUpdates: true,
          showBackgroundLocationIndicator: true,
        );
      default:
        return LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: trackingDistanceFilterMeters,
        );
    }
  }

  static LocationUnavailableException _mapError(Object error) {
    if (error is LocationUnavailableException) return error;
    if (error is LocationServiceDisabledException) {
      return LocationUnavailableException(
        LocationPermissionState.serviceDisabled,
        error,
      );
    }
    return LocationUnavailableException(LocationPermissionState.denied, error);
  }

  static LocationPermissionState _map(LocationPermission permission) {
    switch (permission) {
      case LocationPermission.always:
      case LocationPermission.whileInUse:
        return LocationPermissionState.granted;
      case LocationPermission.deniedForever:
        return LocationPermissionState.deniedForever;
      case LocationPermission.denied:
      case LocationPermission.unableToDetermine:
        return LocationPermissionState.denied;
    }
  }

  static void _log(String message) {
    if (kDebugMode) debugPrint('[LocationService] $message');
  }
}

final locationServiceProvider = Provider<LocationService>(
  (ref) => LocationService(),
);
