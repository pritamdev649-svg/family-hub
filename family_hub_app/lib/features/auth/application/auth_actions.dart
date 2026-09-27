import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/network/api_exception.dart';
import 'package:family_hub/features/auth/application/auth_cooldown.dart';
import 'package:family_hub/features/auth/application/session_expired_notice.dart';
import 'package:family_hub/shared/data/auth_repository.dart';
import 'package:family_hub/shared/data/family_repository.dart';
import 'package:family_hub/shared/session/session_controller.dart';

/// The auth screens' mutations. Thin wrappers around [SessionController]
/// that add the auth-flow bookkeeping screens must not forget:
///
/// * cooldowns (login lockout from `429`, the verification-code resend
///   timer, which also starts right after sign-up because register already
///   sent the first code);
/// * data-change notifications after family membership changes.
///
/// Lives in a provider (not in a screen) so the bookkeeping still happens
/// when the router replaces the screen the moment the session changes.
/// Errors are rethrown unchanged for the screen to show.
class AuthActions {
  AuthActions(this._ref);

  final Ref _ref;

  SessionController get _session =>
      _ref.read(sessionControllerProvider.notifier);

  AuthCooldown _cooldown(AuthCooldownKey key) =>
      _ref.read(authCooldownProvider(key).notifier);

  /// Remaining lockout for [email] in seconds (0 = may try).
  int loginLockSeconds(String email) =>
      _cooldown(AuthCooldownKeys.login(email)).secondsLeft;

  /// `POST /auth/login`. `429` starts the lockout cooldown for [email];
  /// success clears it. Errors: `INVALID_CREDENTIALS`, `TOO_MANY_REQUESTS`.
  Future<void> login({required String email, required String password}) async {
    final key = AuthCooldownKeys.login(email);
    try {
      await _session.login(email: email, password: password);
      _cooldown(key).clear();
      _signedIn();
    } on ApiException catch (e) {
      if (e.code == ApiErrorCode.tooManyRequests) {
        _cooldown(key).start(
          e.retryAfterSeconds ?? AuthCooldownDefaults.tooManyRequestsSeconds,
        );
      }
      rethrow;
    }
  }

  /// `POST /auth/register`. The server sent the first verification code, so
  /// the resend cooldown starts now. Errors: `EMAIL_TAKEN`,
  /// `INVALID_INVITE_CODE`, `VALIDATION_ERROR`.
  Future<void> register(RegisterRequest request) async {
    await _session.register(request);
    _signedIn();
    final userId = _ref.read(sessionUserIdProvider);
    if (userId != null) {
      _cooldown(
        AuthCooldownKeys.verifyEmail(userId),
      ).start(AuthCooldownDefaults.resendSeconds);
    }
    markChanged(_ref, {DataScope.family, DataScope.members});
  }

  /// `POST /auth/verify-email`. Errors: `INVALID_OTP`, `OTP_EXPIRED`.
  Future<void> verifyEmail(String otp) => _session.verifyEmail(otp);

  /// Seconds until the signed-in user may request another code.
  int verificationCooldownSeconds() {
    final userId = _ref.read(sessionUserIdProvider);
    if (userId == null) return 0;
    return _cooldown(AuthCooldownKeys.verifyEmail(userId)).secondsLeft;
  }

  /// `POST /auth/resend-verification`; starts the cooldown with the
  /// server's wait (also on `429`, honouring `retryAfterSeconds`, which
  /// grows after wrong codes).
  ///
  /// Returns whether a code was sent. `false` means the email is already
  /// verified (e.g. the code was typed on another device); the session is
  /// then reloaded so the router moves on.
  Future<bool> resendVerification() async {
    final userId = _ref.read(sessionUserIdProvider);
    // Cooldown notifiers are looked up after the await: an unwatched one
    // may have been disposed meanwhile.
    void wait(int seconds) {
      if (userId != null) {
        _cooldown(AuthCooldownKeys.verifyEmail(userId)).start(seconds);
      }
    }

    final int seconds;
    try {
      seconds = await _session.resendVerification();
    } on ApiException catch (e) {
      if (e.code == ApiErrorCode.tooManyRequests) {
        wait(
          e.retryAfterSeconds ?? AuthCooldownDefaults.tooManyRequestsSeconds,
        );
      }
      rethrow;
    }
    if (seconds > 0) {
      wait(seconds);
      return true;
    }
    // `{ sent: false, retryAfterSeconds: 0 }`: nothing to wait for.
    wait(0);
    await _session.refreshMe();
    return false;
  }

  /// Re-reads the session, e.g. when the app returns to the foreground on
  /// an onboarding screen (the email may have been verified, or a family
  /// created / joined, on another device). Never throws: a `401` signs out
  /// through the session controller, other failures keep the session.
  Future<void> refreshSession() async {
    try {
      await _session.refreshMe();
    } catch (e) {
      debugPrint('AuthActions: session refresh failed ($e)');
    }
  }

  /// `POST /family` for a signed-in user without a family.
  Future<void> createFamily(CreateFamilyRequest request) =>
      _membershipChange(() => _session.createFamily(request));

  /// `POST /family/join`. Errors: `INVALID_INVITE_CODE`,
  /// `ALREADY_IN_FAMILY`.
  Future<void> joinFamily(String inviteCode) =>
      _membershipChange(() => _session.joinFamily(inviteCode));

  /// Signs out of this device (never throws).
  Future<void> logout() => _session.logout();

  /// The user signed in again: the "you were signed out" notice is done.
  void _signedIn() =>
      _ref.read(sessionExpiredNoticeProvider.notifier).dismiss();

  Future<void> _membershipChange(Future<void> Function() action) async {
    try {
      await action();
      markChanged(_ref, {DataScope.family, DataScope.members});
    } on ApiException catch (e) {
      // The server already has a family for this account (e.g. joined on
      // another phone): reload the session so the router moves on.
      if (e.code == ApiErrorCode.alreadyInFamily) {
        unawaited(
          _session.refreshMe().catchError((Object error) {
            debugPrint('AuthActions: session refresh failed ($error)');
          }),
        );
      }
      rethrow;
    }
  }
}

final authActionsProvider = Provider<AuthActions>(AuthActions.new);
