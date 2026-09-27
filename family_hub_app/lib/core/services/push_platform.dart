import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:family_hub/l10n/app_localizations.dart';

/// Android notification channel ids. They must match the backend
/// (`services/push.js`) and the FCM `default_notification_channel_id`
/// meta-data in `android/app/src/main/AndroidManifest.xml`.
abstract final class PushChannelIds {
  /// Emergency alerts: max importance, sound, vibration, lock screen.
  static const sos = 'sos_alerts';

  /// Everything else.
  static const general = 'general';
}

/// `data.type` values of the push payload (docs/03-API_CONTRACT.md §13).
abstract final class PushTypes {
  static const sos = 'sos';
  static const sosResolved = 'sos_resolved';
  static const taskAssigned = 'task_assigned';
  static const taskCompleted = 'task_completed';
  static const notice = 'notice';
  static const goalAchieved = 'goal_achieved';
  static const memberJoined = 'member_joined';
}

/// Localized names/descriptions of the Android notification channels
/// (visible in the system notification settings).
@immutable
class PushChannelLabels {
  const PushChannelLabels({
    required this.sosName,
    required this.sosDescription,
    required this.generalName,
    required this.generalDescription,
  });

  factory PushChannelLabels.fromL10n(AppLocalizations l10n) =>
      PushChannelLabels(
        sosName: l10n.servicesPushChannelSosName,
        sosDescription: l10n.servicesPushChannelSosDescription,
        generalName: l10n.servicesPushChannelGeneralName,
        generalDescription: l10n.servicesPushChannelGeneralDescription,
      );

  final String sosName;
  final String sosDescription;
  final String generalName;
  final String generalDescription;

  @override
  bool operator ==(Object other) =>
      other is PushChannelLabels &&
      other.sosName == sosName &&
      other.sosDescription == sosDescription &&
      other.generalName == generalName &&
      other.generalDescription == generalDescription;

  @override
  int get hashCode =>
      Object.hash(sosName, sosDescription, generalName, generalDescription);
}

/// Seam over Firebase Cloud Messaging so the push logic is testable.
abstract interface class PushMessaging {
  /// `false` when Firebase was not initialised (no `flutterfire configure`)
  /// or the platform has no FCM support in this app (web, desktop).
  bool get isAvailable;

  /// Asks for notification permission (iOS prompt, Android 13+ runtime
  /// permission). Returns whether notifications may be shown.
  Future<bool> requestPermission();

  /// FCM auto-init is disabled in AndroidManifest.xml / Info.plist so no
  /// token exists before sign-in; enabled on register, disabled on
  /// unregister (the value persists across launches).
  Future<void> setAutoInitEnabled(bool enabled);

  /// The FCM registration token, or `null` when it cannot be obtained yet
  /// (e.g. iOS before APNs registration completes, no Play services).
  Future<String?> getToken();
  Future<void> deleteToken();
  Stream<String> get onTokenRefresh;

  /// Messages received while the app is in the foreground.
  Stream<RemoteMessage> get onMessage;

  /// Notification taps that brought the app from background to foreground.
  Stream<RemoteMessage> get onMessageOpenedApp;

  /// The notification tap that launched the app from terminated state.
  Future<RemoteMessage?> getInitialMessage();

  /// iOS: let the OS show notifications while the app is in the foreground.
  Future<void> enableForegroundPresentation();

  void setBackgroundHandler(BackgroundMessageHandler handler);
}

/// Production [PushMessaging] backed by `firebase_messaging`.
class FirebasePushMessaging implements PushMessaging {
  const FirebasePushMessaging({
    this.apnsAttempts = 10,
    this.apnsDelay = const Duration(milliseconds: 500),
  });

  /// How often / how long to wait for the APNs token on iOS before giving
  /// up (`getToken` throws `apns-token-not-set` until it exists). The token
  /// is registered later through [onTokenRefresh] in that case.
  final int apnsAttempts;
  final Duration apnsDelay;

  FirebaseMessaging get _fm => FirebaseMessaging.instance;

  static bool get _isApple =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  @override
  bool get isAvailable {
    if (kIsWeb) return false;
    final platformSupported =
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    if (!platformSupported) return false;
    try {
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> requestPermission() async {
    final settings = await _fm.requestPermission();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  @override
  Future<void> setAutoInitEnabled(bool enabled) =>
      _fm.setAutoInitEnabled(enabled);

  @override
  Future<String?> getToken() async {
    if (_isApple) {
      var apns = await _fm.getAPNSToken();
      for (var i = 1; apns == null && i < apnsAttempts; i++) {
        await Future<void>.delayed(apnsDelay);
        apns = await _fm.getAPNSToken();
      }
      if (apns == null) return null;
    }
    final token = await _fm.getToken();
    return token == null || token.isEmpty ? null : token;
  }

  @override
  Future<void> deleteToken() => _fm.deleteToken();

  @override
  Stream<String> get onTokenRefresh => _fm.onTokenRefresh;

  @override
  Stream<RemoteMessage> get onMessage => FirebaseMessaging.onMessage;

  @override
  Stream<RemoteMessage> get onMessageOpenedApp =>
      FirebaseMessaging.onMessageOpenedApp;

  @override
  Future<RemoteMessage?> getInitialMessage() => _fm.getInitialMessage();

  @override
  Future<void> enableForegroundPresentation() =>
      _fm.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

  @override
  void setBackgroundHandler(BackgroundMessageHandler handler) =>
      FirebaseMessaging.onBackgroundMessage(handler);
}

/// Seam over `flutter_local_notifications`, used on Android only (FCM does
/// not display notifications while the app is in the foreground there).
abstract interface class LocalNotifier {
  /// [onTap] receives the payload (an in-app route) of a tapped notification.
  Future<void> initialize({required void Function(String? payload) onTap});

  /// Payload of the local notification that launched the app, if any.
  Future<String?> launchPayload();

  /// Creates or re-labels the `sos_alerts` and `general` channels.
  Future<void> createChannels(PushChannelLabels labels);

  Future<void> show({
    required int id,
    required String channelId,
    required PushChannelLabels labels,
    String? title,
    String? body,
    String? payload,
  });
}

/// Production [LocalNotifier] (Android).
class AndroidLocalNotifier implements LocalNotifier {
  AndroidLocalNotifier([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  /// Monochrome status-bar icon, `android/app/src/main/res/drawable/`.
  static const smallIcon = 'ic_stat_notification';

  /// Long, insistent pattern so an SOS is noticed even in a pocket.
  static final Int64List _sosVibration = Int64List.fromList(<int>[
    0,
    600,
    300,
    600,
    300,
    600,
  ]);

  final FlutterLocalNotificationsPlugin _plugin;

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  @override
  Future<void> initialize({
    required void Function(String? payload) onTap,
  }) async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings(smallIcon),
      ),
      onDidReceiveNotificationResponse: (response) => onTap(response.payload),
    );
  }

  @override
  Future<String?> launchPayload() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details == null || !details.didNotificationLaunchApp) return null;
    return details.notificationResponse?.payload;
  }

  @override
  Future<void> createChannels(PushChannelLabels labels) async {
    final android = _android;
    if (android == null) return;
    await android.createNotificationChannel(sosChannel(labels));
    await android.createNotificationChannel(generalChannel(labels));
  }

  static AndroidNotificationChannel sosChannel(PushChannelLabels labels) =>
      AndroidNotificationChannel(
        PushChannelIds.sos,
        labels.sosName,
        description: labels.sosDescription,
        importance: Importance.max,
        vibrationPattern: _sosVibration,
        audioAttributesUsage: AudioAttributesUsage.alarm,
      );

  static AndroidNotificationChannel generalChannel(PushChannelLabels labels) =>
      AndroidNotificationChannel(
        PushChannelIds.general,
        labels.generalName,
        description: labels.generalDescription,
        importance: Importance.high,
      );

  @override
  Future<void> show({
    required int id,
    required String channelId,
    required PushChannelLabels labels,
    String? title,
    String? body,
    String? payload,
  }) {
    final isSos = channelId == PushChannelIds.sos;
    final details = isSos
        ? AndroidNotificationDetails(
            PushChannelIds.sos,
            labels.sosName,
            channelDescription: labels.sosDescription,
            icon: smallIcon,
            importance: Importance.max,
            priority: Priority.max,
            category: AndroidNotificationCategory.alarm,
            visibility: NotificationVisibility.public,
            vibrationPattern: _sosVibration,
            audioAttributesUsage: AudioAttributesUsage.alarm,
            styleInformation: body == null
                ? null
                : BigTextStyleInformation(body),
            ticker: title,
          )
        : AndroidNotificationDetails(
            PushChannelIds.general,
            labels.generalName,
            channelDescription: labels.generalDescription,
            icon: smallIcon,
            importance: Importance.high,
            priority: Priority.high,
            styleInformation: body == null
                ? null
                : BigTextStyleInformation(body),
          );
    return _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(android: details),
      payload: payload,
    );
  }
}
