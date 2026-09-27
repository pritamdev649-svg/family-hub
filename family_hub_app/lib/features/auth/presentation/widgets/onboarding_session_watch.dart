import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/features/auth/application/auth_actions.dart';
import 'package:family_hub/features/auth/application/session_expired_notice.dart';

/// For the onboarding screens (signed in, session incomplete: verify email,
/// family setup), which live outside the app shell and its resume handling:
///
/// * re-reads the session whenever the app returns to the foreground, so a
///   code typed or a family created / joined **on another device** moves
///   this one on (the router follows the session);
/// * keeps [sessionExpiredNoticeProvider] listening, so a session that
///   expires while the screen is open is explained on the welcome screen.
///
/// Call [watchOnboardingSession] from `build`.
mixin OnboardingSessionWatch<T extends ConsumerStatefulWidget>
    on ConsumerState<T> {
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => unawaited(ref.read(authActionsProvider).refreshSession()),
    );
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  /// Keeps the session-expired notice alive while this screen is shown.
  void watchOnboardingSession() =>
      ref.listen<bool>(sessionExpiredNoticeProvider, (_, _) {});
}
