import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import 'package:family_hub/core/services/push_notification_service.dart';
import 'package:family_hub/features/settings/domain/notification_status.dart';

/// Reads OS-level state the settings screens show and opens the phone's
/// settings page for this app. A seam so screens are testable.
abstract interface class SystemSettingsGateway {
  /// Notification permission of this app. Never prompts, never throws.
  Future<NotificationStatus> notificationStatus();

  /// Opens this app's page in the phone settings (notifications,
  /// permissions). Returns `false` when it could not be opened.
  Future<bool> openAppSettings();
}

/// Production [SystemSettingsGateway]: Firebase Messaging for the
/// notification permission (only when [PushNotificationService.isAvailable])
/// and Geolocator's cross-platform "open app settings".
class DeviceSystemSettings implements SystemSettingsGateway {
  const DeviceSystemSettings(this._push);

  final PushNotificationService _push;

  @override
  Future<NotificationStatus> notificationStatus() async {
    if (!_push.isAvailable) return NotificationStatus.unavailable;
    try {
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();
      return mapAuthorizationStatus(settings.authorizationStatus);
    } catch (e) {
      if (kDebugMode) debugPrint('[Settings] notification status failed: $e');
      return NotificationStatus.unavailable;
    }
  }

  @override
  Future<bool> openAppSettings() async {
    try {
      return await Geolocator.openAppSettings();
    } catch (e) {
      if (kDebugMode) debugPrint('[Settings] open app settings failed: $e');
      return false;
    }
  }

  /// FCM permission → [NotificationStatus].
  static NotificationStatus mapAuthorizationStatus(AuthorizationStatus s) =>
      switch (s) {
        AuthorizationStatus.authorized ||
        AuthorizationStatus.provisional => NotificationStatus.enabled,
        AuthorizationStatus.notDetermined => NotificationStatus.notDetermined,
        // denied, deniedPermanently and statuses added by future plugin
        // versions: the user must allow it in the phone settings.
        _ => NotificationStatus.disabled,
      };
}

final systemSettingsProvider = Provider<SystemSettingsGateway>(
  (ref) => DeviceSystemSettings(ref.watch(pushNotificationServiceProvider)),
);
