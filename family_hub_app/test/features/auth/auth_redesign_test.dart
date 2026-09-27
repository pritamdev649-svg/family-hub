// The "modern & colourful" auth screens (docs/12-DESIGN_LANGUAGE.md):
// transparent status bar with readable icons, the OTP boxes, the mode
// tiles and every screen in the dark theme.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/features/auth/presentation/widgets/auth_code_fields.dart';
import 'package:family_hub/features/auth/presentation/widgets/family_form.dart';
import 'package:family_hub/shared/models/models.dart';

import 'auth_test_utils.dart';

void main() {
  final l10n = enL10n;

  SystemUiOverlayStyle style() => SystemChrome.latestStyle!;

  group('status bar', () {
    testWidgets('welcome: transparent over the gradient hero, white icons', (
      tester,
    ) async {
      await pumpAuthApp(tester, location: AppRoutes.welcome);
      await settle(tester);

      expect(style().statusBarColor, Colors.transparent);
      expect(style().statusBarIconBrightness, Brightness.light);
      expect(style().statusBarBrightness, Brightness.dark); // iOS
    });

    testWidgets('welcome: icons turn dark once the hero scrolled away', (
      tester,
    ) async {
      await pumpAuthApp(tester, location: AppRoutes.welcome, textScale: 1.4);
      // A very short viewport (e.g. landscape with large text and the
      // keyboard), so the whole hero can scroll away.
      tester.view.physicalSize = const Size(960, 600);
      await settle(tester);
      expect(style().statusBarIconBrightness, Brightness.light);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -2000));
      await settle(tester);

      expect(style().statusBarColor, Colors.transparent);
      expect(style().statusBarIconBrightness, Brightness.dark);
    });

    testWidgets('canvas screens: transparent, dark icons in the light theme', (
      tester,
    ) async {
      final app = await pumpAuthApp(tester, location: AppRoutes.welcome);
      await tester.tap(find.text(l10n.authWelcomeHaveAccount));
      await settle(tester);
      expect(app.router.state.uri.path, AppRoutes.login);

      expect(style().statusBarColor, Colors.transparent);
      expect(style().statusBarIconBrightness, Brightness.dark);
      expect(style().statusBarBrightness, Brightness.light);
    });

    testWidgets('canvas screens: white icons in the dark theme', (
      tester,
    ) async {
      await pumpAuthApp(
        tester,
        location: AppRoutes.login,
        theme: AppTheme.dark(),
      );
      await settle(tester);

      expect(style().statusBarColor, Colors.transparent);
      expect(style().statusBarIconBrightness, Brightness.light);
    });
  });

  group('OTP boxes', () {
    testWidgets('draw the typed digits, one per box', (tester) async {
      await pumpAuthApp(
        tester,
        location: AppRoutes.verifyEmail,
        auth: FakeAuthRepository(account: completeSession(verified: false)),
        signedIn: true,
      );

      await tester.enterText(find.byType(OtpCodeField), '4 2 7');
      await tester.pump();

      for (final digit in ['4', '2', '7']) {
        expect(
          find.descendant(
            of: find.byType(OtpCodeField),
            matching: find.text(digit),
          ),
          findsOneWidget,
        );
      }
      expect(find.text(l10n.authOtpLabel), findsOneWidget);
    });

    testWidgets('an incomplete code is explained under the boxes', (
      tester,
    ) async {
      final auth = FakeAuthRepository(
        account: completeSession(verified: false),
      );
      await pumpAuthApp(
        tester,
        location: AppRoutes.verifyEmail,
        auth: auth,
        signedIn: true,
      );

      await tester.enterText(find.byType(OtpCodeField), '12');
      await tester.tap(find.text(l10n.authVerifyButton));
      await settle(tester);

      expect(find.text(l10n.validationOtp), findsOneWidget);
      expect(auth.count('verifyEmail'), 0);
    });
  });

  testWidgets('mode tiles: the chosen mode is selected for screen readers', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpAuthApp(tester, location: AppRoutes.register());

    expect(
      tester.getSemantics(find.text(l10n.authWelcomeCreateFamily)),
      containsSemantics(isButton: true, isSelected: true),
    );
    expect(
      tester.getSemantics(find.text(l10n.authWelcomeJoinFamily)),
      containsSemantics(isButton: true, isSelected: false),
    );

    await tester.tap(find.text(l10n.authWelcomeJoinFamily));
    await settle(tester);
    expect(
      tester.getSemantics(find.text(l10n.authWelcomeJoinFamily)),
      containsSemantics(isButton: true, isSelected: true),
    );
    expect(find.byType(FamilyModeSelector), findsOneWidget);
    semantics.dispose();
  });

  group('dark theme', () {
    final screens = <String, ({String location, SessionState? account})>{
      'welcome': (location: AppRoutes.welcome, account: null),
      'login': (location: AppRoutes.login, account: null),
      'register': (location: AppRoutes.register(), account: null),
      'forgot password': (location: AppRoutes.forgotPassword, account: null),
      'verify email': (
        location: AppRoutes.verifyEmail,
        account: completeSession(verified: false),
      ),
      'family setup': (
        location: AppRoutes.familySetup,
        account: SessionState(user: testUser(withFamily: false)),
      ),
    };
    for (final entry in screens.entries) {
      testWidgets('${entry.key} renders on the dark canvas', (tester) async {
        final account = entry.value.account;
        await pumpAuthApp(
          tester,
          location: entry.value.location,
          auth: FakeAuthRepository(account: account),
          signedIn: account != null,
          theme: AppTheme.dark(),
        );
        await settle(tester);

        expect(tester.takeException(), isNull);
        final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).last);
        final context = tester.element(find.byWidget(scaffold));
        expect(Theme.of(context).brightness, Brightness.dark);
        expect(
          Theme.of(context).scaffoldBackgroundColor,
          AppSemanticColors.dark.canvas,
        );
      });
    }
  });
}
