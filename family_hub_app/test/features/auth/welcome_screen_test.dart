import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/providers/core_providers.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/settings/settings_controller.dart';
import 'package:family_hub/features/auth/application/session_expired_notice.dart';
import 'package:family_hub/features/auth/domain/register_args.dart';
import 'package:family_hub/features/auth/presentation/screens/login_screen.dart';
import 'package:family_hub/features/auth/presentation/screens/register_screen.dart';

import 'auth_test_utils.dart';

void main() {
  final l10n = enL10n;

  testWidgets('shows the brand and the three ways in', (tester) async {
    await pumpAuthApp(tester, location: AppRoutes.welcome);

    expect(find.text(l10n.appName), findsOneWidget);
    expect(find.text(l10n.appTagline), findsOneWidget);
    expect(find.text(l10n.authWelcomeCreateFamily), findsOneWidget);
    expect(find.text(l10n.authWelcomeJoinFamily), findsOneWidget);
    expect(find.text(l10n.authWelcomeHaveAccount), findsOneWidget);
    expect(find.text(l10n.authSessionExpiredNotice), findsNothing);
  });

  testWidgets('buttons open sign-up in the right mode and log-in', (
    tester,
  ) async {
    final app = await pumpAuthApp(tester, location: AppRoutes.welcome);

    await tester.tap(find.text(l10n.authWelcomeJoinFamily));
    await settle(tester);
    final join = tester.widget<RegisterScreen>(find.byType(RegisterScreen));
    expect(join.args.mode, RegisterMode.join);
    expect(find.text(l10n.authRegisterJoinTitle), findsOneWidget);

    app.router.pop();
    await settle(tester);
    await tester.tap(find.text(l10n.authWelcomeCreateFamily));
    await settle(tester);
    expect(
      tester.widget<RegisterScreen>(find.byType(RegisterScreen)).args.mode,
      RegisterMode.create,
    );

    app.router.pop();
    await settle(tester);
    await tester.tap(find.text(l10n.authWelcomeHaveAccount));
    await settle(tester);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('language picker lists native names and switches the app '
      'language', (tester) async {
    final app = await pumpAuthApp(tester, location: AppRoutes.welcome);

    await tester.tap(find.text('English'));
    await settle(tester);
    expect(find.text(l10n.authLanguageSheetTitle), findsOneWidget);
    expect(find.text('हिन्दी'), findsOneWidget);
    expect(find.text('العربية'), findsOneWidget);

    await tester.tap(find.text('हिन्दी'));
    await settle(tester);

    expect(app.container.read(settingsControllerProvider).localeCode, 'hi');
    expect(app.container.read(resolvedLocaleProvider).languageCode, 'hi');
  });

  testWidgets('explains an expired session', (tester) async {
    final events = AuthEvents();
    final app = await pumpAuthApp(
      tester,
      location: AppRoutes.welcome,
      events: events,
    );
    // The shell keeps the notice alive while signed in.
    app.container.listen(sessionExpiredNoticeProvider, (_, _) {});
    events.emitSessionExpired();
    await settle(tester);

    expect(find.text(l10n.authSessionExpiredNotice), findsOneWidget);
  });
}
