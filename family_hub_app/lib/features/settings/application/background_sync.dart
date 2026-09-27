import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/services/location_service.dart';
import 'package:family_hub/features/settings/application/location_upload_clock.dart';
import 'package:family_hub/features/settings/application/settings_actions.dart';
import 'package:family_hub/shared/session/session_controller.dart';

/// Keeps the signed-in session and the "Always share" location fresh while
/// the app is used:
///
/// * On every app resume the session is re-read (`GET /auth/me`, at most
///   once per [sessionRefreshInterval]) so changes made by others — role,
///   removal from the family, family settings, a sharing mode changed on
///   another phone — reach this phone without a restart.
/// * When the current member's `locationSharing` is `always`, a fix is
///   uploaded (`PUT /me/location`) on app start and on every app resume, at
///   most once per [minInterval]. Never prompts for permission (a missing
///   permission is simply skipped — the location screen explains it), never
///   tracks in the background and never shares an old cached position
///   ([isShareableFix]).
/// * Errors are silently ignored (logged in debug builds). A
///   `LOCATION_SHARING_DISABLED` / `NO_FAMILY` answer resyncs the session.
class BackgroundLocationSync {
  BackgroundLocationSync(this._ref)
    // The session was restored (or signed in) right before the shell was
    // built, so the first resume does not need to re-read it again at once.
    : _sessionCheckedAt = _ref.read(settingsClockProvider)();

  /// Minimum time between two automatic location uploads.
  static const minInterval = Duration(minutes: 10);

  /// Minimum time between two session refreshes triggered by app resumes.
  static const sessionRefreshInterval = Duration(minutes: 2);

  final Ref _ref;
  Future<bool>? _running;
  Future<void>? _resuming;
  DateTime? _sessionCheckedAt;

  DateTime _now() => _ref.read(settingsClockProvider)();

  /// The app came back to the foreground: refreshes the session if due,
  /// then uploads the location if due. Concurrent calls share one run;
  /// never throws.
  Future<void> onResume() => _resuming ??= _onResume().whenComplete(() {
    _resuming = null;
  });

  Future<void> _onResume() async {
    await refreshSessionIfDue();
    if (_ref.mounted) await syncIfDue();
  }

  /// Re-reads the session unless that happened less than
  /// [sessionRefreshInterval] ago. Returns whether it was refreshed; never
  /// throws (a `401` signs out through the session controller).
  Future<bool> refreshSessionIfDue() async {
    final now = _now();
    final last = _sessionCheckedAt;
    if (last != null) {
      final elapsed = now.difference(last);
      // A clock that jumped backwards counts as due.
      if (!elapsed.isNegative && elapsed < sessionRefreshInterval) {
        return false;
      }
    }
    // Throttle failures too (offline): no request storm on every resume.
    _sessionCheckedAt = now;
    try {
      await _ref.read(sessionControllerProvider.notifier).refreshMe();
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[BackgroundSync] session refresh failed: $e');
      return false;
    }
  }

  /// Uploads a fix if due. Concurrent calls share one run. Returns whether a
  /// fix was uploaded; never throws.
  Future<bool> syncIfDue() => _running ??= _sync().whenComplete(() {
    _running = null;
  });

  Future<bool> _sync() async {
    try {
      final member = _ref.read(currentMemberProvider);
      if (member == null || !member.locationSharing.sharesAlways) return false;
      final clock = _ref.read(locationUploadClockProvider.notifier);
      if (!clock.isDue(minInterval)) return false;

      final location = _ref.read(locationServiceProvider);
      final permission = await location.checkPermission();
      if (!permission.isGranted) return false;
      final fix = await location.currentFix();
      if (fix == null || !_ref.mounted || !isShareableFix(fix, _now())) {
        return false;
      }

      // The member may have switched modes or signed out meanwhile.
      final now = _ref.read(currentMemberProvider);
      if (now == null ||
          now.id != member.id ||
          !now.locationSharing.sharesAlways) {
        return false;
      }
      await _ref
          .read(meRepositoryProvider)
          .updateLocation(lat: fix.lat, lng: fix.lng, accuracy: fix.accuracy);
      if (_ref.mounted) {
        _ref.read(locationUploadClockProvider.notifier).record();
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[BackgroundSync] location upload skipped: $e');
      }
      // e.g. the mode was changed on another phone → show the real one.
      if (_ref.mounted) _ref.read(settingsActionsProvider).resyncIfStale(e);
      return false;
    }
  }
}

/// Watched by `HomeShell`, so it lives exactly as long as the signed-in app
/// frame. Uploads the location once on start (opening the app counts as a
/// resume) and runs [BackgroundLocationSync.onResume] on every
/// `AppLifecycleState.resumed`.
final backgroundSyncProvider = Provider.autoDispose<BackgroundLocationSync>((
  ref,
) {
  final sync = BackgroundLocationSync(ref);
  final listener = AppLifecycleListener(
    onResume: () => unawaited(sync.onResume()),
  );
  ref.onDispose(listener.dispose);
  // At the end of the frame that built the shell, so start-up rendering is
  // not delayed (and no timer is left behind).
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (ref.mounted) unawaited(sync.syncIfDue());
  });
  return sync;
});
