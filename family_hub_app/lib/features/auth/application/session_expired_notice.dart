import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/providers/core_providers.dart';

/// `true` after the session expired on this device (the refresh token was
/// rejected → `AuthEvents.sessionExpired`) until the welcome / log-in screen
/// has told the user why they were signed out.
///
/// It listens from the moment it is first read, so the app shell should keep
/// it alive while signed in (`ref.watch(sessionExpiredNoticeProvider)`);
/// the welcome and log-in screens read and [dismiss] it.
class SessionExpiredNotice extends Notifier<bool> {
  @override
  bool build() {
    final sub = ref
        .watch(authEventsProvider)
        .sessionExpired
        .listen((_) => state = true);
    ref.onDispose(sub.cancel);
    return false;
  }

  void dismiss() => state = false;
}

final sessionExpiredNoticeProvider =
    NotifierProvider<SessionExpiredNotice, bool>(SessionExpiredNotice.new);
