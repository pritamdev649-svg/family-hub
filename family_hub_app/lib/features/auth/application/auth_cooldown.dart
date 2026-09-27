import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show KeepAliveLink;

import 'package:family_hub/features/auth/domain/auth_rules.dart';

/// What a cooldown is waiting for.
enum AuthCooldownPurpose {
  /// `POST /auth/resend-verification` (60 s between codes).
  verifyEmail,

  /// `POST /auth/forgot-password` (a new reset code).
  passwordReset,

  /// Login lockout after too many wrong passwords (`429`).
  login,
}

/// Identifies one cooldown: its purpose plus the account it applies to
/// (user id or normalised email), so switching account / email never
/// inherits somebody else's wait. Records have value equality, so they work
/// as provider family keys.
typedef AuthCooldownKey = ({AuthCooldownPurpose purpose, String subject});

/// Builders for [AuthCooldownKey]s (subjects are normalised here once).
abstract final class AuthCooldownKeys {
  static AuthCooldownKey verifyEmail(String userId) =>
      (purpose: AuthCooldownPurpose.verifyEmail, subject: userId.trim());

  static AuthCooldownKey passwordReset(String email) =>
      (purpose: AuthCooldownPurpose.passwordReset, subject: _email(email));

  static AuthCooldownKey login(String email) =>
      (purpose: AuthCooldownPurpose.login, subject: _email(email));

  static String _email(String email) => email.trim().toLowerCase();
}

/// Default waits when the server does not say (contract §4: resend
/// cooldown 60 s).
abstract final class AuthCooldownDefaults {
  static final resendSeconds = OtpRules.resendCooldown.inSeconds;

  /// Used for a `429` without `retryAfterSeconds`.
  static const tooManyRequestsSeconds = 60;
}

/// The auth feature's clock. Tests override it to move time forward.
final authClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Seconds left until [until] at [now], rounded up (0 when over / unset).
int cooldownSecondsLeft(DateTime? until, DateTime now) {
  if (until == null) return 0;
  final ms = until.difference(now).inMilliseconds;
  return ms <= 0 ? 0 : (ms / 1000).ceil();
}

/// A wait before an action may be repeated (resend a code, retry a locked
/// login). The state is the moment the wait ends (`null` = no wait): an end
/// time — not a ticking counter — stays correct while the app is in the
/// background. Widgets re-render every second with `CooldownBuilder`.
///
/// Auto-disposed, but a running cooldown keeps itself alive, so one started
/// by one screen (e.g. sign-up, which just sent the first code) is still
/// there when the next screen opens. It lets go once it is cleared or seen
/// expired, so keys nobody started (the log-in screen watches the key of
/// whatever email is being typed) never pile up.
class AuthCooldown extends Notifier<DateTime?> {
  AuthCooldown(this.key);

  final AuthCooldownKey key;
  KeepAliveLink? _keepAlive;

  @override
  DateTime? build() {
    ref.onDispose(() => _keepAlive = null);
    return null;
  }

  DateTime _now() => ref.read(authClockProvider)();

  /// Starts (or replaces) the wait with [seconds]; `<= 0` clears it.
  void start(int seconds) {
    if (seconds <= 0) return clear();
    state = _now().add(Duration(seconds: seconds));
    _keepAlive ??= ref.keepAlive();
  }

  /// Makes the wait last at least until [until] (never shortens it); an
  /// [until] in the past changes nothing.
  void extendUntil(DateTime until) {
    if (!until.isAfter(_now())) return;
    final current = state;
    if (current != null && !until.isAfter(current)) return;
    state = until;
    _keepAlive ??= ref.keepAlive();
  }

  void clear() {
    state = null;
    _release();
  }

  /// Seconds left right now.
  int get secondsLeft {
    final left = cooldownSecondsLeft(state, _now());
    if (left == 0) _release();
    return left;
  }

  bool get isActive => secondsLeft > 0;

  void _release() {
    _keepAlive?.close();
    _keepAlive = null;
  }
}

final authCooldownProvider = NotifierProvider.autoDispose
    .family<AuthCooldown, DateTime?, AuthCooldownKey>(AuthCooldown.new);
