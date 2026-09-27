import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/providers/core_providers.dart';
import 'package:family_hub/features/dashboard/domain/dashboard_data.dart';
import 'package:family_hub/shared/data/repository_utils.dart';

/// `GET /dashboard` (docs/03-API_CONTRACT.md §11).
class DashboardRepository {
  DashboardRepository(this._api);

  final ApiClient _api;

  static const path = '/dashboard';

  /// The caller's dashboard. A response without the `family` or `me`
  /// object is a server / proxy bug and fails as `ApiException(UNKNOWN)`
  /// instead of rendering a half-empty home screen; every other field is
  /// parsed leniently ([DashboardData.fromJson]).
  ///
  /// Errors: `NO_FAMILY` (removed from the family), `UNAUTHORIZED`, network.
  Future<DashboardData> fetch() async {
    final data = await _api.get(path);
    final json = requireObject(data);
    requireObject(json, 'family');
    requireObject(json, 'me');
    return DashboardData.fromJson(json);
  }
}

final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (ref) => DashboardRepository(ref.watch(apiClientProvider)),
);
