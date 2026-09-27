// Verify-email, forgot-password and family-setup screens.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/network/api_exception.dart';
import 'package:family_hub/core/providers/core_providers.dart' show AuthEvents;
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/features/auth/application/auth_cooldown.dart';
import 'package:family_hub/features/auth/application/session_expired_notice.dart';
import 'package:family_hub/features/auth/presentation/screens/forgot_password_screen.dart';
import 'package:family_hub/features/auth/presentation/screens/login_screen.dart';
import 'package:family_hub/features/auth/presentation/widgets/auth_code_fields.dart';
import 'package:family_hub/shared/models/models.dart';
import 'package:family_hub/shared/session/session_controller.dart';

import 'auth_test_utils.dart';

Finder _field(String label) => find.widgetWithText(TextFormField, label);

/// The 6-box one-time code input (one hidden field under the boxes).
final Finder _otp = find.byType(OtpCodeField);

Finder _button(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
);

bool _enabled(WidgetTester tester, String label) =>
    tester.widget<ButtonStyleButton>(_button(label).first).onPressed != null;

void main() {
  final l10n = enL10n;

  group('VerifyEmailScreen', () {
    testWidgets('shows the email and auto-submits 6 digits', (tester) async {
      final auth = FakeAuthRepository(
        account: completeSession(verified: false),
      );
      final app = await pumpAuthApp(
        tester,
        location: AppRoutes.verifyEmail,
        auth: auth,
        signedIn: true,
      );

      expect(
        find.text(l10n.authVerifyMessage('amit@example.com')),
        findsOneWidget,
      );
      // Native digits and spaces are cleaned up while typing / pasting.
      await tester.enterText(_otp, '١٢٣ ٤٥٦');
      await settle(tester);

      expect(auth.lastOtp, '123456');
      expect(
        app.container.read(sessionControllerProvider).value?.isComplete,
        isTrue,
      );
      expect(find.text(l10n.authEmailVerified), findsOneWidget);
    });

    testWidgets('a wrong code is shown under the field', (tester) async {
      final auth = FakeAuthRepository(account: completeSession(verified: false))
        ..failNext(
          'verifyEmail',
          const ApiException(code: ApiErrorCode.invalidOtp, statusCode: 400),
        );
      await pumpAuthApp(
        tester,
        location: AppRoutes.verifyEmail,
        auth: auth,
        signedIn: true,
      );

      await tester.enterText(_otp, '000000');
      await settle(tester);

      expect(find.text(l10n.errorInvalidOtp), findsOneWidget);
    });

    testWidgets('resend counts down and honours the server wait', (
      tester,
    ) async {
      final clock = TestClock();
      final auth = FakeAuthRepository(account: completeSession(verified: false))
        ..resendSeconds = 60;
      final app = await pumpAuthApp(
        tester,
        location: AppRoutes.verifyEmail,
        auth: auth,
        clock: clock,
        signedIn: true,
      );
      expect(_enabled(tester, l10n.authResendCode), isTrue);

      await tester.tap(find.text(l10n.authResendCode));
      await settle(tester);
      expect(auth.count('resendVerification'), 1);
      expect(find.text(l10n.authCodeSent), findsOneWidget);
      final waiting = l10n.authResendCodeIn(l10n.authCooldownSeconds(60));
      expect(find.text(waiting), findsOneWidget);
      expect(_enabled(tester, waiting), isFalse);

      clock.advance(const Duration(seconds: 60));
      await tester.pump(const Duration(seconds: 1));
      expect(_enabled(tester, l10n.authResendCode), isTrue);

      // 429 from the server: its wait replaces ours.
      auth.failNext(
        'resendVerification',
        const ApiException(
          code: ApiErrorCode.tooManyRequests,
          statusCode: 429,
          details: {'retryAfterSeconds': 25},
        ),
      );
      await tester.tap(find.text(l10n.authResendCode));
      await settle(tester);
      expect(
        find.text(l10n.authResendCodeIn(l10n.authCooldownSeconds(25))),
        findsOneWidget,
      );
      expect(
        app.container
            .read(
              authCooldownProvider(AuthCooldownKeys.verifyEmail('u1')).notifier,
            )
            .secondsLeft,
        25,
      );
    });

    testWidgets('"Use another account" signs out', (tester) async {
      final auth = FakeAuthRepository(
        account: completeSession(verified: false),
      );
      final app = await pumpAuthApp(
        tester,
        location: AppRoutes.verifyEmail,
        auth: auth,
        signedIn: true,
      );

      await tester.tap(find.text(l10n.authUseAnotherAccount));
      await settle(tester);

      expect(auth.calls, contains('logout'));
      expect(app.container.read(sessionUserIdProvider), isNull);
    });
  });

  group('ForgotPasswordScreen', () {
    testWidgets('email → code + new password → back to log-in', (tester) async {
      final auth = FakeAuthRepository();
      final app = await pumpAuthApp(
        tester,
        location: AppRoutes.login,
        auth: auth,
        clock: TestClock(),
      );
      await tester.tap(find.text(l10n.authForgotPasswordLink));
      await settle(tester);
      expect(find.byType(ForgotPasswordScreen), findsOneWidget);

      await tester.enterText(_field(l10n.authEmailLabel), ' Amit@Example.com');
      await tester.tap(find.text(l10n.authSendCode));
      await settle(tester);

      expect(auth.lastForgotEmail, 'amit@example.com');
      expect(
        find.text(l10n.authForgotCodeMessage('amit@example.com')),
        findsOneWidget,
      );
      // The code was just sent: resend waits for the cooldown.
      expect(
        _enabled(tester, l10n.authResendCodeIn(l10n.authCooldownSeconds(60))),
        isFalse,
      );

      await tester.enterText(_otp, '123456');
      await tester.enterText(_field(l10n.authNewPasswordLabel), 'brandnew1');
      await tester.enterText(
        _field(l10n.authConfirmNewPasswordLabel),
        'brandnew1',
      );
      await tester.tap(find.text(l10n.authResetButton));
      await settle(tester);

      expect(auth.lastReset, {
        'email': 'amit@example.com',
        'otp': '123456',
        'newPassword': 'brandnew1',
      });
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text(l10n.authPasswordResetSuccess), findsOneWidget);
      // The email came back to the log-in form.
      expect(find.text('amit@example.com'), findsOneWidget);
      expect(app.router.state.uri.path, AppRoutes.login);
    });

    testWidgets('mismatched passwords and an expired code stay on step 2', (
      tester,
    ) async {
      final auth = FakeAuthRepository()
        ..failNext(
          'resetPassword',
          const ApiException(code: ApiErrorCode.otpExpired, statusCode: 400),
        );
      await pumpAuthApp(
        tester,
        location: AppRoutes.forgotPassword,
        auth: auth,
        clock: TestClock(),
      );
      await tester.enterText(_field(l10n.authEmailLabel), 'amit@example.com');
      await tester.tap(find.text(l10n.authSendCode));
      await settle(tester);

      await tester.enterText(_otp, '123456');
      await tester.enterText(_field(l10n.authNewPasswordLabel), 'brandnew1');
      await tester.enterText(
        _field(l10n.authConfirmNewPasswordLabel),
        'brandnew2',
      );
      await tester.tap(find.text(l10n.authResetButton));
      await settle(tester);
      expect(find.text(l10n.validationPasswordMismatch), findsOneWidget);
      expect(auth.count('resetPassword'), 0);

      await tester.enterText(
        _field(l10n.authConfirmNewPasswordLabel),
        'brandnew1',
      );
      await tester.tap(find.text(l10n.authResetButton));
      await settle(tester);
      expect(find.text(l10n.errorOtpExpired), findsOneWidget);
      expect(find.text(l10n.authResetButton), findsOneWidget);

      // "Use a different email" goes back to step 1.
      await tester.tap(find.text(l10n.authChangeEmail));
      await settle(tester);
      expect(find.text(l10n.authSendCode), findsOneWidget);
    });
  });

  group('FamilySetupScreen', () {
    SessionState noFamily() => SessionState(user: testUser(withFamily: false));

    testWidgets('create sends the family form', (tester) async {
      final auth = FakeAuthRepository(account: noFamily());
      final family = FakeFamilyRepository(completeSession());
      final app = await pumpAuthApp(
        tester,
        location: AppRoutes.familySetup,
        auth: auth,
        family: family,
        signedIn: true,
      );
      expect(find.text(l10n.authFamilySetupGreeting('Amit')), findsOneWidget);
      expect(
        find.text(l10n.authSignedInAs('amit@example.com')),
        findsOneWidget,
      );

      await tester.tap(find.text(l10n.authCreateFamilyButton));
      await settle(tester);
      expect(find.text(l10n.validationRequired), findsOneWidget);
      expect(family.count('createFamily'), 0);

      await tester.enterText(_field(l10n.authFamilyNameLabel), 'Sharma Family');
      await tester.tap(find.text(l10n.authCreateFamilyButton));
      await settle(tester);

      expect(family.lastCreate?.name, 'Sharma Family');
      expect(family.lastCreate?.country, 'US'); // test device locale en_US
      expect(family.lastCreate?.currency, 'USD');
      expect(
        app.container.read(sessionControllerProvider).value?.isComplete,
        isTrue,
      );
    });

    testWidgets('join: an unknown code is shown under the field', (
      tester,
    ) async {
      final auth = FakeAuthRepository(account: noFamily());
      final family = FakeFamilyRepository(completeSession())
        ..failNext(
          'joinFamily',
          const ApiException(
            code: ApiErrorCode.invalidInviteCode,
            statusCode: 400,
          ),
        );
      await pumpAuthApp(
        tester,
        location: AppRoutes.familySetup,
        auth: auth,
        family: family,
        signedIn: true,
      );

      // The "join" mode tile.
      await tester.tap(find.text(l10n.authWelcomeJoinFamily));
      await settle(tester);
      await tester.enterText(_field(l10n.authInviteCodeLabel), 'k7q2-m9xd');
      await tester.tap(find.text(l10n.authJoinFamilyButton));
      await settle(tester);

      expect(family.lastJoinCode, 'K7Q2M9XD');
      expect(find.text(l10n.errorInvalidInviteCode), findsOneWidget);
    });

    testWidgets('log out from the app bar', (tester) async {
      final auth = FakeAuthRepository(account: noFamily());
      final app = await pumpAuthApp(
        tester,
        location: AppRoutes.familySetup,
        auth: auth,
        signedIn: true,
      );

      await tester.tap(find.byTooltip(l10n.authLogout));
      await settle(tester);

      expect(app.container.read(sessionUserIdProvider), isNull);
    });
  });

  group('hardening', () {
    ApiException tooMany(int seconds) => ApiException(
      code: ApiErrorCode.tooManyRequests,
      statusCode: 429,
      details: {'retryAfterSeconds': seconds},
    );

    /// The app went to the background and came back.
    void resumeApp(WidgetTester tester) {
      tester.binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    }

    testWidgets('verify email: resend when the email was verified on '
        'another device reloads the session, no "code sent"', (tester) async {
      final auth = FakeAuthRepository(account: completeSession(verified: false))
        ..resendSeconds = 0; // `{ sent: false, retryAfterSeconds: 0 }`
      final app = await pumpAuthApp(
        tester,
        location: AppRoutes.verifyEmail,
        auth: auth,
        clock: TestClock(),
        signedIn: true,
      );
      auth.account = completeSession();

      await tester.tap(find.text(l10n.authResendCode));
      await settle(tester);

      expect(find.text(l10n.authCodeSent), findsNothing);
      expect(
        app.container.read(sessionControllerProvider).value?.isComplete,
        isTrue,
      );
    });

    testWidgets('verify email: returning to the app reloads the session', (
      tester,
    ) async {
      final auth = FakeAuthRepository(
        account: completeSession(verified: false),
      );
      final app = await pumpAuthApp(
        tester,
        location: AppRoutes.verifyEmail,
        auth: auth,
        signedIn: true,
      );
      final before = auth.count('me');
      auth.account = completeSession(); // verified on the phone meanwhile

      resumeApp(tester);
      await settle(tester);

      expect(auth.count('me'), before + 1);
      expect(
        app.container.read(sessionControllerProvider).value?.isComplete,
        isTrue,
      );
    });

    testWidgets('verify email: a session that expires here is remembered for '
        'the welcome screen', (tester) async {
      final events = AuthEvents();
      final app = await pumpAuthApp(
        tester,
        location: AppRoutes.verifyEmail,
        auth: FakeAuthRepository(account: completeSession(verified: false)),
        events: events,
        signedIn: true,
      );

      events.emitSessionExpired();
      await settle(tester);

      expect(app.container.read(sessionExpiredNoticeProvider), isTrue);
    });

    testWidgets('verify email: a rate-limited resend explains the wait in '
        'minutes', (tester) async {
      final auth = FakeAuthRepository(account: completeSession(verified: false))
        ..failNext('resendVerification', tooMany(840));
      await pumpAuthApp(
        tester,
        location: AppRoutes.verifyEmail,
        auth: auth,
        clock: TestClock(),
        signedIn: true,
      );

      await tester.tap(find.text(l10n.authResendCode));
      await settle(tester);

      expect(
        find.text(l10n.authTooManyAttemptsWait(l10n.authCooldownMinutes(14))),
        findsOneWidget,
      );
      expect(
        find.text(l10n.authResendCodeIn(l10n.authCooldownMinutes(14))),
        findsOneWidget,
      );
    });

    testWidgets('forgot password: 429 on step 1 stays there, explains the '
        'wait and really retries', (tester) async {
      final auth = FakeAuthRepository()
        ..failNext('forgotPassword', tooMany(30));
      await pumpAuthApp(
        tester,
        location: AppRoutes.forgotPassword,
        auth: auth,
        clock: TestClock(),
      );
      await tester.enterText(_field(l10n.authEmailLabel), 'amit@example.com');
      await tester.tap(find.text(l10n.authSendCode));
      await settle(tester);

      expect(
        find.text(l10n.authTooManyAttemptsWait(l10n.authCooldownSeconds(30))),
        findsOneWidget,
      );
      expect(find.text(l10n.authSendCode), findsOneWidget);
      expect(find.text(l10n.authOtpLabel), findsNothing);

      await tester.tap(find.text(l10n.authSendCode));
      await settle(tester);
      expect(auth.count('forgotPassword'), 2);
      expect(find.text(l10n.authOtpLabel), findsOneWidget);
    });

    testWidgets('forgot password opened directly: success goes to log-in '
        'with the email', (tester) async {
      final auth = FakeAuthRepository();
      final app = await pumpAuthApp(
        tester,
        location: AppRoutes.forgotPassword,
        auth: auth,
        clock: TestClock(),
      );
      await tester.enterText(_field(l10n.authEmailLabel), 'amit@example.com');
      await tester.tap(find.text(l10n.authSendCode));
      await settle(tester);
      await tester.enterText(_otp, '123456');
      await tester.enterText(_field(l10n.authNewPasswordLabel), 'brandnew1');
      await tester.enterText(
        _field(l10n.authConfirmNewPasswordLabel),
        'brandnew1',
      );
      await tester.tap(find.text(l10n.authResetButton));
      await settle(tester);

      expect(app.router.state.uri.path, AppRoutes.login);
      expect(
        tester
            .widget<TextFormField>(_field(l10n.authEmailLabel))
            .controller
            ?.text,
        'amit@example.com',
      );
    });

    testWidgets('family setup: an invite link opens join mode with the code', (
      tester,
    ) async {
      final auth = FakeAuthRepository(
        account: SessionState(user: testUser(withFamily: false)),
      );
      final family = FakeFamilyRepository(completeSession());
      await pumpAuthApp(
        tester,
        location: '${AppRoutes.familySetup}?code=k7q2-m9xd',
        auth: auth,
        family: family,
        signedIn: true,
      );

      expect(find.text('K7Q2M9XD'), findsOneWidget);
      await tester.tap(find.text(l10n.authJoinFamilyButton));
      await settle(tester);
      expect(family.lastJoinCode, 'K7Q2M9XD');
    });

    testWidgets('family setup: the consent age gate is explained', (
      tester,
    ) async {
      final auth = FakeAuthRepository(
        account: SessionState(user: testUser(withFamily: false)),
      );
      final family = FakeFamilyRepository(completeSession())
        ..failNext(
          'createFamily',
          const ApiException(
            code: ApiErrorCode.guardianConsentRequired,
            statusCode: 422,
            details: {'consentAge': 18},
          ),
        );
      await pumpAuthApp(
        tester,
        location: AppRoutes.familySetup,
        auth: auth,
        family: family,
        signedIn: true,
      );
      await tester.enterText(_field(l10n.authFamilyNameLabel), 'Our Family');
      await tester.tap(find.text(l10n.authCreateFamilyButton));
      await settle(tester);

      expect(find.text(l10n.authSignupTooYoung(18)), findsOneWidget);
    });

    testWidgets('family setup: returning to the app picks up a family joined '
        'on another device', (tester) async {
      final auth = FakeAuthRepository(
        account: SessionState(user: testUser(withFamily: false)),
      );
      final app = await pumpAuthApp(
        tester,
        location: AppRoutes.familySetup,
        auth: auth,
        signedIn: true,
      );
      auth.account = completeSession();

      resumeApp(tester);
      await settle(tester);

      expect(
        app.container.read(sessionControllerProvider).value?.isComplete,
        isTrue,
      );
    });
  });
}
