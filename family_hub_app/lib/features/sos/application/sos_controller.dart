import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/config/app_config.dart';
import 'package:family_hub/core/network/api_exception.dart';
import 'package:family_hub/core/services/location_service.dart';
import 'package:family_hub/features/sos/application/sos_location_uploader.dart';
import 'package:family_hub/features/sos/application/sos_providers.dart';
import 'package:family_hub/features/sos/application/sos_runtime.dart';
import 'package:family_hub/features/sos/data/sos_repository.dart';
import 'package:family_hub/shared/data/me_repository.dart';
import 'package:family_hub/shared/models/member.dart';
import 'package:family_hub/shared/providers/shared_providers.dart';

export 'package:family_hub/features/sos/domain/sos_alert.dart';

/// Where the outgoing SOS flow is: `idle → countdown → sending → active →
/// idle`.
enum SosPhase { idle, countdown, sending, active }

/// Live location of the member's own active alert.
enum SosSharing {
  /// No live location for this alert (sharing mode `never`).
  off,

  /// Live location is being shared (the foreground-service notification /
  /// iOS indicator is visible).
  live,

  /// Location cannot be read right now (permission missing, GPS off) — see
  /// [SosState.permission].
  unavailable,
}

/// State of the member's own (outgoing) SOS.
@immutable
class SosState {
  const SosState({
    this.phase = SosPhase.idle,
    this.secondsLeft = 0,
    this.alert,
    this.sharing = SosSharing.off,
    this.permission,
    this.lastSentAt,
    this.resolving,
    this.sendError,
  });

  final SosPhase phase;

  /// Seconds left in the countdown (only in [SosPhase.countdown]).
  final int secondsLeft;

  /// The active alert (only in [SosPhase.active]).
  final SosAlert? alert;
  final SosSharing sharing;

  /// Why location is unavailable ([SosSharing.unavailable]) or was not sent.
  final LocationPermissionState? permission;

  /// When a location last reached the server (local time).
  final DateTime? lastSentAt;

  /// A resolve request is running with this resolution.
  final SosResolution? resolving;

  /// The last send attempt failed (only in [SosPhase.idle]).
  final Object? sendError;

  bool get isIdle => phase == SosPhase.idle;
  bool get isCountingDown => phase == SosPhase.countdown;
  bool get isSending => phase == SosPhase.sending;
  bool get isActive => phase == SosPhase.active && alert != null;
  bool get isResolving => resolving != null;

  SosState copyWith({
    SosPhase? phase,
    int? secondsLeft,
    ValueGetter<SosAlert?>? alert,
    SosSharing? sharing,
    ValueGetter<LocationPermissionState?>? permission,
    ValueGetter<DateTime?>? lastSentAt,
    ValueGetter<SosResolution?>? resolving,
    ValueGetter<Object?>? sendError,
  }) {
    return SosState(
      phase: phase ?? this.phase,
      secondsLeft: secondsLeft ?? this.secondsLeft,
      alert: alert != null ? alert() : this.alert,
      sharing: sharing ?? this.sharing,
      permission: permission != null ? permission() : this.permission,
      lastSentAt: lastSentAt != null ? lastSentAt() : this.lastSentAt,
      resolving: resolving != null ? resolving() : this.resolving,
      sendError: sendError != null ? sendError() : this.sendError,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SosState &&
          other.phase == phase &&
          other.secondsLeft == secondsLeft &&
          other.alert == alert &&
          other.sharing == sharing &&
          other.permission == permission &&
          other.lastSentAt == lastSentAt &&
          other.resolving == resolving &&
          other.sendError == sendError;

  @override
  int get hashCode => Object.hash(
    phase,
    secondsLeft,
    alert,
    sharing,
    permission,
    lastSentAt,
    resolving,
    sendError,
  );

  @override
  String toString() =>
      'SosState(${phase.name}, sharing: ${sharing.name}, alert: ${alert?.id})';
}

/// Answer of the "share your location?" dialog shown when the member's
/// sharing mode is `never`.
enum SosLocationChoice {
  /// Switch the sharing mode to "only during SOS" and send the location.
  shareDuringSos,

  /// Keep `never` and alert the family without location.
  sendWithout,
}

/// Shows the "share your location?" question; `null` = no answer (treated
/// as [SosLocationChoice.sendWithout] — an SOS is never dropped).
typedef SosLocationChoiceAsker = Future<SosLocationChoice?> Function();

enum SosSendResult { sent, cancelled, failed, ignored }

/// What the UI should tell the member about the location of a sent SOS.
enum SosLocationNote {
  /// The location was sent / is being shared.
  none,

  /// Sent without location: the sharing mode is `never`.
  sharingOff,

  /// Sent without location: permission missing or GPS off (see
  /// [SosSendOutcome.permission]).
  permissionMissing,

  /// Turning on "share during SOS" failed, so it was sent without location.
  sharingUpdateFailed,
}

/// Result of [SosController.start].
@immutable
class SosSendOutcome {
  const SosSendOutcome._(
    this.result, {
    this.alert,
    this.error,
    this.note = SosLocationNote.none,
    this.permission,
  });

  const SosSendOutcome.cancelled() : this._(SosSendResult.cancelled);

  /// Another flow is running / an alert is already active.
  const SosSendOutcome.ignored() : this._(SosSendResult.ignored);

  const SosSendOutcome.sent(
    SosAlert alert, {
    SosLocationNote note = SosLocationNote.none,
    LocationPermissionState? permission,
  }) : this._(
         SosSendResult.sent,
         alert: alert,
         note: note,
         permission: permission,
       );

  const SosSendOutcome.failed(Object error)
    : this._(SosSendResult.failed, error: error);

  final SosSendResult result;
  final SosAlert? alert;
  final Object? error;
  final SosLocationNote note;
  final LocationPermissionState? permission;

  @override
  String toString() => 'SosSendOutcome(${result.name}, ${note.name})';
}

/// The member's own SOS: countdown, sending, live location and "I am okay".
///
/// * [start] runs the cancellable countdown ([AppConfig.sosCountdownSeconds]),
///   then sends: a member whose sharing mode is `never` is asked whether to
///   share the location for this SOS (switches the mode to `sos_only`);
///   permission is requested (denied → sent without location, the outcome
///   says why); `POST /sos` is retried on transient failures (it is
///   idempotent on the server). Neither question can hold the SOS back: an
///   unanswered location question counts as "send without location" after
///   [locationChoiceTimeout], an unanswered permission prompt as "not
///   granted" after [permissionPromptTimeout] (tracking starts as soon as
///   it is granted later).
/// * While active, [LocationService.track] fixes are uploaded at most every
///   [AppConfig.sosLocationInterval]. Tracking stops at `expiresAt`, on
///   [resolve], on `409 SOS_NOT_ACTIVE` / `404` and when the alert
///   disappears from `GET /sos/active` (resolved by an admin / on another
///   phone — verified with `GET /sos/:id` first).
/// * On app start / resume the member's active alert from
///   [activeSosAlertsProvider] is adopted and tracking resumes (without a
///   permission prompt).
/// * Every change of the alert is announced with `markChanged({sos})`.
/// * Resets on logout / account switch (tracking stops).
class SosController extends Notifier<SosState> {
  /// How long sending waits for a first fix before alerting without one
  /// (live tracking delivers the location shortly after).
  static const firstFixTimeout = Duration(seconds: 5);

  /// An OS-cached position older than this is not sent as the SOS location.
  static const maxLastKnownFixAge = Duration(minutes: 10);

  /// Waits between `POST /sos` attempts on transient failures.
  static const sendRetryDelays = [Duration(seconds: 1), Duration(seconds: 2)];

  /// How long the "share your location?" question may stay unanswered
  /// before the SOS is sent without location (someone in danger may not be
  /// able to answer; privacy by default, so silence never means "share").
  static const locationChoiceTimeout = Duration(seconds: 10);

  /// How long sending waits for the system permission prompt before
  /// alerting without location.
  static const permissionPromptTimeout = Duration(seconds: 10);

  int _epoch = 0;
  Timer? _countdown;
  Completer<bool>? _countdownDone;
  Timer? _expiryTimer;
  SosLocationUploader? _uploader;
  bool _verifying = false;

  DateTime _now() => ref.read(sosClockProvider)();

  @override
  SosState build() {
    final epoch = ++_epoch;
    final userId = ref.watch(sessionUserIdProvider);
    ref.onDispose(_teardown);
    if (userId == null) return const SosState();

    ref.listen<AsyncValue<List<SosAlert>>>(
      activeSosAlertsProvider,
      (_, next) => _onActiveAlerts(epoch, next),
    );
    ref.listen<LocationSharingMode?>(
      currentMemberProvider.select((m) => m?.locationSharing),
      (previous, next) => _onSharingModeChanged(epoch, previous, next),
    );
    ref.listen<bool>(sosAppForegroundProvider, (previous, foreground) {
      if (foreground && previous == false) _onForeground(epoch);
    });
    // The list may already be loaded (the banner watched it first).
    scheduleMicrotask(() {
      if (_isCurrent(epoch)) {
        _onActiveAlerts(epoch, ref.read(activeSosAlertsProvider));
      }
    });
    return const SosState();
  }

  bool _isCurrent(int epoch) => ref.mounted && epoch == _epoch;

  bool _isCurrentAlert(int epoch, String alertId) =>
      _isCurrent(epoch) && state.isActive && state.alert?.id == alertId;

  // ── Countdown & send ─────────────────────────────────────────────────────

  /// Runs the countdown (skipped with [skipCountdown], e.g. "Try again"
  /// after a failed send) and sends the alert. Completes when the flow
  /// ends; never throws (failures are [SosSendResult.failed]).
  Future<SosSendOutcome> start({
    required SosLocationChoiceAsker askLocationChoice,
    bool skipCountdown = false,
  }) async {
    if (!state.isIdle) return const SosSendOutcome.ignored();
    if (ref.read(sessionUserIdProvider) == null) {
      return const SosSendOutcome.failed(
        ApiException(code: ApiErrorCode.unauthorized, statusCode: 401),
      );
    }
    final epoch = _epoch;
    if (!skipCountdown) {
      final proceed = await _runCountdown(epoch);
      if (!proceed || !_isCurrent(epoch)) {
        return const SosSendOutcome.cancelled();
      }
    }
    return _send(epoch, askLocationChoice);
  }

  /// Cancels a running countdown (nothing was sent).
  void cancelCountdown() {
    if (!state.isCountingDown) return;
    _stopCountdown(false);
    state = const SosState();
  }

  /// Hides the error of the last failed send.
  void clearSendError() {
    if (state.isIdle && state.sendError != null) state = const SosState();
  }

  Future<bool> _runCountdown(int epoch) {
    final done = _countdownDone = Completer<bool>();
    var left = AppConfig.sosCountdownSeconds;
    state = SosState(phase: SosPhase.countdown, secondsLeft: left);
    _countdown = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isCurrent(epoch)) {
        _stopCountdown(false);
        return;
      }
      left--;
      if (left <= 0) {
        _stopCountdown(true);
      } else {
        state = state.copyWith(secondsLeft: left);
      }
    });
    return done.future;
  }

  void _stopCountdown(bool proceed) {
    _countdown?.cancel();
    _countdown = null;
    final done = _countdownDone;
    _countdownDone = null;
    if (done != null && !done.isCompleted) done.complete(proceed);
  }

  Future<SosSendOutcome> _send(int epoch, SosLocationChoiceAsker ask) async {
    state = const SosState(phase: SosPhase.sending);
    final member = ref.read(currentMemberProvider);
    var mode = member?.locationSharing ?? LocationSharingMode.never;
    var note = SosLocationNote.none;
    LocationPermissionState? permission;

    if (!mode.sharesDuringSos) {
      SosLocationChoice? choice;
      try {
        // A nullable future of its own (`then<…?>`): the asker's may be a
        // `Future<SosLocationChoice>`, which cannot complete with `null`.
        choice = await ask()
            .then<SosLocationChoice?>((answer) => answer)
            .timeout(locationChoiceTimeout, onTimeout: () => null);
      } catch (e) {
        debugPrint('SosController: location question failed ($e)');
      }
      if (!_isCurrent(epoch)) return const SosSendOutcome.cancelled();
      if (choice == SosLocationChoice.shareDuringSos) {
        final enabled = await _enableSharingDuringSos(epoch);
        if (!_isCurrent(epoch)) return const SosSendOutcome.cancelled();
        if (enabled != null) {
          mode = enabled;
        } else {
          note = SosLocationNote.sharingUpdateFailed;
        }
      } else {
        note = SosLocationNote.sharingOff;
      }
    }

    GeoPoint? location;
    if (mode.sharesDuringSos) {
      final service = ref.read(locationServiceProvider);
      permission = await _requestPermission(epoch);
      if (!_isCurrent(epoch)) return const SosSendOutcome.cancelled();
      if (permission.isGranted) {
        final fix = await service.currentFix(timeout: firstFixTimeout);
        if (!_isCurrent(epoch)) return const SosSendOutcome.cancelled();
        if (fix != null && _isFreshEnough(fix)) location = fix.toGeoPoint();
      } else {
        note = SosLocationNote.permissionMissing;
      }
    }

    final SosAlert alert;
    try {
      alert = await _createWithRetry(epoch, location);
    } catch (e) {
      if (!_isCurrent(epoch)) return SosSendOutcome.failed(e);
      state = SosState(sendError: e);
      // Removed from the family meanwhile: the refreshed session leaves it.
      ref.read(sosSessionResyncProvider).after(e);
      return SosSendOutcome.failed(e);
    }
    if (!_isCurrent(epoch)) return const SosSendOutcome.ignored();

    markChanged(ref, {DataScope.sos});
    if (note == SosLocationNote.none && !alert.locationShared) {
      note = SosLocationNote.sharingOff; // the server's mode is `never`
    }
    if (mode.sharesDuringSos && !alert.locationShared) {
      // The local session thinks the location is shared, the server does
      // not: show the real mode.
      ref.read(sosSessionResyncProvider)();
    }
    final sentAt = location != null && alert.locationShared ? _now() : null;
    _activate(epoch, alert, permission: permission, lastSentAt: sentAt);
    return SosSendOutcome.sent(alert, note: note, permission: permission);
  }

  /// `PATCH /me { locationSharing: sos_only }` → the new mode, or `null`
  /// when it failed (the SOS is then sent without location).
  Future<LocationSharingMode?> _enableSharingDuringSos(int epoch) async {
    try {
      final res = await ref
          .read(meRepositoryProvider)
          .updateMe(MePatch(locationSharing: LocationSharingMode.sosOnly));
      if (!_isCurrent(epoch)) return null;
      await ref
          .read(sessionControllerProvider.notifier)
          .applyMe(res.user, res.member);
      if (_isCurrent(epoch)) markChanged(ref, {DataScope.members});
      return res.member?.locationSharing ?? LocationSharingMode.sosOnly;
    } catch (e) {
      debugPrint('SosController: sharing mode not changed ($e)');
      return null;
    }
  }

  /// Asks for location permission, waiting at most
  /// [permissionPromptTimeout] (then `denied`). A prompt answered later
  /// still starts live tracking of the alert sent meanwhile.
  Future<LocationPermissionState> _requestPermission(int epoch) async {
    final request = ref
        .read(locationServiceProvider)
        .ensurePermission(background: true);
    var timedOut = false;
    final result = await request.timeout(
      permissionPromptTimeout,
      onTimeout: () {
        timedOut = true;
        return LocationPermissionState.denied;
      },
    );
    if (timedOut) {
      unawaited(
        request.then((late) {
          if (!late.isGranted || !_isCurrent(epoch)) return;
          final alert = state.alert;
          if (alert == null ||
              !_isCurrentAlert(epoch, alert.id) ||
              _uploader != null ||
              state.sharing != SosSharing.unavailable) {
            return;
          }
          unawaited(_startTracking(epoch, alert.id, permission: late));
        }, onError: (Object e) => debugPrint('SosController: $e')),
      );
    }
    return result;
  }

  bool _isFreshEnough(GeoFix fix) {
    if (!fix.isLastKnown) return true;
    final age = _now().toUtc().difference(fix.at.toUtc());
    return age.abs() <= maxLastKnownFixAge;
  }

  Future<SosAlert> _createWithRetry(int epoch, GeoPoint? location) async {
    final repository = ref.read(sosRepositoryProvider);
    for (var attempt = 0; ; attempt++) {
      try {
        return await repository.create(location: location);
      } on ApiException catch (e) {
        final transient = e.isNetwork || e.isServer;
        if (!transient || attempt >= sendRetryDelays.length) rethrow;
        await Future<void>.delayed(sendRetryDelays[attempt]);
        if (!_isCurrent(epoch)) rethrow;
      }
    }
  }

  // ── Active alert & tracking ──────────────────────────────────────────────

  void _activate(
    int epoch,
    SosAlert alert, {
    LocationPermissionState? permission,
    DateTime? lastSentAt,
  }) {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _stopUploader();
    final now = _now();
    if (!alert.isActiveAt(now)) {
      state = const SosState();
      return;
    }
    state = SosState(
      phase: SosPhase.active,
      alert: alert,
      sharing: alert.locationShared ? SosSharing.live : SosSharing.off,
      permission: permission,
      lastSentAt: lastSentAt,
    );
    _scheduleExpiry(epoch, alert);
    if (alert.locationShared) {
      unawaited(
        _startTracking(
          epoch,
          alert.id,
          permission: permission,
          since: lastSentAt,
        ),
      );
    }
  }

  void _scheduleExpiry(int epoch, SosAlert alert) {
    _expiryTimer?.cancel();
    final left = alert.expiresAt.difference(_now());
    _expiryTimer = Timer(left.isNegative ? Duration.zero : left, () {
      _expiryTimer = null;
      if (_isCurrentAlert(epoch, alert.id)) _end(epoch);
    });
  }

  /// Starts live tracking for the active alert. Never prompts unless
  /// [prompt] (a tap on "Allow location").
  Future<void> _startTracking(
    int epoch,
    String alertId, {
    LocationPermissionState? permission,
    DateTime? since,
    bool prompt = false,
  }) async {
    _stopUploader();
    if (!_isCurrentAlert(epoch, alertId)) return;
    final service = ref.read(locationServiceProvider);
    final granted = permission != null && permission.isGranted
        ? permission
        : prompt
        ? await service.ensurePermission(background: true)
        : await service.checkPermission();
    if (!_isCurrentAlert(epoch, alertId) || _uploader != null) return;
    if (!granted.isGranted) {
      state = state.copyWith(
        sharing: SosSharing.unavailable,
        permission: () => granted,
      );
      return;
    }

    final texts = ref.read(sosTrackingTextsProvider);
    final repository = ref.read(sosRepositoryProvider);
    final uploader = SosLocationUploader(
      alertId: alertId,
      fixes: service.track(
        notificationTitle: texts.title,
        notificationText: texts.text,
        channelName: texts.channel,
      ),
      upload: repository.sendLocation,
      minInterval: AppConfig.sosLocationInterval,
      now: ref.read(sosClockProvider),
      lastSentAt: since,
      onUploaded: (alert, at) {
        if (!_isCurrentAlert(epoch, alertId)) return;
        final current = state.alert;
        state = state.copyWith(
          sharing: SosSharing.live,
          lastSentAt: () => at,
          permission: () => null,
          alert: () => current == null ? alert : _merge(current, alert),
        );
      },
      onUnavailable: (reason) {
        if (!_isCurrentAlert(epoch, alertId)) return;
        state = state.copyWith(
          sharing: SosSharing.unavailable,
          permission: () => reason,
        );
      },
      onStopped: (reason) => _onUploadStopped(epoch, alertId, reason),
    );
    _uploader = uploader;
    state = state.copyWith(sharing: SosSharing.live, permission: () => null);
    uploader.start();
  }

  void _onUploadStopped(int epoch, String alertId, SosUploadStop reason) {
    if (!_isCurrentAlert(epoch, alertId)) return;
    _uploader = null;
    switch (reason) {
      case SosUploadStop.alertEnded:
        _end(epoch);
      case SosUploadStop.removedFromFamily:
        _end(epoch);
        ref.read(sosSessionResyncProvider)();
      case SosUploadStop.sharingDisabled:
        state = state.copyWith(sharing: SosSharing.off);
        ref.read(sosSessionResyncProvider)();
      case SosUploadStop.streamEnded:
        state = state.copyWith(
          sharing: SosSharing.unavailable,
          permission: () => state.permission ?? LocationPermissionState.denied,
        );
    }
  }

  Future<LocationPermissionState?> retryLocation() async {
    final alert = state.alert;
    if (!state.isActive || alert == null) return null;
    final epoch = _epoch;
    final permission = await ref
        .read(locationServiceProvider)
        .ensurePermission(background: true);
    if (!_isCurrentAlert(epoch, alert.id)) return permission;
    if (!alert.locationShared &&
        !(ref.read(currentMemberProvider)?.locationSharing.sharesDuringSos ??
            false)) {
      return permission;
    }
    await _startTracking(epoch, alert.id, permission: permission);
    return permission;
  }

  /// The member's `locationSharing` changed (settings screen, another
  /// phone) while the alert is active.
  void _onSharingModeChanged(
    int epoch,
    LocationSharingMode? previous,
    LocationSharingMode? next,
  ) {
    final alert = state.alert;
    if (!_isCurrent(epoch) || !state.isActive || alert == null) return;
    if (next == null || !next.sharesDuringSos) {
      _stopUploader();
      state = state.copyWith(sharing: SosSharing.off);
    } else if (_uploader == null) {
      // Switching from `never` during an alert starts sharing.
      state = state.copyWith(alert: () => alert.copyWith(locationShared: true));
      unawaited(_startTracking(epoch, alert.id));
    }
  }

  void _onForeground(int epoch) {
    final alert = state.alert;
    if (!_isCurrent(epoch) || !state.isActive || alert == null) return;
    // Permission may have been granted in the system settings meanwhile.
    if (state.sharing == SosSharing.unavailable && _uploader == null) {
      unawaited(_startTracking(epoch, alert.id));
    }
  }

  void _onActiveAlerts(int epoch, AsyncValue<List<SosAlert>> value) {
    // Only settled lists: while (re)loading the previous list is still
    // exposed and may predate an alert that was just sent.
    if (!_isCurrent(epoch) || value.isLoading) return;
    final alerts = value.value;
    final me = ref.read(currentMemberProvider)?.id;
    if (alerts == null || me == null) return;
    final now = _now();
    // An alert this session saw end is never adopted again, even when a
    // list fetched before the end still reports it.
    final ended = ref.read(sosEndedAlertIdsProvider);
    SosAlert? mine;
    for (final a in alerts) {
      if (a.isOwnedBy(me) && a.isActiveAt(now) && !ended.contains(a.id)) {
        mine = a;
        break;
      }
    }

    void apply() {
      if (!_isCurrent(epoch)) return;
      switch (state.phase) {
        case SosPhase.idle:
          // App start / resume, or a send whose response was lost.
          if (mine != null) _activate(epoch, mine);
        case SosPhase.active:
          final current = state.alert!;
          if (mine == null) {
            unawaited(_verifyStillActive(epoch, current.id));
          } else if (mine.id != current.id) {
            _activate(epoch, mine);
          } else {
            final merged = _merge(current, mine);
            if (merged != current) {
              state = state.copyWith(alert: () => merged);
              if (merged.expiresAt != current.expiresAt) {
                _scheduleExpiry(epoch, merged);
              }
            }
          }
        case SosPhase.countdown:
        case SosPhase.sending:
          break;
      }
    }

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => apply());
    } else {
      apply();
    }
  }

  /// The alert is missing from the active list: make sure it really ended
  /// (the list may be older than the alert) before stopping.
  Future<void> _verifyStillActive(int epoch, String alertId) async {
    if (_verifying) return;
    _verifying = true;
    try {
      final alert = await ref.read(sosRepositoryProvider).get(alertId);
      if (!_isCurrentAlert(epoch, alertId)) return;
      if (!alert.isActiveAt(_now())) _end(epoch);
    } on ApiException catch (e) {
      if (!_isCurrentAlert(epoch, alertId)) return;
      if (e.isNotFound || e.code == ApiErrorCode.noFamily) _end(epoch);
      if (e.code == ApiErrorCode.noFamily) ref.read(sosSessionResyncProvider)();
    } catch (e) {
      debugPrint('SosController: verify failed ($e)');
    } finally {
      _verifying = false;
    }
  }

  /// Newer server data for the same alert; the list responses carry no
  /// trail, which the controller does not need anyway.
  static SosAlert _merge(SosAlert current, SosAlert fresh) =>
      fresh.id == current.id ? fresh.copyWith(trail: const []) : current;

  // ── Resolve ──────────────────────────────────────────────────────────────

  /// "I am okay" ([SosResolution.safe]) / "False alarm". Stops tracking and
  /// returns the resolved alert; `null` when nothing is active or a resolve
  /// is already running. Throws the [ApiException]; `SOS_NOT_ACTIVE` /
  /// `NOT_FOUND` / `NO_FAMILY` also end the local alert (it is over
  /// anyway).
  Future<SosAlert?> resolve(SosResolution resolution) async {
    final alert = state.alert;
    if (!state.isActive || alert == null || state.isResolving) return null;
    final epoch = _epoch;
    state = state.copyWith(resolving: () => resolution);
    try {
      final resolved = await ref
          .read(sosRepositoryProvider)
          .resolve(alert.id, resolution);
      if (_isCurrentAlert(epoch, alert.id)) {
        _end(epoch);
      } else if (ref.mounted) {
        ref.read(sosEndedAlertIdsProvider.notifier).add(alert.id);
        markChanged(ref, {DataScope.sos});
      }
      return resolved;
    } on ApiException catch (e) {
      if (_isCurrentAlert(epoch, alert.id)) {
        // Over anyway: ended / gone, or the member was removed from the
        // family (the removal closes their alerts).
        if (e.code == ApiErrorCode.sosNotActive ||
            e.isNotFound ||
            e.code == ApiErrorCode.noFamily) {
          _end(epoch);
        } else {
          state = state.copyWith(resolving: () => null);
        }
      }
      if (ref.mounted) ref.read(sosSessionResyncProvider).after(e);
      rethrow;
    } catch (_) {
      if (_isCurrentAlert(epoch, alert.id)) {
        state = state.copyWith(resolving: () => null);
      }
      rethrow;
    }
  }

  // ── Teardown ─────────────────────────────────────────────────────────────

  /// The alert is over: stops tracking, goes idle and announces it. The id
  /// is remembered ([sosEndedAlertIdsProvider]) so a list fetched before
  /// the end never shows it as active again.
  void _end(int epoch) {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _stopUploader();
    if (_isCurrent(epoch)) {
      final id = state.alert?.id;
      if (id != null) ref.read(sosEndedAlertIdsProvider.notifier).add(id);
      state = const SosState();
      markChanged(ref, {DataScope.sos});
    }
  }

  void _stopUploader() {
    final uploader = _uploader;
    _uploader = null;
    uploader?.stop();
  }

  void _teardown() {
    _stopCountdown(false);
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _verifying = false;
    _stopUploader();
  }
}

/// The member's own SOS (see [SosController]). Lives for the whole app
/// session so tracking continues on every screen.
final sosControllerProvider = NotifierProvider<SosController, SosState>(
  SosController.new,
);

// ── Resolving other members' alerts ─────────────────────────────────────────

/// Resolves alerts from the alert screen and the banner: the member's own
/// alert goes through [SosController.resolve] (stops tracking), others'
/// (admins: "helped") directly through the repository.
///
/// State = alert id → resolution of the resolves in flight (buttons show a
/// busy state; a second call meanwhile returns `null`).
class SosAlertActions extends Notifier<Map<String, SosResolution>> {
  @override
  Map<String, SosResolution> build() {
    ref.watch(sessionUserIdProvider);
    return const <String, SosResolution>{};
  }

  /// Resolution being sent for [alertId] (also for the member's own alert
  /// while [SosController.resolve] runs), else `null`.
  SosResolution? resolvingOf(String alertId) {
    final own = ref.read(sosControllerProvider);
    if (own.alert?.id == alertId && own.resolving != null) {
      return own.resolving;
    }
    return state[alertId];
  }

  /// Resolves [alertId] with [resolution], announces `DataScope.sos` and
  /// returns the resolved alert (`null` when a resolve is already running).
  /// Throws the [ApiException].
  Future<SosAlert?> resolve(String alertId, SosResolution resolution) async {
    if (resolvingOf(alertId) != null) return null;
    final own = ref.read(sosControllerProvider);
    if (own.isActive && own.alert?.id == alertId) {
      return ref.read(sosControllerProvider.notifier).resolve(resolution);
    }
    state = {...state, alertId: resolution};
    // Read before the await (the answer may arrive after a logout).
    final resync = ref.read(sosSessionResyncProvider);
    try {
      final resolved = await ref
          .read(sosRepositoryProvider)
          .resolve(alertId, resolution);
      if (ref.mounted) {
        if (resolved.status != SosStatus.active) _ended(alertId);
        markChanged(ref, {DataScope.sos});
      }
      return resolved;
    } on ApiException catch (e) {
      // It ended meanwhile: refresh every screen showing it.
      if (ref.mounted &&
          (e.code == ApiErrorCode.sosNotActive || e.isNotFound)) {
        _ended(alertId);
        markChanged(ref, {DataScope.sos});
      }
      // Demoted / removed on another phone: the refreshed session hides the
      // action.
      resync.after(e);
      rethrow;
    } finally {
      if (ref.mounted) state = {...state}..remove(alertId);
    }
  }

  void _ended(String alertId) =>
      ref.read(sosEndedAlertIdsProvider.notifier).add(alertId);
}

final sosAlertActionsProvider =
    NotifierProvider<SosAlertActions, Map<String, SosResolution>>(
      SosAlertActions.new,
    );

/// Resolution being sent for an alert (own or someone else's), for busy
/// buttons: `ref.watch(sosResolvingProvider(alertId))`.
final sosResolvingProvider = Provider.family<SosResolution?, String>((
  ref,
  alertId,
) {
  final own = ref.watch(sosControllerProvider);
  if (own.alert?.id == alertId && own.resolving != null) return own.resolving;
  return ref.watch(sosAlertActionsProvider.select((m) => m[alertId]));
});
