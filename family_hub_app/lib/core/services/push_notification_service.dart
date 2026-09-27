import 'dart:async';
import 'dart:ui' show DartPluginRegistrant, Locale;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/config/app_languages.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/services/push_platform.dart';
import 'package:family_hub/core/services/services_l10n.dart';
import 'package:family_hub/core/settings/settings_controller.dart'
    show resolvedLocaleProvider;
import 'package:family_hub/shared/data/me_repository.dart';
import 'package:family_hub/shared/json.dart';
import 'package:family_hub/shared/providers/data_refresh.dart';
import 'package:family_hub/shared/providers/shared_providers.dart'
    show meRepositoryProvider;

export 'package:family_hub/core/services/push_platform.dart'
    show PushChannelIds, PushTypes;

/// Handles FCM messages while the app is in the background or terminated.
///
/// Must be a top-level function annotated with `vm:entry-point` because it
/// runs in its own isolate. Notification messages (the backend always sends
/// `notification` + `data`) are displayed by the OS itself - on Android in
/// the channel named by the payload. Only a data-only message (not sent by
/// the current backend, handled defensively) is shown here on Android.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (message.notification != null) return;
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  final data = message.data;
  final title = asNonEmptyString(data['title']);
  final body = asNonEmptyString(data['body']);
  if (title == null && body == null) return;
  try {
    DartPluginRegistrant.ensureInitialized();
    final notifier = AndroidLocalNotifier();
    await notifier.initialize(onTap: (_) {});
    final labels = PushChannelLabels.fromL10n(servicesL10n());
    await notifier.show(
      id: PushNotificationService.notificationIdFor(message),
      channelId: PushNotificationService.channelFor(data),
      labels: labels,
      title: title,
      body: body,
      payload: PushNotificationService.routeFromData(data),
    );
  } catch (e) {
    if (kDebugMode) debugPrint('[Push] background display failed: $e');
  }
}

/// Registers / unregisters this device for pushes (`POST /me/devices`,
/// `DELETE /me/devices/:token`).
abstract interface class PushDeviceApi {
  Future<void> register({
    required String token,
    required DevicePlatform platform,
    String? locale,
  });

  Future<void> unregister(String token);
}

/// [PushDeviceApi] over [MeRepository] (the single owner of the `/me`
/// endpoints). The repository is looked up lazily so the long-lived push
/// service never holds a stale API client.
class MeRepositoryPushDeviceApi implements PushDeviceApi {
  const MeRepositoryPushDeviceApi(this._repository);

  final MeRepository Function() _repository;

  @override
  Future<void> register({
    required String token,
    required DevicePlatform platform,
    String? locale,
  }) => _repository().registerDevice(
    token: token,
    platform: platform,
    locale: locale,
  );

  @override
  Future<void> unregister(String token) =>
      _repository().unregisterDevice(token);
}

/// Firebase Cloud Messaging + local notifications (docs/05 §11).
///
/// Every method is a safe no-op while Firebase is not configured
/// (`Firebase.apps` is empty - see `lib/firebase_options.dart`), so the app
/// runs normally without push.
///
/// Lifecycle (wired by the app shell / session):
/// 1. `init()` once after `Firebase.initializeApp` (idempotent).
/// 2. Listen to [routeTaps] and navigate (`context.push(route)`). A tap that
///    cold-started the app is buffered until the first listener subscribes.
/// 3. `registerDevice()` after sign-in / session restore.
/// 4. `unregisterDevice()` on logout **before** the auth tokens are cleared
///    (the DELETE call is authenticated).
class PushNotificationService {
  PushNotificationService({
    required PushDeviceApi deviceApi,
    PushMessaging messaging = const FirebasePushMessaging(),
    LocalNotifier? localNotifier,
    void Function(String type)? onMessageReceived,
    String? Function()? localeResolver,
    Duration networkTimeout = const Duration(seconds: 8),
  }) : _deviceApi = deviceApi,
       _messaging = messaging,
       _localNotifierOverride = localNotifier,
       _onMessageReceived = onMessageReceived,
       _localeResolver = localeResolver,
       _networkTimeout = networkTimeout;

  final PushDeviceApi _deviceApi;
  final PushMessaging _messaging;
  final LocalNotifier? _localNotifierOverride;
  final void Function(String type)? _onMessageReceived;

  /// The app's current language code (used until [registerDevice] /
  /// [updateLocale] pass one explicitly).
  final String? Function()? _localeResolver;
  final Duration _networkTimeout;

  LocalNotifier? _localNotifier;
  late final StreamController<String> _routeTaps =
      StreamController<String>.broadcast(onListen: _flushPendingRoute);
  final List<StreamSubscription<Object?>> _subscriptions = [];

  Future<void>? _initFuture;
  Future<void>? _registerFuture;
  bool _wantsRegistration = false;
  bool _disposed = false;
  String? _pendingRoute;
  String? _registeredToken;
  String? _registeredLocale;
  String? _locale;
  PushChannelLabels? _labels;

  /// Whether push can work in this build (Firebase configured, mobile).
  bool get isAvailable => !_disposed && _messaging.isAvailable;

  /// In-app routes (e.g. `/sos/alert/<id>`) from notification taps, including
  /// the tap that launched the app. Already validated with
  /// [AppRoutes.sanitizeLocation].
  Stream<String> get routeTaps => _routeTaps.stream;

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Wires listeners, notification channels and the background handler.
  /// Safe to call more than once; never throws. A no-op (not remembered)
  /// while Firebase is not initialised.
  Future<void> init() {
    if (!isAvailable) return Future<void>.value();
    return _initFuture ??= _init();
  }

  Future<void> _init() async {
    try {
      _messaging.setBackgroundHandler(firebaseMessagingBackgroundHandler);

      if (_isAndroid) {
        final notifier = _localNotifierOverride ?? AndroidLocalNotifier();
        await notifier.initialize(onTap: _handleLocalTap);
        _localNotifier = notifier;
        await _applyChannelLabels(
          PushChannelLabels.fromL10n(servicesL10n(_localeObject)),
        );
      } else {
        // iOS: the OS presents foreground notifications itself.
        await _messaging.enableForegroundPresentation();
      }

      _subscriptions
        ..add(_messaging.onMessage.listen(_handleForegroundMessage))
        ..add(_messaging.onMessageOpenedApp.listen(_handleOpenedMessage))
        ..add(_messaging.onTokenRefresh.listen(_handleTokenRefresh));

      // Cold start: the app was launched by tapping a notification.
      final initial = await _messaging.getInitialMessage();
      if (initial != null) {
        _handleOpenedMessage(initial);
      } else {
        final payload = await _localNotifier?.launchPayload();
        _handleLocalTap(payload);
      }
    } catch (e, st) {
      _log('init failed: $e\n$st');
    }
  }

  /// Registers this device's FCM token with the backend and keeps it
  /// registered when FCM rotates it. Asks for notification permission on
  /// first use. Never throws (push is best effort).
  ///
  /// [locale]: language code for push texts (`hi`, `ar`, ...). When omitted
  /// the last one passed is reused, else the app language (provider wiring);
  /// if none is known it is left out and the backend falls back to the
  /// account's stored `locale`.
  Future<void> registerDevice({String? locale}) async {
    if (locale != null) await _setLocale(locale);
    _wantsRegistration = true;
    if (!isAvailable) return;
    await init();
    return _registerFuture ??= _register().whenComplete(
      () => _registerFuture = null,
    );
  }

  Future<void> _register() async {
    try {
      try {
        await _messaging.requestPermission();
      } catch (e) {
        _log('permission request failed: $e');
      }
      await _messaging.setAutoInitEnabled(true);
      final token = await _messaging.getToken();
      if (token == null) {
        _log('no FCM token yet; will register on token refresh');
        return;
      }
      await _post(token);
    } catch (e) {
      _log('registerDevice failed: $e');
    }
  }

  Future<void> _post(String token) async {
    if (!_wantsRegistration) return;
    final locale = _effectiveLocale;
    await _deviceApi
        .register(token: token, platform: _devicePlatform, locale: locale)
        .timeout(_networkTimeout);
    _registeredToken = token;
    _registeredLocale = locale;
  }

  /// Changes the language of future pushes (re-registers the token) and of
  /// the Android channel names. [pushNotificationServiceProvider] calls it
  /// whenever the app language changes.
  Future<void> updateLocale(String languageCode) async {
    await _setLocale(languageCode);
    // An in-flight registration may still send the previous language.
    await _registerFuture;
    final registeredInOtherLanguage =
        _registeredToken != null && _registeredLocale != _effectiveLocale;
    if (_wantsRegistration && registeredInOtherLanguage) {
      await registerDevice();
    }
  }

  /// Stops pushes to this device for the signed-in account: deletes the
  /// token on the backend (best effort, time-boxed) and locally, so the next
  /// account on this phone gets a fresh token. Never throws.
  Future<void> unregisterDevice() async {
    _wantsRegistration = false;
    final pendingRegistration = _registerFuture;
    if (!isAvailable) return;
    try {
      // Let an in-flight registration finish first, or it could re-add the
      // token right after we deleted it.
      await pendingRegistration;
      final token = _registeredToken ?? await _messaging.getToken();
      if (token != null) {
        await _deviceApi.unregister(token).timeout(_networkTimeout);
      }
    } catch (e) {
      _log('backend unregister failed: $e');
    }
    _registeredToken = null;
    _registeredLocale = null;
    try {
      // Disable auto-init first so FCM does not mint a new token right
      // after the old one is deleted.
      await _messaging.setAutoInitEnabled(false);
      await _messaging.deleteToken().timeout(_networkTimeout);
    } catch (e) {
      _log('deleting the local token failed: $e');
    }
  }

  /// The current FCM token (e.g. for `POST /auth/logout { deviceToken }`),
  /// `null` when push is unavailable.
  Future<String?> currentToken() async {
    if (!isAvailable) return null;
    try {
      return _registeredToken ?? await _messaging.getToken();
    } catch (e) {
      _log('getToken failed: $e');
      return null;
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    for (final s in _subscriptions) {
      await s.cancel();
    }
    _subscriptions.clear();
    await _routeTaps.close();
  }

  // ---------------------------------------------------------------------------
  // Message handling
  // ---------------------------------------------------------------------------

  void _handleForegroundMessage(RemoteMessage message) {
    final data = message.data;
    _notifyReceived(data);
    // iOS shows it via the foreground presentation options.
    final notifier = _localNotifier;
    if (!_isAndroid || notifier == null) return;
    final title =
        message.notification?.title ?? asNonEmptyString(data['title']);
    final body = message.notification?.body ?? asNonEmptyString(data['body']);
    if (title == null && body == null) return;
    unawaited(
      notifier
          .show(
            id: notificationIdFor(message),
            channelId: channelFor(data),
            labels:
                _labels ??
                PushChannelLabels.fromL10n(servicesL10n(_localeObject)),
            title: title,
            body: body,
            payload: routeFromData(data),
          )
          .catchError((Object e) => _log('show failed: $e')),
    );
  }

  void _handleOpenedMessage(RemoteMessage message) {
    _notifyReceived(message.data);
    _emitRoute(routeFromData(message.data));
  }

  void _handleLocalTap(String? payload) =>
      _emitRoute(AppRoutes.sanitizeLocation(payload));

  void _handleTokenRefresh(String token) {
    if (!_wantsRegistration || token.isEmpty) return;
    unawaited(
      _post(token).catchError((Object e) => _log('token refresh failed: $e')),
    );
  }

  void _notifyReceived(Map<String, dynamic> data) {
    final type = asNonEmptyString(data['type']);
    if (type == null) return;
    try {
      _onMessageReceived?.call(type);
    } catch (e) {
      _log('onMessageReceived failed: $e');
    }
  }

  void _emitRoute(String? route) {
    if (route == null || _routeTaps.isClosed) return;
    if (_routeTaps.hasListener) {
      _routeTaps.add(route);
    } else {
      _pendingRoute = route;
    }
  }

  void _flushPendingRoute() {
    final route = _pendingRoute;
    if (route == null) return;
    _pendingRoute = null;
    scheduleMicrotask(() {
      if (!_routeTaps.isClosed) _routeTaps.add(route);
    });
  }

  // ---------------------------------------------------------------------------
  // Locale / channels
  // ---------------------------------------------------------------------------

  String? get _effectiveLocale {
    if (_locale != null) return _locale;
    try {
      final code = _localeResolver?.call();
      return code == null ? null : AppLanguages.byCode(code)?.code;
    } catch (_) {
      return null;
    }
  }

  Locale? get _localeObject {
    final code = _effectiveLocale;
    return code == null ? null : Locale(code);
  }

  Future<void> _setLocale(String code) async {
    final language = AppLanguages.byCode(code.trim().toLowerCase());
    if (language == null) return; // unsupported -> backend falls back
    _locale = language.code;
    if (_localNotifier != null) {
      await _applyChannelLabels(
        PushChannelLabels.fromL10n(servicesL10n(language.locale)),
      );
    }
  }

  Future<void> _applyChannelLabels(PushChannelLabels labels) async {
    if (labels == _labels) return;
    try {
      await _localNotifier?.createChannels(labels);
      _labels = labels;
    } catch (e) {
      _log('creating channels failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Pure helpers (unit tested)
  // ---------------------------------------------------------------------------

  static DevicePlatform get _devicePlatform =>
      defaultTargetPlatform == TargetPlatform.iOS
      ? DevicePlatform.ios
      : DevicePlatform.android;

  /// The in-app route for a push `data` payload: `data.route` when it is a
  /// safe internal path, otherwise derived from `type` + `id`, otherwise
  /// `null` (tap just opens the app).
  static String? routeFromData(Map<String, dynamic> data) {
    final explicit = AppRoutes.sanitizeLocation(
      asNonEmptyString(data['route']),
    );
    if (explicit != null) return explicit;
    final id = asNonEmptyString(data['id'])?.trim();
    final hasId = id != null && id.isNotEmpty;
    switch (asNonEmptyString(data['type'])) {
      case PushTypes.sos:
      case PushTypes.sosResolved:
        return hasId ? AppRoutes.sosAlert(id) : AppRoutes.sos;
      case PushTypes.taskAssigned:
      case PushTypes.taskCompleted:
        return hasId ? AppRoutes.taskDetail(id) : AppRoutes.tasks;
      case PushTypes.notice:
        return AppRoutes.notices;
      case PushTypes.goalAchieved:
        return AppRoutes.money;
      case PushTypes.memberJoined:
        return hasId ? AppRoutes.memberDetail(id) : AppRoutes.members;
      default:
        return null;
    }
  }

  /// Android channel for a payload: `sos_alerts` for `type == sos`.
  static String channelFor(Map<String, dynamic> data) =>
      asNonEmptyString(data['type']) == PushTypes.sos
      ? PushChannelIds.sos
      : PushChannelIds.general;

  /// Stable per resource, so a newer push about the same SOS / task
  /// replaces the older notification instead of stacking (e.g. "SOS
  /// resolved" replaces the loud SOS alert).
  static int notificationIdFor(RemoteMessage message) {
    final data = message.data;
    final type = asNonEmptyString(data['type']);
    final id = asNonEmptyString(data['id']);
    final key = (type != null && id != null)
        ? '${_resourceKind(type)}:$id'
        : message.messageId ?? DateTime.now().microsecondsSinceEpoch.toString();
    return _stableHash(key);
  }

  static String _resourceKind(String type) => switch (type) {
    PushTypes.sos || PushTypes.sosResolved => 'sos',
    PushTypes.taskAssigned || PushTypes.taskCompleted => 'task',
    _ => type,
  };

  /// FNV-1a (31-bit) - `String.hashCode` is not guaranteed stable across
  /// isolates / runs, and the background isolate must produce the same id.
  static int _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash & 0x7fffffff;
  }

  /// Data scopes that a push of [type] makes stale (refreshed immediately
  /// when the push arrives in the foreground or is tapped).
  static Set<DataScope> scopesForType(String type) => switch (type) {
    PushTypes.sos || PushTypes.sosResolved => {DataScope.sos},
    PushTypes.taskAssigned || PushTypes.taskCompleted => {DataScope.tasks},
    PushTypes.notice => {DataScope.notices},
    PushTypes.goalAchieved => {DataScope.goals, DataScope.ledger},
    PushTypes.memberJoined => {DataScope.members, DataScope.family},
    _ => const <DataScope>{},
  };

  static void _log(String message) {
    if (kDebugMode) debugPrint('[Push] $message');
  }
}

final pushNotificationServiceProvider = Provider<PushNotificationService>((
  ref,
) {
  final service = PushNotificationService(
    // Read lazily per call: overrides of meRepositoryProvider (tests) apply
    // and the long-lived service never holds a stale API client.
    deviceApi: MeRepositoryPushDeviceApi(() => ref.read(meRepositoryProvider)),
    // Foreground / tapped pushes refresh the affected lists right away.
    onMessageReceived: (type) {
      final scopes = PushNotificationService.scopesForType(type);
      if (scopes.isNotEmpty && ref.mounted) markChanged(ref, scopes);
    },
    // Read per call (like the Accept-Language interceptor) so the service
    // never has to be rebuilt.
    localeResolver: () => ref.read(resolvedLocaleProvider).languageCode,
  );
  // Language change -> re-label channels and re-register the token, so the
  // backend sends future pushes in the new language.
  ref.listen<Locale>(resolvedLocaleProvider, (previous, next) {
    if (previous?.languageCode == next.languageCode) return;
    unawaited(service.updateLocale(next.languageCode));
  }, onError: (Object error, StackTrace stackTrace) {});
  ref.onDispose(service.dispose);
  return service;
});
