import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/l10n/error_messages.dart'
    show unwrapProviderError;
import 'package:family_hub/core/network/api_exception.dart';
import 'package:family_hub/shared/models/family.dart';
import 'package:family_hub/shared/models/member.dart';
import 'package:family_hub/shared/session/session_controller.dart';

/// Fresh `GET /family` for the settings screen (the session copy may be
/// stale, e.g. `memberCount` or a change made on another device). `null`
/// when signed out / without a family. Refetches on account or family
/// switch, on `markChanged({DataScope.family})` and when the caller's role
/// changes (the invite code is only returned to admins).
final familyProvider = FutureProvider<Family?>((ref) async {
  final userId = ref.watch(sessionUserIdProvider);
  final familyId = ref.watch(currentFamilyProvider.select((f) => f?.id));
  ref.watch(isAdminProvider);
  ref.watch(dataRefreshProvider.select((m) => m[DataScope.family]));
  if (userId == null || familyId == null) return null;
  return ref.watch(familyRepositoryProvider).getFamily();
}, retry: apiRetryPolicy);

/// Scopes announced after adding, editing or removing a member: the member
/// list and the family (`memberCount`).
const memberChangeScopes = <DataScope>{DataScope.members, DataScope.family};

/// Extra scopes when a member's name or photo changed: other features show
/// denormalised names / avatars (task assignees, notice authors, SOS).
const memberIdentityScopes = <DataScope>{
  DataScope.tasks,
  DataScope.notices,
  DataScope.sos,
};

/// Everything the member-removal cascade touches: pending tasks, the
/// emergency card and active SOS alerts are deleted / resolved.
const memberRemovalScopes = <DataScope>{
  ...memberChangeScopes,
  DataScope.tasks,
  DataScope.emergencyCards,
  DataScope.sos,
};

/// Whether [error] means the requested member does not exist (any more):
/// `NOT_FOUND` (deleted, or another family's id) or `BAD_REQUEST` (a
/// malformed id, e.g. from an old or mistyped link).
bool isMemberGoneError(Object? error) {
  if (error == null) return false;
  final e = unwrapProviderError(error);
  return e is ApiException &&
      (e.code == ApiErrorCode.notFound || e.code == ApiErrorCode.badRequest);
}

/// A member lookup (`memberByIdProvider`) where "this member no longer
/// exists" is data (`null`) instead of an error, so screens show a
/// dedicated state rather than "something went wrong" with a retry that can
/// never succeed — also when the member is removed while the screen is open
/// (a refresh answering `NOT_FOUND` replaces the stale member).
AsyncValue<Member?> memberOrGone(AsyncValue<Member> value) =>
    isMemberGoneError(value.error) ? const AsyncData<Member?>(null) : value;
