// Whole-app smoke test in mock mode with the real providers (no overrides
// except SharedPreferences): splash → welcome → demo login → home shell →
// tab switch → offline banner → logout → welcome.
//
// It signs in through the session controller, not through any screen, so it
// keeps working when the feature agents replace the placeholder screens.
import 'package:family_hub/app.dart';
import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/network/mock/mock_seed.dart';
import 'package:family_hub/core/providers/core_providers.dart';
import 'package:family_hub/core/router/app_router.dart';
import 'package:family_hub/core/widgets/offline_banner.dart';
import 'package:family_hub/features/home/home_shell.dart';
import 'package:family_hub/features/home/widgets/app_nav_bar.dart';
import 'package:family_hub/shared/session/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pumps frames (advancing fake time, which also runs the mock backend's
/// simulated latency) until [condition] holds.
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  String? reason,
  Duration step = const Duration(milliseconds: 50),
  int maxSteps = 200,
}) async {
  for (var i = 0; i < maxSteps; i++) {
    if (condition()) return;
    await tester.pump(step);
  }
  expect(condition(), isTrue, reason: reason ?? 'condition not met in time');
}

/// Lets route transitions finish. `pumpAndSettle` is not used because
/// loading indicators animate forever.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('mock mode: demo login opens the home shell and logout returns '
      'to welcome', (tester) async {
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
    String location() => container
        .read(goRouterProvider)
        .routerDelegate
        .currentConfiguration
        .uri
        .path;

    // No stored tokens → the session resolves signed out → /welcome.
    await _pumpUntil(
      tester,
      () => location() == AppRoutes.welcome,
      reason: 'signed-out start should land on /welcome',
    );

    // Demo login through the real mock backend (latency included).
    final login = container
        .read(sessionControllerProvider.notifier)
        .login(email: MockSeed.demoEmail, password: MockSeed.demoPassword);
    await _pumpUntil(
      tester,
      () => location() == AppRoutes.home,
      reason: 'a complete session should redirect to /home',
    );
    await login;
    await _settle(tester);

    final l10n = AppLocalizations.of(tester.element(find.byType(HomeShell)));
    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.byType(AppNavBar), findsOneWidget);
    expect(find.byTooltip(l10n.navSosTooltip), findsOneWidget);
    expect(find.byType(OfflineBanner), findsOneWidget);
    expect(find.text(l10n.commonOffline), findsNothing);

    // Tab switching goes through the shell's branches.
    final navBar = find.byType(AppNavBar);
    await tester.tap(
      find.descendant(of: navBar, matching: find.byIcon(AppIcons.tasks)),
    );
    await _pumpUntil(tester, () => location() == AppRoutes.tasks);
    await tester.tap(
      find.descendant(of: navBar, matching: find.byIcon(AppIcons.more)),
    );
    await _pumpUntil(tester, () => location() == AppRoutes.more);

    // The offline banner follows the connectivity status.
    final connectivity = container.read(connectivityStatusProvider.notifier);
    connectivity.report(false);
    await tester.pump();
    await tester.pump(AppDurations.normal);
    expect(find.text(l10n.commonOffline), findsOneWidget);
    connectivity.report(true);
    await tester.pump();
    await tester.pump(AppDurations.normal);
    expect(find.text(l10n.commonOffline), findsNothing);

    // Logout → signed out → back to /welcome.
    final logout = container.read(sessionControllerProvider.notifier).logout();
    await _pumpUntil(
      tester,
      () => location() == AppRoutes.welcome,
      reason: 'logout should redirect to /welcome',
    );
    await logout;
    expect(await container.read(tokenStorageProvider).read(), isNull);

    // Unmount and let pending mock-latency timers finish.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });
}
