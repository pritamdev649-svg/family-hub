import 'package:family_hub/app.dart';
import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/providers/core_providers.dart';
import 'package:family_hub/core/widgets/gradient_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The status bar is fully transparent everywhere: app-wide fallback for
/// screens without an app bar, and the gradient header's own region.
void main() {
  group('AppSystemUi.forBackground', () {
    test('dark background -> transparent bar with light icons', () {
      final style = AppSystemUi.forBackground(Brightness.dark);
      expect(style.statusBarColor, Colors.transparent);
      expect(style.statusBarIconBrightness, Brightness.light);
      expect(style.statusBarBrightness, Brightness.dark);
      expect(style.systemStatusBarContrastEnforced, isFalse);
    });

    test('light background -> transparent bar with dark icons', () {
      final style = AppSystemUi.forBackground(Brightness.light);
      expect(style.statusBarColor, Colors.transparent);
      expect(style.statusBarIconBrightness, Brightness.dark);
      expect(style.statusBarBrightness, Brightness.light);
      expect(style.systemStatusBarContrastEnforced, isFalse);
    });

    test('leaves the system navigation bar untouched', () {
      for (final brightness in Brightness.values) {
        final style = AppSystemUi.forBackground(brightness);
        expect(style.systemNavigationBarColor, isNull);
        expect(style.systemNavigationBarDividerColor, isNull);
        expect(style.systemNavigationBarIconBrightness, isNull);
        expect(style.systemNavigationBarContrastEnforced, isNull);
      }
    });

    test('forTheme follows the theme brightness', () {
      expect(
        AppSystemUi.forTheme(AppTheme.light()),
        AppSystemUi.forBackground(Brightness.light),
      );
      expect(
        AppSystemUi.forTheme(AppTheme.dark()),
        AppSystemUi.forBackground(Brightness.dark),
      );
    });
  });

  testWidgets('app-wide fallback: a screen without an app bar gets a '
      'transparent status bar', (tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const FamilyHubApp(),
      ),
    );
    // Splash / welcome have no AppBar; let the session resolve.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byType(AppBar), findsNothing);
    final style = SystemChrome.latestStyle;
    expect(style, isNotNull);
    expect(style!.statusBarColor, Colors.transparent);
    // Light theme (test platform brightness) -> dark icons on the canvas.
    expect(style.statusBarIconBrightness, Brightness.dark);

    // Unmount so no provider timers outlive the test.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('gradient header: transparent status bar, white icons over the '
      'header and dark icons once it scrolled away', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: GradientHeaderScrollView(
            header: Text('Header'),
            children: [SizedBox(height: 3000)],
          ),
        ),
      ),
    );
    await tester.pump();

    var style = SystemChrome.latestStyle!;
    expect(style.statusBarColor, Colors.transparent);
    expect(style.statusBarIconBrightness, Brightness.light);
    // No longer forces a black Android navigation bar.
    expect(style.systemNavigationBarColor, isNull);

    await tester.drag(find.byType(ListView), const Offset(0, -1500));
    await tester.pumpAndSettle();

    style = SystemChrome.latestStyle!;
    expect(style.statusBarColor, Colors.transparent);
    expect(style.statusBarIconBrightness, Brightness.dark);
  });
}
