import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/services/location_service.dart';
import 'package:family_hub/shared/session/session_controller.dart';

/// Current time; overridden in tests.
final settingsClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// When this device last uploaded the signed-in member's location
/// (`PUT /me/location`), shared by the location screen and the background
/// sync so they never upload twice within the throttle window. Resets on
/// sign-out / account switch.
class LocationUploadClock extends Notifier<DateTime?> {
  @override
  DateTime? build() {
    ref.watch(sessionUserIdProvider);
    return null;
  }

  /// Remembers a successful upload at "now".
  void record() => state = ref.read(settingsClockProvider)();

  /// Whether the last upload is older than [interval] (or there was none).
  bool isDue(Duration interval) {
    final last = state;
    if (last == null) return true;
    final elapsed = ref.read(settingsClockProvider)().difference(last);
    // A clock that jumped backwards counts as due.
    return elapsed.isNegative || elapsed >= interval;
  }
}

final locationUploadClockProvider =
    NotifierProvider<LocationUploadClock, DateTime?>(LocationUploadClock.new);

/// Oldest OS-cached ("last known") position that may still be shared as the
/// member's current location.
const maxLastKnownFixAge = Duration(minutes: 10);

/// Whether [fix] may be uploaded as "where I am now". `PUT /me/location`
/// has no timestamp (the server stamps `recordedAt`), so an old cached
/// position would show the family a wrong place as current. Fresh fixes are
/// always usable; last-known ones only when at most [maxLastKnownFixAge]
/// old.
bool isShareableFix(GeoFix fix, DateTime now) {
  if (!fix.isLastKnown) return true;
  final age = now.toUtc().difference(fix.at.toUtc());
  // A fix "from the future" means the clocks disagree: trust it only when
  // the difference is small.
  return age.abs() <= maxLastKnownFixAge;
}
