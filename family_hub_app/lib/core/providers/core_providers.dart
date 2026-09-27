import 'dart:ui' show PlatformDispatcher;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:family_hub/core/config/app_config.dart';
import 'package:family_hub/core/network/api_client.dart';
import 'package:family_hub/core/network/auth_events.dart';
import 'package:family_hub/core/network/dio_factory.dart';
import 'package:family_hub/core/network/mock/mock_backend.dart';
import 'package:family_hub/core/network/mock/mock_registry.dart';
import 'package:family_hub/core/settings/settings_controller.dart';
import 'package:family_hub/core/storage/local_cache.dart';
import 'package:family_hub/core/storage/token_storage.dart';

export 'package:family_hub/core/network/api_client.dart';
export 'package:family_hub/core/network/auth_events.dart';
export 'package:family_hub/core/storage/local_cache.dart';
export 'package:family_hub/core/storage/token_storage.dart';

/// `SharedPreferences` instance, loaded in `main()` before `runApp`:
/// `ProviderScope(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)])`.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in main() / tests',
  ),
);

/// Access/refresh tokens in secure storage (with in-memory cache).
final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());

/// JSON "last known good" cache (offline start, snapshots).
final localCacheProvider = Provider<LocalCache>(
  (ref) => LocalCache(ref.watch(sharedPreferencesProvider)),
);

/// Session events from the network layer (`sessionExpired`).
final authEventsProvider = Provider<AuthEvents>((ref) {
  final events = AuthEvents();
  ref.onDispose(events.dispose);
  return events;
});

/// In-memory backend when running without `API_BASE_URL`; null otherwise.
final mockBackendProvider = Provider<MockBackend?>((ref) {
  if (!AppConfig.useMockApi) return null;
  final backend = MockBackend();
  registerAllMocks(backend);
  return backend;
});

/// Whether the API was reachable on the last request.
enum ConnectivityStatus { online, offline }

extension ConnectivityStatusX on ConnectivityStatus {
  bool get isOffline => this == ConnectivityStatus.offline;
  bool get isOnline => this == ConnectivityStatus.online;
}

/// Updated by every request: `offline` after a request failed without a
/// response (no connection / timeout), `online` as soon as the server
/// answers again. Drives `OfflineBanner`.
class ConnectivityStatusNotifier extends Notifier<ConnectivityStatus> {
  @override
  ConnectivityStatus build() => ConnectivityStatus.online;

  void report(bool reachable) {
    final next = reachable
        ? ConnectivityStatus.online
        : ConnectivityStatus.offline;
    if (state != next) state = next;
  }
}

final connectivityStatusProvider =
    NotifierProvider<ConnectivityStatusNotifier, ConnectivityStatus>(
      ConnectivityStatusNotifier.new,
    );

/// The configured HTTP client (interceptors: reachability, locale, auth
/// with token refresh, mock backend in mock mode).
final dioProvider = Provider<Dio>((ref) {
  final dio = createDio(
    tokenStorage: ref.watch(tokenStorageProvider),
    authEvents: ref.watch(authEventsProvider),
    mockBackend: ref.watch(mockBackendProvider),
    // Read per request so a language change applies immediately without
    // rebuilding the client (and without a provider dependency cycle).
    languageCode: () {
      try {
        return ref.read(resolvedLocaleProvider).languageCode;
      } catch (_) {
        return PlatformDispatcher.instance.locale.languageCode;
      }
    },
    onReachability: (reachable) {
      if (ref.mounted) {
        ref.read(connectivityStatusProvider.notifier).report(reachable);
      }
    },
  );
  ref.onDispose(() => dio.close(force: true));
  return dio;
});

/// Envelope-aware API client used by every repository.
final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(ref.watch(dioProvider)),
);
