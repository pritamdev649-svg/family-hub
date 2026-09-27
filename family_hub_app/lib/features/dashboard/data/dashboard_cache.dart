import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/providers/core_providers.dart';
import 'package:family_hub/features/dashboard/domain/dashboard_data.dart';
import 'package:family_hub/shared/json.dart';

/// The last dashboard of the signed-in account, kept in [LocalCache] so the
/// home screen opens offline (docs/02-ARCHITECTURE.md §8).
///
/// * One entry ([cacheKey]) tagged with the account and family it belongs
///   to; a read for any other account / family returns `null`. The session
///   clears [LocalCache] on logout, account switch and session expiry.
/// * Location data is never written ([DashboardData.withoutLocations]).
/// * Copies older than [maxAge] or of another format [version] are ignored;
///   unreadable entries are dropped.
///
/// Never throws: a broken store only means there is no offline copy.
class DashboardCache {
  DashboardCache(this._cache);

  static const cacheKey = 'dashboard.last';

  /// Bump when the stored shape changes incompatibly.
  static const version = 1;

  /// Older copies are too stale to be useful.
  static const maxAge = Duration(days: 30);

  final LocalCache _cache;

  /// Saves [data] as [userId]'s offline copy.
  Future<void> write(String userId, DashboardData data) async {
    if (userId.isEmpty) return;
    await _cache.write(cacheKey, {
      'v': version,
      'u': userId,
      'f': data.family.id,
      'data': data.withoutLocations().toJson(),
    });
  }

  /// [userId]'s offline copy for [familyId] with the time it was saved
  /// (never in the future, even when the clock was set back), or `null`.
  DashboardSnapshot? read(String userId, String familyId, {DateTime? now}) {
    if (userId.isEmpty || familyId.isEmpty) return null;
    final data = _cache.read<DashboardData?>(cacheKey, (json) {
      final entry = asMap(json);
      if (entry['v'] != version ||
          entry['u'] != userId ||
          entry['f'] != familyId ||
          entry['data'] is! Map) {
        return null;
      }
      return DashboardData.fromJson(asMap(entry['data']));
    }, maxAge: maxAge);
    if (data == null || data.family.id != familyId || data.me.id.isEmpty) {
      return null;
    }
    final current = (now ?? DateTime.now()).toUtc();
    var savedAt = _cache.savedAt(cacheKey) ?? current;
    if (savedAt.isAfter(current)) savedAt = current;
    return DashboardSnapshot(userId: userId, data: data, savedAt: savedAt);
  }

  Future<void> clear() => _cache.remove(cacheKey);
}

final dashboardCacheProvider = Provider<DashboardCache>(
  (ref) => DashboardCache(ref.watch(localCacheProvider)),
);
