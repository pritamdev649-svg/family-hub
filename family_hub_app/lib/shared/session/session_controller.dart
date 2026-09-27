import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/config/countries.dart';
import 'package:family_hub/core/providers/core_providers.dart';
import 'package:family_hub/core/services/push_notification_service.dart';
import 'package:family_hub/shared/data/auth_repository.dart';
import 'package:family_hub/shared/data/family_repository.dart';
import 'package:family_hub/shared/data/me_repository.dart';
import 'package:family_hub/shared/json.dart';
import 'package:family_hub/shared/models/auth_user.dart';
import 'package:family_hub/shared/models/family.dart';
import 'package:family_hub/shared/models/member.dart';
import 'package:family_hub/shared/models/session_state.dart';
import 'package:family_hub/shared/providers/shared_providers.dart';

// One import gives features the whole shared session API.
export 'package:family_hub/shared/providers/shared_providers.dart';

/// Owns "who is signed in" (docs/05-FLUTTER_GUIDE.md §8).
///
/// * `build()` restores the session: stored tokens → `GET /auth/me`. On a
///   network / server failure the last session cached under [cacheKey] is
///   used so the app opens offline (and `/auth/me` is retried in the
///   background); `401` → signed out. Without tokens → signed out.
/// * Actions never put the state into `AsyncLoading` (the router would flash
///   the splash). Screens own their busy state; actions set `AsyncData` on
///   success and rethrow the `ApiException` on failure.
/// * After every successful sign-in / online restore the device is registered
///   for pushes (fire-and-forget); logout unregisters it **before** the
///   tokens are cleared.
class SessionController extends AsyncNotifier<SessionState> {
  /// `LocalCache` key of the last known session (used for offline start).
  static const cacheKey = 'session.last';

  /// Background `/auth/me` retries after an offline restore.
  static const _backgroundRefreshDelays = [
    Duration(seconds: 10),
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 2),
    Duration(minutes: 5),
  ];

  Timer? _refreshTimer;
  int _refreshAttempt = 0;

  /// Incremented whenever the signed-in identity changes (sign-in, sign-out)
  /// so late results of background work for an old session are dropped.
  int _epoch = 0;
  bool _signingOut = false;
  bool _pushRegistered = false;

  /// Pending push unregistration; a following registration waits for it so
  /// the new account's token is not deleted by the old account's cleanup.
  Future<void>? _pushCleanup;

  AuthRepository get _auth => ref.read(authRepositoryProvider);
  FamilyRepository get _family => ref.read(familyRepositoryProvider);
  MeRepository get _me => ref.read(meRepositoryProvider);
  LocalCache get _cache => ref.read(localCacheProvider);

  /// Current session (never `null`: signed out while loading / on error).
  SessionState get _current => state.value ?? SessionState.signedOut;

  @override
  Future<SessionState> build() async {
    final sub = ref
        .read(authEventsProvider)
        .sessionExpired
        .listen((_) => unawaited(handleSessionExpired()));
    ref.onDispose(() {
      sub.cancel();
      _cancelBackgroundRefresh();
    });
    return _restore();
  }

  // ── Restore ──────────────────────────────────────────────────────────────

  Future<SessionState> _restore() async {
    final auth = _auth;
    final cache = _cache;
    if (!await auth.hasTokens()) {
      await cache.remove(cacheKey);
      return SessionState.signedOut;
    }
    try {
      final session = await auth.me();
      await _persist(cache, session);
      _registerPush();
      return session;
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        await auth.clearTokens();
        await cache.clear();
        return SessionState.signedOut;
      }
      final cached = _readCachedSession(cache);
      if (cached != null) {
        debugPrint('SessionController: offline restore ($e)');
        _scheduleBackgroundRefresh();
        return cached;
      }
      // No cached session: transient errors are retried by
      // [_sessionRetryPolicy] (state stays AsyncLoading → splash); after that
      // the AsyncError makes the router treat the user as signed out. The
      // tokens are kept, so the next start / login can still succeed.
      rethrow;
    }
  }

  // ── Sign in / sign up ────────────────────────────────────────────────────

  /// `POST /auth/login`, then `GET /auth/me` for the member / family.
  /// Errors: `INVALID_CREDENTIALS`, `TOO_MANY_REQUESTS`, network errors.
  Future<void> login({required String email, required String password}) async {
    final auth = _auth;
    final result = await auth.login(email: email, password: password);
    await _signIn(await _completeSession(auth, result));
  }

  /// `POST /auth/register` (create or join mode). The response already
  /// contains member + family. Errors: `EMAIL_TAKEN`, `INVALID_INVITE_CODE`,
  /// `VALIDATION_ERROR`.
  Future<void> register(RegisterRequest request) async {
    final auth = _auth;
    final result = await auth.register(request);
    await _signIn(await _completeSession(auth, result));
  }

  /// Login returns only `{ user, tokens }`; fetch member / family when the
  /// user belongs to a family. If that fails the stored tokens are dropped
  /// so the app never ends up half signed in.
  Future<SessionState> _completeSession(
    AuthRepository auth,
    AuthResult result,
  ) async {
    if (result.hasMembership || !result.user.hasFamily) return result.session;
    try {
      final session = await auth.me();
      return session.user?.id == result.user.id ? session : result.session;
    } catch (_) {
      await auth.clearTokens();
      rethrow;
    }
  }

  Future<void> _signIn(SessionState session) async {
    _epoch++;
    _cancelBackgroundRefresh();
    _pushRegistered = false;
    final previousUserId = _current.user?.id;
    final cache = _cache;
    if (previousUserId != null && previousUserId != session.user?.id) {
      await cache.clear(); // never show the previous account's cached data
    }
    await _persist(cache, session);
    if (!ref.mounted) return;
    state = AsyncData(session);
    _registerPush();
  }

  // ── Email verification ───────────────────────────────────────────────────

  /// `POST /auth/verify-email`. Errors: `INVALID_OTP`, `OTP_EXPIRED`.
  Future<void> verifyEmail(String otp) async {
    final user = await _auth.verifyEmail(otp);
    await _update(
      (s) => s.user?.id == user.id ? s.copyWith(user: () => user) : s,
    );
  }

  /// `POST /auth/resend-verification` → seconds until the next resend is
  /// allowed. Errors: `TOO_MANY_REQUESTS` (see `retryAfterSeconds`).
  Future<int> resendVerification() => _auth.resendVerification();

  // ── Family membership ────────────────────────────────────────────────────

  /// `POST /family` for a signed-in user without a family.
  /// Errors: `ALREADY_IN_FAMILY`, `VALIDATION_ERROR`.
  Future<void> createFamily(CreateFamilyRequest request) async {
    final session = await _family.createFamily(request);
    await _update((s) => s.user?.id == session.user?.id ? session : s);
  }

  /// `POST /family/join`. Errors: `INVALID_INVITE_CODE`, `ALREADY_IN_FAMILY`.
  Future<void> joinFamily(String inviteCode) async {
    final session = await _family.joinFamily(inviteCode);
    await _update((s) => s.user?.id == session.user?.id ? session : s);
  }

  /// `POST /me/leave-family` → the session keeps the user without a family
  /// (router shows family setup). Errors: `LAST_ADMIN`.
  Future<void> leaveFamily() async {
    final user = await _me.leaveFamily();
    await _update((s) => s.user?.id == user.id ? SessionState(user: user) : s);
  }

  /// Merges fresh server objects about the signed-in user into the session,
  /// e.g. after `PATCH /me` (`applyMe(res.user, res.member)`), after an admin
  /// edits their own member record (`applyMe(null, member)`) or after
  /// `PATCH /family` (`applyMe(null, null, family)`). Objects that do not
  /// belong to the current session are ignored. Changes of the member /
  /// family also bump the matching [DataScope]s.
  Future<void> applyMe([AuthUser? user, Member? member, Family? family]) async {
    await _update((s) {
      final current = s.user;
      if (current == null) return s;
      var next = s;
      if (user != null && user.id == current.id) {
        next = next.copyWith(user: () => user);
      }
      final memberId = next.member?.id ?? next.user?.memberId;
      if (member != null && member.id == memberId) {
        next = next.copyWith(member: () => member);
      }
      final familyId = next.family?.id ?? next.user?.familyId;
      if (family != null && family.id == familyId) {
        next = next.copyWith(family: () => family);
      }
      return next;
    });
  }

  // ── Refresh ──────────────────────────────────────────────────────────────

  /// Re-reads `GET /auth/me` (pull-to-refresh, app resume, after an offline
  /// start). `401` signs out locally; other errors are rethrown and keep the
  /// current session.
  Future<void> refreshMe() async {
    if (!_current.isSignedIn) return;
    final epoch = _epoch;
    final auth = _auth;
    final SessionState session;
    try {
      session = await auth.me();
    } on ApiException catch (e) {
      if (e.isUnauthorized && epoch == _epoch) {
        await handleSessionExpired();
        return;
      }
      rethrow;
    }
    if (!ref.mounted || epoch != _epoch) return;
    _cancelBackgroundRefresh();
    if (session.user?.id != _current.user?.id) {
      await _signIn(session); // server says: different account
      return;
    }
    await _update((_) => session);
    _registerPush();
  }

  // ── Sign out ─────────────────────────────────────────────────────────────

  /// Unregisters the device (while still authenticated), revokes the refresh
  /// token (`POST /auth/logout`, best effort), clears tokens and cached data
  /// and switches to signed out. Never throws.
  Future<void> logout() async {
    if (_signingOut) return;
    _signingOut = true;
    _beginSignOut();
    final auth = _auth;
    final cache = _cache;
    try {
      await _unregisterPush();
      await auth.logout(); // best effort; always clears the tokens
      await cache.clear();
    } catch (e) {
      debugPrint('SessionController.logout: cleanup failed ($e)');
      await auth.clearTokens();
    } finally {
      _signingOut = false;
      if (ref.mounted) state = const AsyncData(SessionState.signedOut);
    }
  }

  /// `DELETE /me` (with password confirmation), then signs out locally.
  /// Errors: `INVALID_CREDENTIALS`, `LAST_ADMIN`.
  Future<void> deleteAccount(String password) async {
    await _me.deleteAccount(password);
    if (_signingOut) return;
    _signingOut = true;
    _beginSignOut();
    final auth = _auth;
    final cache = _cache;
    if (ref.mounted) state = const AsyncData(SessionState.signedOut);
    try {
      await auth.clearTokens();
      await cache.clear();
      await _unregisterPush(); // server removed the devices; drop the token
    } finally {
      _signingOut = false;
    }
  }

  /// Called when the refresh token is rejected (the auth interceptor already
  /// cleared the tokens and emitted `AuthEvents.sessionExpired`) or when
  /// `/auth/me` answers 401. Switches to signed out **first** so the router
  /// shows the login screen, then cleans up. Idempotent.
  Future<void> handleSessionExpired() async {
    if (_signingOut || !_current.isSignedIn) return;
    _signingOut = true;
    _beginSignOut();
    final auth = _auth;
    final cache = _cache;
    if (ref.mounted) state = const AsyncData(SessionState.signedOut);
    try {
      await auth.clearTokens();
      await cache.clear();
    } finally {
      _signingOut = false;
    }
    // Stop this account's pushes on this phone (deletes the FCM token).
    unawaited(_unregisterPush());
  }

  void _beginSignOut() {
    _epoch++;
    _cancelBackgroundRefresh();
    _pushRegistered = false;
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// Applies [change] to the current signed-in session, persists it and
  /// bumps data scopes when the member / family changed. No-op when signed
  /// out or unchanged.
  Future<void> _update(SessionState Function(SessionState s) change) async {
    final current = _current;
    if (!current.isSignedIn || !ref.mounted) return;
    final next = change(current);
    if (next == current) return;
    state = AsyncData(next);
    final scopes = <DataScope>{
      if (next.family?.id != current.family?.id) ...DataScope.values,
      if (next.family != current.family) DataScope.family,
      if (next.member != current.member) DataScope.members,
    };
    if (scopes.isNotEmpty) markChanged(ref, scopes);
    await _persist(_cache, next);
  }

  /// Caches the session for offline start. The member's last location is
  /// never written to disk.
  static Future<void> _persist(LocalCache cache, SessionState session) async {
    if (!session.isSignedIn) {
      await cache.remove(cacheKey);
      return;
    }
    final member = session.member;
    final safe = member?.lastLocation == null
        ? session
        : session.copyWith(
            member: () => member?.copyWith(lastLocation: () => null),
          );
    await cache.write(cacheKey, safe.toJson());
  }

  static SessionState? _readCachedSession(LocalCache cache) {
    final session = cache.read(
      cacheKey,
      (json) => SessionState.fromJson(asMap(json)),
    );
    return session != null && session.isSignedIn ? session : null;
  }

  void _scheduleBackgroundRefresh() {
    _refreshTimer?.cancel();
    if (_refreshAttempt >= _backgroundRefreshDelays.length) return;
    final delay = _backgroundRefreshDelays[_refreshAttempt++];
    _refreshTimer = Timer(delay, () async {
      _refreshTimer = null;
      if (!ref.mounted) return;
      try {
        await refreshMe();
      } on ApiException catch (e) {
        if (e.isNetwork || e.isServer) _scheduleBackgroundRefresh();
      } catch (e) {
        debugPrint('SessionController: background refresh failed ($e)');
      }
    });
  }

  void _cancelBackgroundRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _refreshAttempt = 0;
  }

  PushNotificationService? _push() {
    try {
      return ref.read(pushNotificationServiceProvider);
    } catch (e) {
      debugPrint('SessionController: push unavailable ($e)');
      return null;
    }
  }

  /// Registers this device for pushes once per signed-in session
  /// (fire-and-forget, errors ignored).
  void _registerPush() {
    if (_pushRegistered) return;
    final push = _push();
    if (push == null) return;
    _pushRegistered = true;
    final pending = _pushCleanup ?? Future<void>.value();
    unawaited(
      pending.then((_) => push.registerDevice()).catchError((Object e) {
        debugPrint('SessionController: push registration failed ($e)');
      }),
    );
  }

  /// Unregisters this device (time-boxed by the service, never throws).
  Future<void> _unregisterPush() {
    final push = _push();
    if (push == null) return Future<void>.value();
    late final Future<void> cleanup;
    cleanup = push
        .unregisterDevice()
        .catchError((Object e) {
          debugPrint('SessionController: push unregistration failed ($e)');
        })
        .whenComplete(() {
          if (identical(_pushCleanup, cleanup)) _pushCleanup = null;
        });
    _pushCleanup = cleanup;
    return cleanup;
  }
}

/// Transient restore failures (offline without a cached session, 5xx) are
/// retried with backoff while the splash is shown; anything else surfaces
/// as `AsyncError` immediately.
Duration? _sessionRetryPolicy(int retryCount, Object error) {
  if (retryCount >= 6) return null;
  if (error is! ApiException || !(error.isNetwork || error.isServer)) {
    return null;
  }
  final seconds = 1 << retryCount; // 1, 2, 4, 8, 16, 32
  return Duration(seconds: seconds > 30 ? 30 : seconds);
}

final sessionControllerProvider =
    AsyncNotifierProvider<SessionController, SessionState>(
      SessionController.new,
      retry: _sessionRetryPolicy,
    );

// ── Derived providers ───────────────────────────────────────────────────────

/// The signed-in account (`null` when signed out / restoring).
final currentUserProvider = Provider<AuthUser?>(
  (ref) => ref.watch(sessionControllerProvider.select((s) => s.value?.user)),
);

/// The signed-in user's member record (`null` without a family).
final currentMemberProvider = Provider<Member?>(
  (ref) => ref.watch(sessionControllerProvider.select((s) => s.value?.member)),
);

/// The signed-in user's family (`null` without a family).
final currentFamilyProvider = Provider<Family?>(
  (ref) => ref.watch(sessionControllerProvider.select((s) => s.value?.family)),
);

/// Whether the current member is a family admin (UI mirror of the backend
/// permission checks — always handle `FORBIDDEN` anyway).
final isAdminProvider = Provider<bool>(
  (ref) => ref.watch(
    sessionControllerProvider.select((s) => s.value?.isAdmin ?? false),
  ),
);

/// Country defaults of the family (emergency number, consent age …);
/// [Countries.fallback] without a family.
final currentCountryProvider = Provider<CountryInfo>(
  (ref) => Countries.byCode(
    ref.watch(currentFamilyProvider.select((f) => f?.country)),
  ),
);

/// Id of the signed-in user. **Every feature data provider watches this** so
/// its data resets on logout / account switch.
final sessionUserIdProvider = Provider<String?>(
  (ref) => ref.watch(currentUserProvider.select((u) => u?.id)),
);
