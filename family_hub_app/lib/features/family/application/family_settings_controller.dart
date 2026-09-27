import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/features/family/application/family_session_sync.dart';
import 'package:family_hub/shared/data/family_repository.dart';
import 'package:family_hub/shared/models/family.dart';
import 'package:family_hub/shared/session/session_controller.dart';

/// The family-settings mutation in flight.
enum FamilySettingsAction { save, regenerateInviteCode }

/// Admin mutations of the family settings screen: `PATCH /family` and
/// `POST /family/invite-code`.
///
/// State is the action currently running (`null` = idle), so each button
/// shows its own busy state and no second action starts meanwhile. Methods
/// return `null` when another action is already running and rethrow the
/// `ApiException` on failure (`FORBIDDEN`, `VALIDATION_ERROR`). After a
/// failure the family is refetched when the outcome is unknown (offline /
/// timeout: a new invite code may already be active) and `FORBIDDEN`
/// resyncs the session (demoted on another phone).
class FamilySettingsController extends Notifier<FamilySettingsAction?> {
  @override
  FamilySettingsAction? build() => null;

  bool get isBusy => state != null;

  /// Saves the fields that differ from [before]. Without changes no request
  /// is made and [before] is returned.
  Future<Family?> save(
    Family before, {
    String? name,
    String? country,
    String? currency,
    String? timezone,
  }) async {
    if (isBusy) return null;
    final patch = FamilyPatch.diff(
      before,
      name: name,
      country: country,
      currency: currency,
      timezone: timezone,
    );
    if (patch.isEmpty) return before;
    return _run(
      FamilySettingsAction.save,
      (repo) => repo.updateFamily(patch),
      scopesForPatch(patch),
    );
  }

  /// Creates a new invite code; the old one stops working immediately.
  Future<Family?> regenerateInviteCode() => _run(
    FamilySettingsAction.regenerateInviteCode,
    (repo) => repo.regenerateInviteCode(),
    const {DataScope.family},
  );

  /// Data to refresh after [patch]: money is shown in the family currency,
  /// and "today", "this week" and month ranges follow the family time zone.
  static Set<DataScope> scopesForPatch(FamilyPatch patch) {
    final fields = patch.fields;
    final money =
        fields.containsKey('currency') || fields.containsKey('timezone');
    return {
      DataScope.family,
      if (money) ...{DataScope.ledger, DataScope.goals},
      if (fields.containsKey('timezone')) DataScope.tasks,
    };
  }

  Future<Family?> _run(
    FamilySettingsAction action,
    Future<Family> Function(FamilyRepository repo) request,
    Set<DataScope> scopes,
  ) async {
    if (isBusy) return null;
    state = action;
    // Read up front: the screen may close while the request runs, but the
    // change must still reach the session and the other screens.
    final repo = ref.read(familyRepositoryProvider);
    final session = ref.read(sessionControllerProvider.notifier);
    final refresh = ref.read(dataRefreshProvider.notifier);
    final sync = ref.read(familySessionSyncProvider);
    try {
      final family = await request(repo);
      // Updates the session copy (currency / country used by `Fmt`, the
      // consent age, the invite code …).
      await session.applyMe(null, null, family);
      refresh.markChanged(scopes);
      return family;
    } catch (e) {
      sync.afterFailedMutation(e, ifStale: const {DataScope.family});
      rethrow;
    } finally {
      if (ref.mounted) state = null;
    }
  }
}

final familySettingsControllerProvider =
    NotifierProvider.autoDispose<
      FamilySettingsController,
      FamilySettingsAction?
    >(FamilySettingsController.new);
