import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/providers/core_providers.dart';
import 'package:family_hub/features/ledger/domain/ledger_entry.dart';
import 'package:family_hub/features/ledger/domain/ledger_requests.dart';
import 'package:family_hub/features/ledger/domain/savings_goal.dart';
import 'package:family_hub/shared/data/repository_utils.dart';
import 'package:family_hub/shared/json.dart';

/// `?status=` filter of `GET /goals`.
enum GoalListFilter {
  all,
  active,
  achieved,
  archived;

  String get wireName => enumWireName(this);
}

/// Savings goals (docs/03-API_CONTRACT.md §8). Writes are admin-only except
/// [contribute].
class GoalRepository {
  GoalRepository(this._api);

  final ApiClient _api;

  static const _goals = '/goals';

  /// `GET /goals?status=` — active goals first.
  Future<List<SavingsGoal>> listGoals({
    GoalListFilter status = GoalListFilter.all,
  }) async {
    final data = await _api.get(_goals, query: {'status': status.wireName});
    return List.unmodifiable(
      asMapList(requireList(data), SavingsGoal.fromJson),
    );
  }

  /// `POST /goals` (admin) → the created goal.
  Future<SavingsGoal> createGoal(GoalInput input) async {
    final data = await _api.post(_goals, body: input.toJson());
    return SavingsGoal.fromJson(requireObject(data));
  }

  /// `PATCH /goals/:id` (admin) → the updated goal (null when [patch] is
  /// empty and nothing was sent).
  Future<SavingsGoal?> updateGoal(String id, GoalPatch patch) async {
    if (patch.isEmpty) return null;
    final data = await _api.patch(
      '$_goals/${pathId(id)}',
      body: patch.toJson(),
    );
    return SavingsGoal.fromJson(requireObject(data));
  }

  /// `DELETE /goals/:id` (admin). Linked entries stay (their `goalId`
  /// becomes null).
  Future<void> deleteGoal(String id) async {
    await _api.delete('$_goals/${pathId(id)}');
  }

  /// `POST /goals/:id/contributions` → `{ goal, entry }`. Archived goals are
  /// rejected with `VALIDATION_ERROR`.
  Future<GoalContributionResult> contribute(
    String goalId,
    GoalContributionInput input,
  ) async {
    final data = await _api.post(
      '$_goals/${pathId(goalId)}/contributions',
      body: input.toJson(),
    );
    return GoalContributionResult(
      goal: SavingsGoal.fromJson(requireObject(data, 'goal')),
      entry: LedgerEntry.fromJson(requireObject(data, 'entry')),
    );
  }
}

final goalRepositoryProvider = Provider<GoalRepository>(
  (ref) => GoalRepository(ref.watch(apiClientProvider)),
);
