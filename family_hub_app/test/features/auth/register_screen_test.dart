import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/config/app_config.dart';
import 'package:family_hub/core/network/api_exception.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/settings/settings_controller.dart';
import 'package:family_hub/core/utils/url_actions.dart';
import 'package:family_hub/features/auth/application/auth_actions.dart';
import 'package:family_hub/features/auth/application/auth_cooldown.dart';
import 'package:family_hub/features/auth/domain/register_args.dart';
import 'package:family_hub/features/auth/presentation/screens/login_screen.dart';
import 'package:family_hub/features/auth/presentation/widgets/consent_checkbox.dart';
import 'package:family_hub/l10n/app_localizations.dart';

import 'auth_test_utils.dart';

Finder _field(String label) => find.widgetWithText(TextFormField, label);

Finder _submit(AppLocalizations l10n) =>
    find.widgetWithText(FilledButton, l10n.authRegisterButton);

Future<void> _fillAboutYou(WidgetTester tester, AppLocalizations l10n) async {
  await tester.enterText(_field(l10n.authNameLabel), 'Neha Gupta');
  await tester.enterText(_field(l10n.authEmailLabel), 'neha@example.com');
  await tester.enterText(_field(l10n.authPasswordLabel), 'secret123');
  await tester.enterText(_field(l10n.authConfirmPasswordLabel), 'secret123');
}

Future<void> _acceptConsent(WidgetTester tester) async {
  await tester.ensureVisible(find.byType(Checkbox));
  await tester.tap(find.byType(Checkbox));
  await tester.pump();
}

void main() {
  final l10n = enL10n;

  testWidgets('submit stays disabled until the consent box is ticked', (
    tester,
  ) async {
    await pumpAuthApp(tester, location: AppRoutes.register());

    expect(tester.widget<FilledButton>(_submit(l10n)).onPressed, isNull);
    expect(find.text(l10n.authConsentRequired), findsOneWidget);
    expect(
      find.text(
        l10n.authConsentAgree(l10n.authPrivacyPolicy, l10n.authTermsOfService),
        findRichText: true,
      ),
      findsOneWidget,
    );

    await _acceptConsent(tester);

    expect(tester.widget<FilledButton>(_submit(l10n)).onPressed, isNotNull);
    expect(find.text(l10n.authConsentRequired), findsNothing);
  });

  testWidgets('consent links open the privacy policy and the terms', (
    tester,
  ) async {
    final opened = <Uri>[];
    UrlActions.launcherOverride = (uri, _) async {
      opened.add(uri);
      return true;
    };
    addTearDown(() => UrlActions.launcherOverride = null);
    await pumpAuthApp(tester, location: AppRoutes.register());

    // The consent sentence with the links (the card's "please accept"
    // hint below it names the documents too, without links).
    final consent = find.descendant(
      of: find.byType(ConsentCheckbox),
      matching: find.byWidgetPredicate((w) => w is Text && w.textSpan != null),
    );
    await tester.tapOnText(
      find.textRange.ofSubstring(l10n.authPrivacyPolicy, descendentOf: consent),
    );
    await tester.tapOnText(
      find.textRange.ofSubstring(
        l10n.authTermsOfService,
        descendentOf: consent,
      ),
    );
    await tester.pump();

    expect(opened, [
      Uri.parse(AppConfig.privacyPolicyUrl),
      Uri.parse(AppConfig.termsUrl),
    ]);
    // Tapping a link does not tick the box.
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
  });

  testWidgets('create mode: country picker pre-fills currency and suggests '
      'the language', (tester) async {
    final auth = FakeAuthRepository(account: completeSession(verified: false));
    final clock = TestClock();
    final app = await pumpAuthApp(
      tester,
      location: AppRoutes.register(mode: AppRoutes.registerModeCreate),
      auth: auth,
      clock: clock,
    );

    // The device locale of the test (en_US) chose the first guess.
    expect(find.text('United States'), findsOneWidget);
    expect(find.text('USD · \$'), findsOneWidget);

    await tester.tap(find.text('United States'));
    await settle(tester);
    expect(find.text(l10n.authCountryPickerTitle), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, l10n.commonSearch),
      'germ',
    );
    await tester.pump();
    await tester.tap(find.text('Germany'));
    await settle(tester);

    expect(find.text('Germany'), findsOneWidget);
    expect(find.text('EUR · €'), findsOneWidget);
    expect(find.text(l10n.authSuggestLanguage('Deutsch')), findsOneWidget);
    await tester.tap(find.text(l10n.authSuggestLanguageAction));
    await settle(tester);
    expect(app.container.read(settingsControllerProvider).localeCode, 'de');

    await _fillAboutYou(tester, l10n);
    await tester.enterText(_field(l10n.authFamilyNameLabel), ' Gupta Family ');
    await _acceptConsent(tester);
    await tester.tap(_submit(l10n));
    await settle(tester);

    final request = auth.lastRegister!;
    expect(request.mode, RegisterMode.create);
    expect(request.consentAccepted, isTrue);
    expect(request.locale, 'de'); // the app language at submit time
    expect(request.toJson()['family'], {
      'name': 'Gupta Family',
      'country': 'DE',
      'currency': 'EUR',
      'timezone': 'Europe/Berlin',
    });
    // Sign-up already sent the first code: the resend timer runs.
    expect(
      app.container.read(authActionsProvider).verificationCooldownSeconds(),
      AuthCooldownDefaults.resendSeconds,
    );
  });

  testWidgets('join link pre-fills the code; EMAIL_TAKEN shows under the '
      'email', (tester) async {
    final auth = FakeAuthRepository()
      ..failNext(
        'register',
        const ApiException(code: ApiErrorCode.emailTaken, statusCode: 409),
      );
    await pumpAuthApp(
      tester,
      location: AppRoutes.register(code: 'k7q2m9xd'),
      auth: auth,
    );

    expect(find.text(l10n.authRegisterJoinTitle), findsOneWidget);
    expect(find.text('K7Q2M9XD'), findsOneWidget);
    expect(find.text(l10n.authFamilyNameLabel), findsNothing);

    await _fillAboutYou(tester, l10n);
    await _acceptConsent(tester);
    await tester.tap(_submit(l10n));
    await settle(tester);

    expect(auth.count('register'), 1);
    expect(auth.lastRegister?.mode, RegisterMode.join);
    expect(auth.lastRegister?.inviteCode, 'K7Q2M9XD');
    expect(find.text(l10n.errorEmailTaken), findsOneWidget);

    // Editing the email clears the server error.
    await tester.enterText(_field(l10n.authEmailLabel), 'neha2@example.com');
    await tester.pump();
    expect(find.text(l10n.errorEmailTaken), findsNothing);
  });

  testWidgets('a sign-up below the consent age is explained under the date '
      'of birth', (tester) async {
    final auth = FakeAuthRepository()
      ..failNext(
        'register',
        const ApiException(
          code: ApiErrorCode.guardianConsentRequired,
          statusCode: 422,
          details: {'consentAge': 18},
        ),
      );
    await pumpAuthApp(
      tester,
      location: AppRoutes.register(code: 'DEMO2345'),
      auth: auth,
    );

    await _fillAboutYou(tester, l10n);
    await _acceptConsent(tester);
    await tester.tap(_submit(l10n));
    await settle(tester);

    expect(find.text(l10n.authSignupTooYoung(18)), findsOneWidget);
  });

  testWidgets('client validation blocks a weak password and a bad code', (
    tester,
  ) async {
    final auth = FakeAuthRepository();
    await pumpAuthApp(
      tester,
      location: AppRoutes.register(mode: AppRoutes.registerModeJoin),
      auth: auth,
    );

    await tester.enterText(_field(l10n.authNameLabel), 'Neha');
    await tester.enterText(_field(l10n.authEmailLabel), 'neha@example.com');
    await tester.enterText(_field(l10n.authPasswordLabel), 'password');
    await tester.enterText(_field(l10n.authConfirmPasswordLabel), 'passw0rd');
    await tester.enterText(_field(l10n.authInviteCodeLabel), 'abc');
    await _acceptConsent(tester);
    await tester.tap(_submit(l10n));
    await settle(tester);

    expect(find.text(l10n.validationPasswordComplexity), findsOneWidget);
    expect(find.text(l10n.validationPasswordMismatch), findsOneWidget);
    expect(find.text(l10n.validationInviteCode), findsOneWidget);
    expect(auth.count('register'), 0);
  });

  testWidgets('mode switch swaps the family form and the invite code', (
    tester,
  ) async {
    await pumpAuthApp(tester, location: AppRoutes.register());
    expect(find.text(l10n.authFamilyNameLabel), findsOneWidget);

    // The "join" mode tile.
    await tester.tap(find.text(l10n.authWelcomeJoinFamily));
    await settle(tester);
    expect(find.text(l10n.authRegisterJoinTitle), findsOneWidget);
    expect(find.text(l10n.authInviteCodeLabel), findsOneWidget);
    expect(find.text(l10n.authFamilyNameLabel), findsNothing);
  });

  testWidgets('an invisible name and an over-long password are caught '
      'before sending', (tester) async {
    final auth = FakeAuthRepository();
    await pumpAuthApp(
      tester,
      location: AppRoutes.register(code: 'DEMO2345'),
      auth: auth,
    );
    // Zero-width space + Hangul filler: looks empty, is not blank.
    final invisible =
        '${String.fromCharCode(0x200B)}${String.fromCharCode(0x3164)}';
    // 26 Devanagari letters (3 bytes each) + a digit = 79 bytes.
    final longPassword = '${'क' * 26}1';
    await tester.enterText(_field(l10n.authNameLabel), invisible);
    await tester.enterText(_field(l10n.authEmailLabel), 'neha@example.com');
    await tester.enterText(_field(l10n.authPasswordLabel), longPassword);
    await tester.enterText(_field(l10n.authConfirmPasswordLabel), longPassword);
    await _acceptConsent(tester);
    await tester.tap(_submit(l10n));
    await settle(tester);

    expect(find.text(l10n.authNameNeedsLetter), findsOneWidget);
    expect(find.text(l10n.authPasswordTooLong), findsOneWidget);
    expect(auth.count('register'), 0);
  });

  testWidgets('"Log in" carries the typed email to the log-in screen', (
    tester,
  ) async {
    await pumpAuthApp(tester, location: AppRoutes.register());
    await tester.enterText(_field(l10n.authEmailLabel), ' neha@example.com ');

    final link = find.text(l10n.authLoginLink);
    await tester.ensureVisible(link);
    await tester.tap(link);
    await settle(tester);

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(_field(l10n.authEmailLabel))
          .controller
          ?.text,
      'neha@example.com',
    );
  });
}
