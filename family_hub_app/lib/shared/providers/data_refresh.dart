import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Kinds of server data that can change. Features announce mutations with
/// [markChanged]; data providers watch the scopes they depend on:
///
/// ```dart
/// final tasksProvider = FutureProvider<List<FamilyTask>>((ref) {
///   ref.watch(sessionUserIdProvider);
///   ref.watch(dataRefreshProvider.select((m) => m[DataScope.tasks]));
///   return ref.watch(taskRepositoryProvider).list();
/// });
/// ```
///
/// This decouples features: a screen never imports another feature just to
/// invalidate its providers (docs/05-FLUTTER_GUIDE.md §10).
enum DataScope {
  family,
  members,
  tasks,
  ledger,
  goals,
  notices,
  sos,
  emergencyCards,
}

/// Change counters per [DataScope]. Every scope is always present (starts at
/// `0`) so `m[scope]` is never `null` for watchers.
class DataRefresh extends Notifier<Map<DataScope, int>> {
  @override
  Map<DataScope, int> build() => {for (final s in DataScope.values) s: 0};

  /// Bumps the counter of every scope in [scopes]; providers watching those
  /// scopes refetch. Empty sets are ignored.
  void markChanged(Set<DataScope> scopes) {
    if (scopes.isEmpty) return;
    state = Map.unmodifiable({
      for (final s in DataScope.values)
        s: (state[s] ?? 0) + (scopes.contains(s) ? 1 : 0),
    });
  }

  /// Bumps every scope (e.g. pull-to-refresh on the dashboard, app resume).
  void markAllChanged() => markChanged(DataScope.values.toSet());
}

final dataRefreshProvider = NotifierProvider<DataRefresh, Map<DataScope, int>>(
  DataRefresh.new,
);

/// Announces a successful mutation from a provider / notifier.
void markChanged(Ref ref, Set<DataScope> scopes) =>
    ref.read(dataRefreshProvider.notifier).markChanged(scopes);

/// Announces a successful mutation from a widget:
/// `ref.markChanged({DataScope.tasks})`.
extension DataRefreshWidgetRefX on WidgetRef {
  void markChanged(Set<DataScope> scopes) =>
      read(dataRefreshProvider.notifier).markChanged(scopes);
}
