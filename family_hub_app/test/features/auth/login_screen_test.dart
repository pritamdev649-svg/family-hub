import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/network/api_exception.dart';
import 'package:family_hub/core/network/mock/mock_seed.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/features/auth/presentation/screens/forgot_password_screen.dart';
import 'package:family_hub/features/auth/presentation/screens/login_screen.dart';
import 'package:family_hub/features/auth/presentation/screens/register_screen.dart';
import 'package:family_hub/l10n/app_localizations.dart';
import 'package:family_hub/shared/session/session_controller.dart';

import 'auth_test_utils.dart';

Finder _field(String label) =>
    find.widgetWithText(TextFormField, label, skipOffstage: false);

Finder _loginButton(AppLocalizations l10n) =>
    find.widgetWithText(FilledButton, l10n.authLoginButton);

void main() {
  final l10n = enL10n;

  testWidgets('empty submit shows validation errors and calls nothing', (
    tester,
  ) async {
    final auth = FakeAuthRepository();
    await pumpAuthApp(tester, location: AppRoutes.login, auth: auth);

    await tester.tap(_loginButton(l10n));
    await settle(tester);

    expect(find.text(l10n.validationRequired), findsWidgets);
    expect(auth.count('login'), 0);
  });

  testWidgets('valid credentials sign in with the trimmed email', (
    tester,
  ) async {
    final auth = FakeAuthRepository();
    final app = await pumpAuthApp(
      tester,
      location: AppRoutes.login,
      auth: auth,
    );

    await tester.enterText(_field(l10n.authEmailLabel), '  amit@example.com ');
    await tester.enterText(_field(l10n.authPasswordLabel), 'secret123');
    await tester.tap(_loginButton(l10n));
    await settle(tester);

    expect(auth.lastLoginEmail, 'amit@example.com');
    expect(auth.lastLoginPassword, 'secret123');
    expect(app.container.read(sessionUserIdProvider), 'u1');
  });

  testWidgets('wrong password shows the generic message inline', (
    tester,
  ) async {
    final auth = FakeAuthRepository()
      ..failNext(
        'login',
        const ApiException(
          code: ApiErrorCode.invalidCredentials,
          statusCode: 401,
        ),
      );
    await pumpAuthApp(tester, location: AppRoutes.login, auth: auth);

    await tester.enterText(_field(l10n.authEmailLabel), 'amit@example.com');
    await tester.enterText(_field(l10n.authPasswordLabel), 'wrong123');
    await tester.tap(_loginButton(l10n));
    await settle(tester);

    expect(find.text(l10n.errorInvalidCredentials), findsOneWidget);

    // Editing the form clears the message.
    await tester.enterText(_field(l10n.authPasswordLabel), 'wrong1234');
    await tester.pump();
    expect(find.text(l10n.errorInvalidCredentials), findsNothing);
  });

  testWidgets('lockout shows a countdown and disables the button until it '
      'ends', (tester) async {
    final clock = TestClock();
    final auth = FakeAuthRepository()
      ..failNext(
        'login',
        const ApiException(
          code: ApiErrorCode.tooManyRequests,
          statusCode: 429,
          details: {'retryAfterSeconds': 900},
        ),
      );
    await pumpAuthApp(
      tester,
      location: AppRoutes.login,
      auth: auth,
      clock: clock,
    );

    await tester.enterText(_field(l10n.authEmailLabel), 'amit@example.com');
    await tester.enterText(_field(l10n.authPasswordLabel), 'wrong123');
    await tester.tap(_loginButton(l10n));
    await settle(tester);

    expect(
      find.text(l10n.authLoginLockedOut(l10n.authCooldownMinutes(15))),
      findsOneWidget,
    );
    expect(tester.widget<FilledButton>(_loginButton(l10n)).onPressed, isNull);

    // Another email is not locked.
    await tester.enterText(_field(l10n.authEmailLabel), 'priya@example.com');
    await tester.pump();
    expect(
      tester.widget<FilledButton>(_loginButton(l10n)).onPressed,
      isNotNull,
    );
    await tester.enterText(_field(l10n.authEmailLabel), 'amit@example.com');
    await tester.pump();

    clock.advance(const Duration(minutes: 14, seconds: 30));
    await tester.pump(const Duration(seconds: 1));
    expect(
      find.text(l10n.authLoginLockedOut(l10n.authCooldownSeconds(30))),
      findsOneWidget,
    );

    clock.advance(const Duration(seconds: 30));
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining(l10n.authCooldownSeconds(1)), findsNothing);
    expect(
      tester.widget<FilledButton>(_loginButton(l10n)).onPressed,
      isNotNull,
    );
  });

  testWidgets('demo hint fills the demo account (mock mode)', (tester) async {
    await pumpAuthApp(tester, location: AppRoutes.login);

    expect(find.text(l10n.authDemoTitle), findsOneWidget);
    await tester.tap(find.text(l10n.authDemoFill));
    await tester.pump();

    expect(find.text(MockSeed.demoEmail), findsOneWidget);
    final password = tester.widget<EditableText>(
      find.descendant(
        of: _field(l10n.authPasswordLabel),
        matching: find.byType(EditableText),
      ),
    );
    expect(password.controller.text, MockSeed.demoPassword);
  });

  testWidgets('links open forgot password (with the email) and sign-up', (
    tester,
  ) async {
    final app = await pumpAuthApp(tester, location: AppRoutes.login);

    await tester.enterText(_field(l10n.authEmailLabel), 'amit@example.com');
    await tester.tap(find.text(l10n.authForgotPasswordLink));
    await settle(tester);
    expect(find.byType(ForgotPasswordScreen), findsOneWidget);
    expect(find.text('amit@example.com'), findsOneWidget);

    app.router.pop();
    await settle(tester);
    expect(find.byType(LoginScreen), findsOneWidget);

    await tester.ensureVisible(find.text(l10n.authCreateAccountLink));
    await tester.tap(find.text(l10n.authCreateAccountLink));
    await settle(tester);
    expect(find.byType(RegisterScreen), findsOneWidget);
  });
}
