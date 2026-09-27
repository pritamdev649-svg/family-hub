import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;

import 'package:family_hub/core/providers/core_providers.dart';
import 'package:family_hub/shared/data/auth_repository.dart';
import 'package:family_hub/shared/data/family_repository.dart';
import 'package:family_hub/shared/data/me_repository.dart';
import 'package:family_hub/shared/models/member.dart';
import 'package:family_hub/shared/session/session_controller.dart';

// One import gives features the whole shared session API.
export 'package:family_hub/shared/providers/data_refresh.dart';
export 'package:family_hub/shared/session/session_controller.dart';

// ── Repositories ────────────────────────────────────────────────────────────

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    ref.watch(apiClientProvider),
    ref.watch(tokenStorageProvider),
  ),
);

final familyRepositoryProvider = Provider<FamilyRepository>(
  (ref) => FamilyRepository(ref.watch(apiClientProvider)),
);

final meRepositoryProvider = Provider<MeRepository>(
  (ref) => MeRepository(ref.watch(apiClientProvider)),
);

// ── Retry policy ────────────────────────────────────────────────────────────

/// Retry policy for API-backed providers (`FutureProvider(..., retry:
/// apiRetryPolicy)`).
///
/// Riverpod 3 retries every failing provider up to 10× by default and keeps
/// it in `AsyncLoading` meanwhile, so a `FORBIDDEN` / `NOT_FOUND` would show
/// a spinner for ~40 s. This policy retries only transient failures
/// (connection error, 5xx) twice with a short backoff and surfaces
/// everything else — including timeouts, which already waited long —
/// immediately, so `AsyncValueView` shows the error with a retry button.
Duration? apiRetryPolicy(int retryCount, Object error) {
  if (retryCount >= 2) return null;
  if (error is! ApiException) return null;
  final transient = error.code == ApiErrorCode.network || error.isServer;
  if (!transient) return null;
  return Duration(milliseconds: 600 * (1 << retryCount));
}

// ── Members ─────────────────────────────────────────────────────────────────

/// Members of the signed-in user's family (admins first, then oldest →
/// youngest). Empty when signed out / without a family. Refetches on account
/// or family switch and on `markChanged({DataScope.members})`.
final membersProvider = FutureProvider<List<Member>>((ref) async {
  final userId = ref.watch(sessionUserIdProvider);
  final familyId = ref.watch(currentFamilyProvider.select((f) => f?.id));
  ref.watch(dataRefreshProvider.select((m) => m[DataScope.members]));
  if (userId == null || familyId == null) return const <Member>[];
  return ref.watch(familyRepositoryProvider).getMembers();
}, retry: apiRetryPolicy);

/// One member by id. Served from [membersProvider] when present (no extra
/// request), else `GET /family/members/:id`. `NOT_FOUND` when signed out or
/// the member does not exist / belongs to another family.
final memberByIdProvider = FutureProvider.family<Member, String>((
  ref,
  id,
) async {
  final userId = ref.watch(sessionUserIdProvider);
  ref.watch(dataRefreshProvider.select((m) => m[DataScope.members]));
  if (userId == null || id.trim().isEmpty) {
    throw const ApiException(code: ApiErrorCode.notFound, statusCode: 404);
  }
  final List<Member> members;
  try {
    members = await ref.watch(membersProvider.future);
  } on ProviderException catch (e) {
    // Surface the real ApiException so screens show a proper message.
    Error.throwWithStackTrace(e.exception, e.stackTrace);
  }
  for (final m in members) {
    if (m.id == id) return m;
  }
  return ref.watch(familyRepositoryProvider).getMember(id);
}, retry: apiRetryPolicy);
