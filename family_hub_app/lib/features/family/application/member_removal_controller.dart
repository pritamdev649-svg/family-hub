import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/network/api_exception.dart';
import 'package:family_hub/features/family/application/family_providers.dart';
import 'package:family_hub/features/family/application/family_session_sync.dart';
import 'package:family_hub/shared/models/member.dart';
import 'package:family_hub/shared/session/session_controller.dart';

/// How [MemberRemovalController.remove] ended.
enum MemberRemovalOutcome {
  /// This request removed the member.
  removed,

  /// The member was already gone (`NOT_FOUND`: removed by another admin, or
  /// a retry after a lost response) — the wanted end state.
  alreadyRemoved,

  /// Another removal is still running; nothing was sent.
  busy,
}

/// Removes a member from the family (`DELETE /family/members/:id`, admin).
///
/// State is `AsyncLoading` while the request runs (the button shows its busy
/// state, repeated taps are ignored). Errors are rethrown (`LAST_ADMIN`,
/// `FORBIDDEN`) so the screen can show a localised message.
class MemberRemovalController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  bool get isBusy => state.isLoading;

  /// The server cascade deletes the member's pending tasks and emergency
  /// card and resolves their active SOS, so those scopes are refreshed too.
  /// A timeout / offline failure also refreshes them (the removal may have
  /// gone through; a retry then answers `NOT_FOUND` = already removed).
  Future<MemberRemovalOutcome> remove(Member member) async {
    if (state.isLoading) return MemberRemovalOutcome.busy;
    // Read up front: the screen may close while the request runs, but the
    // change must still be announced.
    final repo = ref.read(familyRepositoryProvider);
    final refresh = ref.read(dataRefreshProvider.notifier);
    final sync = ref.read(familySessionSyncProvider);
    state = const AsyncLoading();
    try {
      var outcome = MemberRemovalOutcome.removed;
      try {
        await repo.deleteMember(member.id);
      } on ApiException catch (e) {
        if (e.code != ApiErrorCode.notFound) rethrow;
        outcome = MemberRemovalOutcome.alreadyRemoved;
      }
      refresh.markChanged(memberRemovalScopes);
      if (ref.mounted) state = const AsyncData(null);
      return outcome;
    } catch (e, st) {
      // A lost answer may hide a completed removal (whole cascade); a
      // refusal only shows the member list was stale.
      sync.afterFailedMutation(
        e,
        ifStale: memberChangeScopes,
        ifUncertain: memberRemovalScopes,
      );
      if (ref.mounted) state = AsyncError(e, st);
      rethrow;
    }
  }
}

final memberRemovalControllerProvider =
    NotifierProvider.autoDispose<MemberRemovalController, AsyncValue<void>>(
      MemberRemovalController.new,
    );
