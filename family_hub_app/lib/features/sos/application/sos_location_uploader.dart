import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:family_hub/core/network/api_exception.dart';
import 'package:family_hub/core/services/location_service.dart';
import 'package:family_hub/features/sos/domain/sos_alert.dart';

/// Why live location uploads stopped by themselves.
enum SosUploadStop {
  /// The alert is no longer active (`409 SOS_NOT_ACTIVE`) or gone (`404`).
  alertEnded,

  /// The member is no longer in the family (`403 NO_FAMILY`; the removal
  /// resolved the alert).
  removedFromFamily,

  /// The member's sharing mode is `never` now
  /// (`403 LOCATION_SHARING_DISABLED`).
  sharingDisabled,

  /// The location stream closed (e.g. permission missing when it started).
  streamEnded,
}

/// Uploads the fixes of a live location stream to `POST /sos/:id/location`,
/// at most once per [minInterval]:
///
/// * Fixes arriving faster are coalesced: the newest one is sent when the
///   interval has passed (so the last position is always delivered, also
///   when the person stops moving and no new fix arrives).
/// * Uploads never overlap. A transient failure (offline, timeout, 5xx,
///   429, an expired token being refreshed) keeps the fix and retries it
///   after [minInterval], unless a newer fix arrived meanwhile. A fix the
///   server rejects (e.g. `422`) is dropped; the next fix is sent as usual.
/// * `SOS_NOT_ACTIVE`, `NOT_FOUND`, `NO_FAMILY` and
///   `LOCATION_SHARING_DISABLED` stop the uploader and report
///   [onStopped] once.
/// * Stream errors ([LocationUnavailableException], e.g. GPS switched off)
///   are reported via [onUnavailable]; the stream keeps running so tracking
///   resumes when location comes back.
/// * [lastSentAt] (e.g. the fix sent with `POST /sos`) delays the first
///   upload accordingly.
class SosLocationUploader {
  SosLocationUploader({
    required this.alertId,
    required Stream<GeoFix> fixes,
    required Future<SosAlert> Function(String alertId, GeoPoint point) upload,
    required this.minInterval,
    required DateTime Function() now,
    required this.onUploaded,
    required this.onStopped,
    this.onUnavailable,
    DateTime? lastSentAt,
  }) : _fixes = fixes,
       _upload = upload,
       _now = now,
       _lastAttemptAt = lastSentAt;

  final String alertId;
  final Stream<GeoFix> _fixes;
  final Future<SosAlert> Function(String alertId, GeoPoint point) _upload;
  final DateTime Function() _now;
  final Duration minInterval;

  /// A fix reached the server ([at] = local time of the upload).
  final void Function(SosAlert alert, DateTime at) onUploaded;

  /// Uploads stopped by themselves (not called for [stop]).
  final void Function(SosUploadStop reason) onStopped;

  /// The stream reported that location is unavailable right now.
  final void Function(LocationPermissionState reason)? onUnavailable;

  StreamSubscription<GeoFix>? _subscription;
  Timer? _timer;
  GeoFix? _pending;
  DateTime? _lastAttemptAt;
  bool _inFlight = false;
  bool _stopped = false;

  bool get isStopped => _stopped;

  /// Starts listening to the location stream. Call once.
  void start() {
    if (_stopped || _subscription != null) return;
    _subscription = _fixes.listen(
      _onFix,
      onError: (Object error, StackTrace stack) {
        if (_stopped) return;
        final reason = error is LocationUnavailableException
            ? error.reason
            : LocationPermissionState.denied;
        onUnavailable?.call(reason);
      },
      onDone: () {
        if (_stopped) return;
        _halt();
        onStopped(SosUploadStop.streamEnded);
      },
    );
  }

  /// Stops uploads and the location stream (the foreground-service
  /// notification disappears). Idempotent; takes effect immediately (the
  /// stream is cancelled in the background).
  void stop() {
    if (_stopped) return;
    _halt();
  }

  void _onFix(GeoFix fix) {
    if (_stopped) return;
    _pending = fix;
    _pump();
  }

  /// Uploads the pending fix now or schedules it for when [minInterval]
  /// has passed since the previous attempt.
  void _pump() {
    if (_stopped || _inFlight || _pending == null) return;
    final last = _lastAttemptAt;
    if (last != null) {
      final elapsed = _now().difference(last);
      // A clock that jumped backwards counts as due.
      if (!elapsed.isNegative && elapsed < minInterval) {
        _timer ??= Timer(minInterval - elapsed, () {
          _timer = null;
          _pump();
        });
        return;
      }
    }
    _timer?.cancel();
    _timer = null;
    unawaited(_send());
  }

  Future<void> _send() async {
    final fix = _pending;
    if (fix == null || _stopped) return;
    _pending = null;
    _inFlight = true;
    _lastAttemptAt = _now();
    try {
      final alert = await _upload(alertId, fix.toGeoPoint());
      if (_stopped) return;
      onUploaded(alert, _now());
    } on ApiException catch (e) {
      if (_stopped) return;
      final reason = _stopReason(e);
      if (reason != null) {
        _halt();
        onStopped(reason);
        return;
      }
      if (_isRetryable(e)) {
        _retryLater(fix, e);
      } else if (kDebugMode) {
        debugPrint('SosLocationUploader: fix rejected ($e)');
      }
    } catch (e) {
      if (_stopped) return;
      _retryLater(fix, e);
    } finally {
      _inFlight = false;
      if (!_stopped) _pump();
    }
  }

  void _retryLater(GeoFix fix, Object error) {
    // Keep the failed fix unless a newer one arrived meanwhile.
    _pending ??= fix;
    if (kDebugMode) debugPrint('SosLocationUploader: upload failed ($error)');
  }

  static SosUploadStop? _stopReason(ApiException e) {
    switch (e.code) {
      case ApiErrorCode.sosNotActive:
      case ApiErrorCode.notFound:
        return SosUploadStop.alertEnded;
      case ApiErrorCode.noFamily:
        return SosUploadStop.removedFromFamily;
      case ApiErrorCode.locationSharingDisabled:
        return SosUploadStop.sharingDisabled;
    }
    return null;
  }

  /// Failures worth sending the same fix again for. Anything else the
  /// server answered (`422`, `400`, `403 FORBIDDEN` …) would fail the same
  /// way again.
  static bool _isRetryable(ApiException e) =>
      e.isNetwork ||
      e.isServer ||
      e.isUnauthorized ||
      e.code == ApiErrorCode.tooManyRequests ||
      e.code == ApiErrorCode.unknown ||
      e.statusCode == null;

  void _halt() {
    _stopped = true;
    _timer?.cancel();
    _timer = null;
    _pending = null;
    final sub = _subscription;
    _subscription = null;
    // Not awaited: callers must never wait for the platform to release the
    // location stream (the foreground service stops shortly after).
    if (sub != null) {
      unawaited(
        sub.cancel().catchError((Object e) {
          debugPrint('SosLocationUploader: cancel failed ($e)');
        }),
      );
    }
  }
}
