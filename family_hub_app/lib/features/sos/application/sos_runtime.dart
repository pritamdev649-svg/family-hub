import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/network/api_exception.dart';
import 'package:family_hub/core/services/services_l10n.dart';
import 'package:family_hub/core/settings/settings_controller.dart';
import 'package:family_hub/shared/providers/shared_providers.dart';

/// Current time for every SOS decision (countdown, expiry, "updated X ago").
/// Overridden in tests.
final sosClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Re-reads the session (`GET /auth/me`) in the background when an SOS call
/// shows that the local session no longer matches the server:
///
/// * `403 NO_FAMILY` — the member was removed from the family (the router
///   then leaves the family screens);
/// * `403 FORBIDDEN` — e.g. demoted from admin on another phone while the
///   alert screen offered "Mark as helped";
/// * a sharing mode that differs from the server's (an alert sent with
///   "share during SOS" came back without location).
///
/// Concurrent calls share one refresh; never throws. Call it with
/// [SosSessionResync.after] for an error.
final sosSessionResyncProvider = Provider<SosSessionResync>(
  (ref) => SosSessionResync(
    () => ref.read(sessionControllerProvider.notifier).refreshMe(),
  ),
);

class SosSessionResync {
  SosSessionResync(this._refresh);

  final Future<void> Function() _refresh;
  bool _running = false;

  /// Starts a refresh unless one is running.
  void call() {
    if (_running) return;
    _running = true;
    unawaited(
      Future<void>.sync(_refresh)
          .catchError((Object e) {
            debugPrint('SOS: session refresh failed ($e)');
          })
          .whenComplete(() => _running = false),
    );
  }

  /// Refreshes the session when [error] shows it is out of date
  /// (`NO_FAMILY`, `FORBIDDEN`). Returns whether it did.
  bool after(Object error) {
    if (error is! ApiException) return false;
    if (error.code != ApiErrorCode.noFamily && !error.isForbidden) return false;
    call();
    return true;
  }
}

/// Whether the app is in the foreground (`resumed` or `inactive`, e.g. while
/// the notification shade is open). SOS polling pauses while the app is in
/// the background; live location tracking does not (it runs in a foreground
/// service).
final sosAppForegroundProvider = NotifierProvider<SosAppForeground, bool>(
  SosAppForeground.new,
);

class SosAppForeground extends Notifier<bool> {
  @override
  bool build() {
    final listener = AppLifecycleListener(
      onStateChange: (s) {
        final foreground = isForeground(s);
        if (ref.mounted && foreground != state) state = foreground;
      },
    );
    ref.onDispose(listener.dispose);
    return isForeground(WidgetsBinding.instance.lifecycleState);
  }

  /// `null` (not reported yet, e.g. at start-up) counts as foreground.
  static bool isForeground(AppLifecycleState? s) =>
      s == null ||
      s == AppLifecycleState.resumed ||
      s == AppLifecycleState.inactive;
}

/// Localized texts of the ongoing notification while SOS live location is
/// shared (Android foreground service). Read when tracking starts.
typedef SosTrackingTexts = ({String title, String text, String channel});

final sosTrackingTextsProvider = Provider<SosTrackingTexts>((ref) {
  final l10n = servicesL10n(ref.watch(resolvedLocaleProvider));
  return (
    title: l10n.servicesLocationSharingTitle,
    text: l10n.servicesLocationSharingText,
    channel: l10n.servicesLocationChannelName,
  );
});

/// Runs [poll] every [interval] while [enabled], never overlapping, and
/// never throwing (errors are the poll function's business). The next poll
/// is scheduled after the previous one finished, so a slow network never
/// piles up requests.
class SosPoller {
  SosPoller({required this.interval, required this.poll});

  final Duration interval;
  final Future<void> Function() poll;

  Timer? _timer;
  bool _enabled = false;
  bool _running = false;
  bool _disposed = false;

  bool get isEnabled => _enabled;

  /// Starts / stops the periodic polls.
  set enabled(bool value) {
    if (_disposed || value == _enabled) return;
    _enabled = value;
    if (value) {
      _schedule();
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  /// Polls right away (unless a poll is running) and restarts the interval.
  Future<void> pollNow() async {
    if (_disposed) return;
    _timer?.cancel();
    _timer = null;
    await _run();
    if (_enabled) _schedule();
  }

  void dispose() {
    _disposed = true;
    _enabled = false;
    _timer?.cancel();
    _timer = null;
  }

  void _schedule() {
    _timer?.cancel();
    if (!_enabled || _disposed) return;
    _timer = Timer(interval, () async {
      _timer = null;
      if (!_enabled || _disposed) return;
      await _run();
      if (_enabled && _timer == null) _schedule();
    });
  }

  Future<void> _run() async {
    if (_running || _disposed) return;
    _running = true;
    try {
      await poll();
    } catch (e) {
      debugPrint('SosPoller: poll failed ($e)');
    } finally {
      _running = false;
    }
  }
}
