import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/features/settings/application/location_upload_clock.dart';
import 'package:family_hub/features/settings/data/system_settings.dart';
import 'package:family_hub/features/settings/domain/data_export.dart';
import 'package:family_hub/features/settings/domain/notification_status.dart';
import 'package:family_hub/shared/session/session_controller.dart';

/// `GET /me/export` for the data export screen. Fetched fresh every time the
/// screen opens (auto-dispose) and never cached on disk.
final dataExportProvider = FutureProvider.autoDispose<DataExport>((ref) async {
  ref.watch(sessionUserIdProvider);
  final json = await ref.watch(meRepositoryProvider).exportData();
  return DataExport.fromJson(
    json,
    receivedAt: ref.read(settingsClockProvider)(),
  );
}, retry: apiRetryPolicy);

/// Notification permission of this app, re-read whenever the More tab is
/// shown again or the app resumes (the user may have changed it in the
/// phone settings).
final notificationStatusProvider =
    FutureProvider.autoDispose<NotificationStatus>(
      (ref) => ref.watch(systemSettingsProvider).notificationStatus(),
      retry: (_, _) => null,
    );
