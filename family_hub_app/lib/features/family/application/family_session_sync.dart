import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/l10n/error_messages.dart'
    show unwrapProviderError;
import 'package:family_hub/core/network/api_exception.dart';
import 'package:family_hub/features/family/application/family_providers.dart';
import 'package:family_hub/shared/models/family.dart';
import 'package:family_hub/shared/models/member.dart';
import 'package:family_hub/shared/session/session_controller.dart';

/// Keeps the session in step with what the `/family` endpoints report, so
/// permission and membership changes made on another phone reach every
/// screen (and the router) while a family screen is open:
///
/// * the signed-in member as listed by `GET /family/members` (e.g. demoted
///   from admin, renamed by an admin) is merged into the session, so
///   `isAdminProvider` and the admin-only actions follow at once;
/// * a fresher `GET /family` (currency, country, invite code) is merged too;
/// * `NO_FAMILY` / `FORBIDDEN` answers re-read `GET /auth/me` (removed from
///   the family → family setup; lost admin rights → member UI);
/// * after a failed mutation whose answer shows that the screen was out of
///   date (`NOT_FOUND`, `LAST_ADMIN`, `MEMBER_EMAIL_EXISTS`) or whose outcome
///   is unknown (offline, timeout, 5xx — the server may have applied it),
///   the affected data is refetched.
///
/// Session updates run in a microtask, never while providers notify.
class FamilySessionSync {
  FamilySessionSync(this._ref);

  final Ref _ref;
  bool _resyncing = false;

  /// Answers meaning the session itself is out of date.
  static const staleSessionCodes = {
    ApiErrorCode.noFamily,
    ApiErrorCode.forbidden,
  };

  /// Answers meaning the data shown on screen is out of date.
  static const staleDataCodes = {
    ...staleSessionCodes,
    ApiErrorCode.notFound,
    ApiErrorCode.lastAdmin,
    ApiErrorCode.memberEmailExists,
  };

  /// Re-reads the session in the background when [error] shows that it no
  /// longer matches the server. Concurrent calls share one refresh. Never
  /// throws.
  void resyncIfStale(Object? error) {
    final e = error == null ? null : unwrapProviderError(error);
    if (e is! ApiException || !staleSessionCodes.contains(e.code)) return;
    if (_resyncing) return;
    _resyncing = true;
    final session = _ref.read(sessionControllerProvider.notifier);
    unawaited(
      Future<void>(session.refreshMe)
          .catchError((Object e) {
            debugPrint('FamilySessionSync: session refresh failed ($e)');
          })
          .whenComplete(() => _resyncing = false),
    );
  }

  /// After a failed mutation: refetches [ifStale] when the answer shows
  /// that the screen was out of date, [ifUncertain] (default [ifStale]) when
  /// the outcome is unknown (the server may have applied the change), and
  /// resyncs the session on `NO_FAMILY` / `FORBIDDEN`. Never throws.
  void afterFailedMutation(
    Object error, {
    required Set<DataScope> ifStale,
    Set<DataScope>? ifUncertain,
  }) {
    final e = unwrapProviderError(error);
    if (e is! ApiException) return;
    if (e.isNetwork || e.isServer) {
      markChanged(_ref, ifUncertain ?? ifStale);
    } else if (staleDataCodes.contains(e.code)) {
      markChanged(_ref, ifStale);
    }
    resyncIfStale(e);
  }

  /// Merges the signed-in member from a fresh member list into the session
  /// when something the app relies on (role, name, photo …) differs. A list
  /// without the signed-in member means they were removed → resync.
  void syncSelf(List<Member> members) {
    _later('member', () async {
      final me = _ref.read(currentMemberProvider);
      if (me == null) return;
      Member? fresh;
      for (final m in members) {
        if (m.id == me.id) fresh = m;
      }
      if (fresh == null) {
        resyncIfStale(const ApiException(code: ApiErrorCode.noFamily));
      } else if (!sameMemberDetails(fresh, me)) {
        await _ref
            .read(sessionControllerProvider.notifier)
            .applyMe(null, fresh);
      }
    });
  }

  /// Merges a fresh `GET /family` into the session when it differs.
  void syncFamily(Family family) {
    _later('family', () async {
      final current = _ref.read(currentFamilyProvider);
      if (current == null || current.id != family.id || current == family) {
        return;
      }
      await _ref
          .read(sessionControllerProvider.notifier)
          .applyMe(null, null, family);
    });
  }

  /// Runs [action] in a microtask (outside provider notifications); errors
  /// are logged, never thrown.
  void _later(String what, Future<void> Function() action) {
    unawaited(
      Future<void>.microtask(action).catchError((Object e) {
        debugPrint('FamilySessionSync: $what sync failed ($e)');
      }),
    );
  }

  /// Whether [a] and [b] agree on everything but the volatile location
  /// fields (`lastLocation` / `updatedAt` change with every location
  /// update; they are no reason to rewrite the session).
  @visibleForTesting
  static bool sameMemberDetails(Member a, Member b) {
    Member stable(Member m) =>
        m.copyWith(lastLocation: () => null, updatedAt: () => null);
    return stable(a) == stable(b);
  }
}

final familySessionSyncProvider = Provider<FamilySessionSync>(
  FamilySessionSync.new,
);

/// Wires a family screen to [FamilySessionSync]. Call from `build`.
extension FamilySessionSyncRefX on WidgetRef {
  /// Listens to the member list ([members]) and / or `GET /family`
  /// ([family]) the screen shows and keeps the session in step with them.
  void syncFamilySession({bool members = true, bool family = false}) {
    final sync = read(familySessionSyncProvider);
    if (members) {
      listen<AsyncValue<List<Member>>>(membersProvider, (_, next) {
        if (next.isLoading) return;
        if (next.hasError) {
          sync.resyncIfStale(next.error);
        } else if (next.value case final list? when list.isNotEmpty) {
          sync.syncSelf(list);
        }
      });
    }
    if (family) {
      listen<AsyncValue<Family?>>(familyProvider, (_, next) {
        if (next.isLoading) return;
        if (next.hasError) {
          sync.resyncIfStale(next.error);
        } else if (next.value case final fresh?) {
          sync.syncFamily(fresh);
        }
      });
    }
  }
}
