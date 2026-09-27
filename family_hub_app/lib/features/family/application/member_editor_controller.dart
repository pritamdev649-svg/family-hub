import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/features/family/application/family_providers.dart';
import 'package:family_hub/features/family/application/family_session_sync.dart';
import 'package:family_hub/features/family/domain/member_form_data.dart';
import 'package:family_hub/shared/data/family_repository.dart';
import 'package:family_hub/shared/data/repository_utils.dart';
import 'package:family_hub/shared/models/member.dart';
import 'package:family_hub/shared/session/session_controller.dart';

/// Outcome of [MemberEditorController.add].
@immutable
class AddMemberResult {
  const AddMemberResult({required this.member, this.avatarSaved = true});

  final Member member;

  /// `false` when the member was created but saving the picked photo failed
  /// (the member exists — the form must not be submitted again).
  final bool avatarSaved;
}

/// Add / edit mutations of the member form.
///
/// State is the last mutation: `AsyncLoading` while a request runs (the
/// form shows its busy button and a second submit is ignored), `AsyncError`
/// after a failure, `AsyncData` otherwise. Methods rethrow the
/// `ApiException` so the screen can show a localised error.
///
/// After a failure the member list is refetched when the answer shows it was
/// stale (`NOT_FOUND`, `LAST_ADMIN`, `MEMBER_EMAIL_EXISTS`) or when the
/// outcome is unknown (offline / timeout / 5xx: the server may have saved
/// it), and `FORBIDDEN` / `NO_FAMILY` resync the session (see
/// [FamilySessionSync.afterFailedMutation]).
class MemberEditorController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  bool get isBusy => state.isLoading;

  /// `POST /family/members`, then saves the photo (not part of the add body
  /// in the contract) with `PATCH`. Returns `null` when a mutation is
  /// already running. [consentRequired] records the guardian consent even
  /// when the local rule says it is not needed (the server answered
  /// `GUARDIAN_CONSENT_REQUIRED`). Errors: `GUARDIAN_CONSENT_REQUIRED`,
  /// `MEMBER_EMAIL_EXISTS`, `VALIDATION_ERROR`, `FORBIDDEN`.
  Future<AddMemberResult?> add(
    MemberFormData data, {
    bool consentRequired = false,
  }) {
    // Read collaborators up front: the screen may close (and dispose this
    // controller) while the request runs, but the change must still be
    // announced.
    final repo = _repo;
    final refresh = ref.read(dataRefreshProvider.notifier);
    final country = ref.read(currentCountryProvider);
    return _run(memberChangeScopes, () async {
      var member = await repo.addMember(
        data.toNewMemberRequest(country, consentRequired: consentRequired),
      );
      var avatarSaved = true;
      final avatarUrl = trimOrNull(data.avatarUrl);
      if (avatarUrl != null) {
        try {
          member = await repo.updateMember(
            member.id,
            MemberPatch(avatarUrl: avatarUrl),
          );
        } catch (e) {
          debugPrint('MemberEditorController: photo not saved ($e)');
          avatarSaved = false;
        }
      }
      refresh.markChanged(memberChangeScopes);
      return AddMemberResult(member: member, avatarSaved: avatarSaved);
    });
  }

  /// `PATCH /family/members/:id` with the changes [access] may make.
  /// Returns [before] unchanged without a request when nothing changed,
  /// `null` when a mutation is already running. When the signed-in member
  /// edited themselves the session is updated too.
  /// Errors: `FORBIDDEN`, `LAST_ADMIN`, `MEMBER_EMAIL_EXISTS`,
  /// `VALIDATION_ERROR`, `NOT_FOUND`.
  Future<Member?> update(
    Member before,
    MemberFormData data,
    MemberFormAccess access, {
    bool consentRequired = false,
  }) {
    final patch = data.toPatch(
      before,
      access,
      ref.read(currentCountryProvider),
      consentRequired: consentRequired,
    );
    if (patch.isEmpty && !state.isLoading) return Future.value(before);
    final repo = _repo;
    final refresh = ref.read(dataRefreshProvider.notifier);
    final session = ref.read(sessionControllerProvider.notifier);
    final myMemberId = ref.read(currentMemberProvider)?.id;
    return _run(memberChangeScopes, () async {
      final updated = await repo.updateMember(before.id, patch);
      if (updated.id == myMemberId) {
        // Keeps the session's own member (name, photo…) in sync.
        await session.applyMe(null, updated);
      }
      final identityChanged =
          patch.fields.containsKey('name') ||
          patch.fields.containsKey('avatarUrl');
      refresh.markChanged({
        ...memberChangeScopes,
        if (identityChanged) ...memberIdentityScopes,
      });
      return updated;
    });
  }

  FamilyRepository get _repo => ref.read(familyRepositoryProvider);

  Future<T?> _run<T>(
    Set<DataScope> scopesOnFailure,
    Future<T> Function() action,
  ) async {
    if (state.isLoading) return null;
    final sync = ref.read(familySessionSyncProvider);
    state = const AsyncLoading();
    try {
      final result = await action();
      if (ref.mounted) state = const AsyncData(null);
      return result;
    } catch (e, st) {
      sync.afterFailedMutation(e, ifStale: scopesOnFailure);
      if (ref.mounted) state = AsyncError(e, st);
      rethrow;
    }
  }
}

final memberEditorControllerProvider =
    NotifierProvider.autoDispose<MemberEditorController, AsyncValue<void>>(
      MemberEditorController.new,
    );
