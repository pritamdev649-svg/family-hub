// Every auth screen on a small phone with large text (1.4×, the app's
// maximum) in a right-to-left layout: no overflow, no exceptions.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/shared/models/models.dart';

import 'auth_test_utils.dart';

void main() {
  final screens = <String, ({String location, SessionState? account})>{
    'welcome': (location: AppRoutes.welcome, account: null),
    'login': (location: AppRoutes.login, account: null),
    'register (create)': (location: AppRoutes.register(), account: null),
    'register (join)': (
      location: AppRoutes.register(mode: AppRoutes.registerModeJoin),
      account: null,
    ),
    'forgot password': (location: AppRoutes.forgotPassword, account: null),
    'verify email': (
      location: AppRoutes.verifyEmail,
      account: completeSession(verified: false),
    ),
    'family setup': (
      location: AppRoutes.familySetup,
      account: SessionState(user: testUser(withFamily: false)),
    ),
    'family setup (invite link)': (
      location: '${AppRoutes.familySetup}?code=K7Q2M9XD',
      account: SessionState(user: testUser(withFamily: false)),
    ),
  };

  for (final entry in screens.entries) {
    testWidgets('${entry.key}: large text + RTL on a 320 dp phone', (
      tester,
    ) async {
      final account = entry.value.account;
      await pumpAuthApp(
        tester,
        location: entry.value.location,
        auth: FakeAuthRepository(account: account),
        signedIn: account != null,
        textScale: 1.4,
        textDirection: TextDirection.rtl,
      );
      // Narrow phone after the harness picked its tall surface.
      tester.view.physicalSize = const Size(960, 4800);
      await settle(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(Scaffold), findsWidgets);
    });
  }
}
