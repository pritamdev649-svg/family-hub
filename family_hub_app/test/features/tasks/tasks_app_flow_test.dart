// End-to-end flow of the tasks feature in the real app (mock mode, real
// providers, real router and shell, seeded Sharma family): sign in → Tasks
// tab → complete a task → open its detail → Family view.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:family_hub/app.dart';
import 'package:family_hub/core/network/mock/mock_seed.dart';
import 'package:family_hub/core/providers/core_providers.dart';
import 'package:family_hub/core/router/app_router.dart';
import 'package:family_hub/features/tasks/presentation/screens/task_detail_screen.dart';
import 'package:family_hub/features/tasks/presentation/screens/tasks_screen.dart';
import 'package:family_hub/features/tasks/presentation/widgets/task_tile.dart';
import 'package:family_hub/shared/session/session_controller.dart';

/// Pumps frames (advancing fake time, which also runs the mock backend's
/// simulated latency) until [condition] holds. `pumpAndSettle` can't be used:
/// loading indicators animate forever.
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required String reason,
}) async {
  for (var i = 0; i < 200; i++) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(condition(), isTrue, reason: reason);
}

void main() {
  testWidgets('demo admin completes a seeded task and opens its detail', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(480, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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

    await _pumpUntil(
      tester,
      () => location() == AppRoutes.welcome,
      reason: 'starts signed out',
    );
    final login = container
        .read(sessionControllerProvider.notifier)
        .login(email: MockSeed.demoEmail, password: MockSeed.demoPassword);
    await _pumpUntil(
      tester,
      () => location() == AppRoutes.home,
      reason: 'demo login lands on /home',
    );
    await login;

    container.read(goRouterProvider).go(AppRoutes.tasks);
    await _pumpUntil(
      tester,
      () => find.text('Pay the electricity bill').evaluate().isNotEmpty,
      reason: "Amit's seeded tasks are listed",
    );
    expect(find.byType(TasksScreen), findsOneWidget);
    expect(find.text('Overdue'), findsWidgets);

    // Complete "Renew the car insurance" (Amit's own task).
    final tile = find.widgetWithText(TaskTile, 'Renew the car insurance');
    await tester.tap(
      find.descendant(of: tile, matching: find.byType(Checkbox)),
    );
    await tester.pump();
    await _pumpUntil(
      tester,
      () => find.text('Renew the car insurance').evaluate().isEmpty,
      reason: 'the refetched "My tasks" list drops the completed task',
    );

    // Its detail (via the Done view) shows who completed it.
    await tester.tap(find.text('Done'));
    await _pumpUntil(
      tester,
      () => find.text('Renew the car insurance').evaluate().isNotEmpty,
      reason: 'the task is in the Done view',
    );
    await tester.tap(find.text('Renew the car insurance'));
    await _pumpUntil(
      tester,
      () => find.text('Completed by').evaluate().isNotEmpty,
      reason: 'detail shows the completion',
    );
    expect(find.byType(TaskDetailScreen), findsOneWidget);
    expect(find.text('Reopen task'), findsOneWidget);
  });
}
