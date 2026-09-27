// End to end in mock mode with the real app, router guard, session
// controller and `/auth` mock handlers: sign up (create a family) → verify
// the email with the mock OTP → home; then log out and log back in.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:family_hub/app.dart';
import 'package:family_hub/core/network/mock/mock_seed.dart';
import 'package:family_hub/core/providers/core_providers.dart';
import 'package:family_hub/core/router/app_router.dart';
import 'package:family_hub/features/auth/presentation/screens/family_setup_screen.dart';
import 'package:family_hub/features/auth/presentation/widgets/auth_code_fields.dart';
import 'package:family_hub/features/auth/presentation/screens/verify_email_screen.dart';
import 'package:family_hub/features/auth/presentation/screens/welcome_screen.dart';
import 'package:family_hub/shared/session/session_controller.dart';

import 'auth_test_utils.dart';

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required String reason,
}) async {
  for (var i = 0; i < 300; i++) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(condition(), isTrue, reason: reason);
}

Finder _field(String label) => find.widgetWithText(TextFormField, label);

void main() {
  testWidgets(
    'sign up → verify email → home → log out → log in',
    (tester) async {
      useTallScreen(tester);
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: const FamilyHubApp(),
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(FamilyHubApp)),
      );
      final l10n = enL10n;
      String path() => container
          .read(goRouterProvider)
          .routerDelegate
          .currentConfiguration
          .uri
          .path;

      await _pumpUntil(
        tester,
        () => find.byType(WelcomeScreen).evaluate().isNotEmpty,
        reason: 'signed-out start shows the welcome screen',
      );

      // ── Sign up, creating a family ──────────────────────────────────────
      await tester.tap(find.text(l10n.authWelcomeCreateFamily));
      await _pumpUntil(
        tester,
        () => _field(l10n.authNameLabel).evaluate().isNotEmpty,
        reason: 'sign-up form opens',
      );
      await tester.enterText(_field(l10n.authNameLabel), 'Neha Gupta');
      await tester.enterText(_field(l10n.authEmailLabel), 'neha@example.com');
      await tester.enterText(_field(l10n.authPasswordLabel), 'secret123');
      await tester.enterText(
        _field(l10n.authConfirmPasswordLabel),
        'secret123',
      );
      await tester.enterText(_field(l10n.authFamilyNameLabel), 'Gupta Family');
      await tester.ensureVisible(find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.text(l10n.authRegisterButton));

      await _pumpUntil(
        tester,
        () => find.byType(VerifyEmailScreen).evaluate().isNotEmpty,
        reason: 'a new account must verify its email first',
      );
      expect(
        find.text(l10n.authVerifyMessage('neha@example.com')),
        findsOneWidget,
      );

      // ── Verify with the mock OTP (auto-submits at 6 digits) ─────────────
      await tester.enterText(find.byType(OtpCodeField), MockSeed.otp);
      await _pumpUntil(
        tester,
        () => path() == '/home',
        reason: 'a verified account with a family lands on /home',
      );
      final session = container.read(sessionControllerProvider).value!;
      expect(session.user?.emailVerified, isTrue);
      expect(session.family?.name, 'Gupta Family');
      expect(session.isAdmin, isTrue);

      // ── Log out, then log back in with the new account ──────────────────
      // Not awaited directly: the mock latency needs frames to be pumped.
      final logout = container
          .read(sessionControllerProvider.notifier)
          .logout();
      await _pumpUntil(
        tester,
        () => find.byType(WelcomeScreen).evaluate().isNotEmpty,
        reason: 'logout returns to welcome',
      );
      await logout;
      await tester.tap(find.text(l10n.authWelcomeHaveAccount));
      await _pumpUntil(
        tester,
        () => _field(l10n.authPasswordLabel).evaluate().isNotEmpty,
        reason: 'log-in form opens',
      );
      await tester.enterText(_field(l10n.authEmailLabel), 'neha@example.com');
      await tester.enterText(_field(l10n.authPasswordLabel), 'secret123');
      await tester.tap(find.text(l10n.authLoginButton).last);
      await _pumpUntil(
        tester,
        () => path() == '/home',
        reason: 'log-in with the new account opens home',
      );
      expect(find.byType(FamilySetupScreen), findsNothing);

      final finalLogout = container
          .read(sessionControllerProvider.notifier)
          .logout();
      await _pumpUntil(
        tester,
        () => find.byType(WelcomeScreen).evaluate().isNotEmpty,
        reason: 'final logout',
      );
      await finalLogout;
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
