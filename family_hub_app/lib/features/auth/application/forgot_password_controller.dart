import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/network/api_exception.dart';
import 'package:family_hub/features/auth/application/auth_cooldown.dart';
import 'package:family_hub/features/auth/domain/auth_rules.dart';
import 'package:family_hub/shared/data/repository_utils.dart';
import 'package:family_hub/shared/providers/shared_providers.dart';

/// Steps of the forgot-password flow.
enum ForgotPasswordStep {
  /// Type the account email → `POST /auth/forgot-password`.
  email,

  /// Type the code + new password → `POST /auth/reset-password`.
  reset,
}

/// State of the forgot-password flow. Busy flags live here (not in the
/// widget) so the controller itself refuses double submits.
@immutable
class ForgotPasswordState {
  const ForgotPasswordState({
    this.step = ForgotPasswordStep.email,
    this.email = '',
    this.isSending = false,
    this.isResetting = false,
  });

  final ForgotPasswordStep step;

  /// Normalised email the code was requested for ('' before step 1).
  final String email;

  /// A code request (step 1 or "resend") is in flight.
  final bool isSending;

  /// The reset request is in flight.
  final bool isResetting;

  bool get isBusy => isSending || isResetting;

  ForgotPasswordState copyWith({
    ForgotPasswordStep? step,
    String? email,
    bool? isSending,
    bool? isResetting,
  }) {
    return ForgotPasswordState(
      step: step ?? this.step,
      email: email ?? this.email,
      isSending: isSending ?? this.isSending,
      isResetting: isResetting ?? this.isResetting,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ForgotPasswordState &&
          other.step == step &&
          other.email == email &&
          other.isSending == isSending &&
          other.isResetting == isResetting;

  @override
  int get hashCode => Object.hash(step, email, isSending, isResetting);

  @override
  String toString() =>
      'ForgotPasswordState(${step.name}, sending: $isSending, '
      'resetting: $isResetting)';
}

/// Drives the forgot-password screen (docs/03-API_CONTRACT.md §4):
/// email → code → new password. Methods rethrow [ApiException]s for the
/// screen to show; the state always leaves its busy flag afterwards.
///
/// `forgot-password` always answers `{ sent: true }`, even when the server
/// sends nothing because the resend cooldown still runs. So the controller
/// mirrors that cooldown ([OtpRules.resendCooldownAfter]: it grows with
/// every wrong code) and "Resend code" never promises a code that is not
/// coming.
class ForgotPasswordController extends Notifier<ForgotPasswordState> {
  /// When the last code for [ForgotPasswordState.email] was requested
  /// successfully, and how many wrong codes were typed since.
  DateTime? _sentAt;
  int _wrongCodes = 0;

  @override
  ForgotPasswordState build() {
    _sentAt = null;
    _wrongCodes = 0;
    return const ForgotPasswordState();
  }

  DateTime _now() => ref.read(authClockProvider)();

  AuthCooldown _cooldown(String email) => ref.read(
    authCooldownProvider(AuthCooldownKeys.passwordReset(email)).notifier,
  );

  /// Seconds until another code may be requested for the current email.
  int get resendSecondsLeft =>
      state.email.isEmpty ? 0 : _cooldown(state.email).secondsLeft;

  /// Step 1: requests a code for [email] and moves to the reset step. The
  /// server answers the same for unknown emails (no enumeration). When a
  /// code was sent to this email moments ago (its resend cooldown runs), no
  /// new request is made.
  Future<void> requestCode(String email) async {
    final normalized = normalizeEmail(email) ?? '';
    if (state.isBusy || normalized.isEmpty) return;
    if (_cooldown(normalized).isActive) {
      if (normalized != state.email) {
        // A code of an earlier visit: its wrong guesses are unknown here.
        _sentAt = null;
        _wrongCodes = 0;
      }
      state = state.copyWith(step: ForgotPasswordStep.reset, email: normalized);
      return;
    }
    await _send(normalized, isResend: false);
    if (ref.mounted) {
      state = state.copyWith(step: ForgotPasswordStep.reset, email: normalized);
    }
  }

  /// Step 2: "Resend code". No-op while the cooldown runs.
  Future<void> resendCode() async {
    final email = state.email;
    if (state.isBusy || email.isEmpty || _cooldown(email).isActive) return;
    await _send(email, isResend: true);
  }

  /// Step 2: sets the new password. The server revokes every session of the
  /// account. Errors: `INVALID_OTP` (also extends the resend wait, like the
  /// server), `OTP_EXPIRED`, `VALIDATION_ERROR`.
  Future<void> resetPassword({
    required String otp,
    required String newPassword,
  }) async {
    if (state.isBusy || state.email.isEmpty) return;
    final email = state.email;
    state = state.copyWith(isResetting: true);
    try {
      await ref
          .read(authRepositoryProvider)
          .resetPassword(email: email, otp: otp, newPassword: newPassword);
      if (ref.mounted) {
        _cooldown(email).clear();
        _sentAt = null;
        _wrongCodes = 0;
      }
    } on ApiException catch (e) {
      if (e.code == ApiErrorCode.invalidOtp && ref.mounted) {
        _wrongCodes++;
        final sentAt = _sentAt;
        if (sentAt != null) {
          _cooldown(
            email,
          ).extendUntil(sentAt.add(OtpRules.resendCooldownAfter(_wrongCodes)));
        }
      }
      rethrow;
    } finally {
      if (ref.mounted) state = state.copyWith(isResetting: false);
    }
  }

  /// Back to step 1 (the email stays for editing).
  void changeEmail() {
    if (state.isBusy) return;
    state = state.copyWith(step: ForgotPasswordStep.email);
  }

  Future<void> _send(String email, {required bool isResend}) async {
    state = state.copyWith(isSending: true);
    try {
      await ref.read(authRepositoryProvider).forgotPassword(email);
      if (ref.mounted) {
        _sentAt = _now();
        _wrongCodes = 0;
        _cooldown(email).start(AuthCooldownDefaults.resendSeconds);
      }
    } on ApiException catch (e) {
      // A rate-limited *resend* waits for the server. On step 1 no code was
      // sent, so no cooldown is started (it would later skip step 1 as if a
      // code were on its way); the screen shows the wait instead.
      if (e.code == ApiErrorCode.tooManyRequests && isResend && ref.mounted) {
        _cooldown(email).start(
          e.retryAfterSeconds ?? AuthCooldownDefaults.tooManyRequestsSeconds,
        );
      }
      rethrow;
    } finally {
      if (ref.mounted) state = state.copyWith(isSending: false);
    }
  }
}

final forgotPasswordControllerProvider =
    NotifierProvider.autoDispose<ForgotPasswordController, ForgotPasswordState>(
      ForgotPasswordController.new,
    );
