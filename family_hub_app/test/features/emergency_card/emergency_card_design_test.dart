import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/utils/url_actions.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/emergency_card/application/emergency_card_providers.dart';
import 'package:family_hub/features/emergency_card/presentation/screens/emergency_card_responder_screen.dart';
import 'package:family_hub/features/emergency_card/presentation/widgets/emergency_header_scroll_view.dart';

import 'emergency_card_test_utils.dart';

/// The "modern & colourful" redesign (docs/12-DESIGN_LANGUAGE.md,
/// docs/progress/rd-emergency.md): gradient headers behind a transparent
/// status bar, tappable content where it overlaps the header, the
/// always-dark responder view, the dark theme and the blood group chips.
void main() {
  late FakeEmergencyCardRepository repo;
  late InMemorySecureStore secure;
  late List<Uri> launched;

  setUp(() {
    repo = FakeEmergencyCardRepository();
    secure = InMemorySecureStore();
    launched = [];
    UrlActions.launcherOverride = (uri, mode) async {
      launched.add(uri);
      return true;
    };
  });

  tearDown(() => UrlActions.launcherOverride = null);

  /// A phone-sized surface with a 24 px status bar.
  void phone(WidgetTester tester, {double height = 800}) {
    tester.view.physicalSize = Size(400, height);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 24);
    tester.view.viewPadding = const FakeViewPadding(top: 24);
    addTearDown(tester.view.reset);
  }

  Future<void> pump(
    WidgetTester tester,
    String location, {
    ThemeData? theme,
  }) async {
    await pumpEmergencyApp(
      tester,
      location: location,
      theme: theme,
      overrides: emergencyOverrides(
        prefs: await mockPrefs(),
        repository: repo,
        secure: secure,
      ),
    );
    await tester.pump();
  }

  void expectTransparentStatusBar({required Brightness icons}) {
    final style = SystemChrome.latestStyle;
    expect(style?.statusBarColor, Colors.transparent);
    expect(style?.statusBarIconBrightness, icons);
    expect(
      style?.systemNavigationBarColor,
      isNull,
      reason: 'the navigation bar is left to the system',
    );
  }

  group('gradient header behind a transparent status bar', () {
    testWidgets('card: light icons over the header, dark once scrolled away', (
      tester,
    ) async {
      phone(tester);
      repo.cards[kamla.id] = fullCard(kamla.id);
      await pump(tester, '/emergency-cards/${kamla.id}');

      // Full bleed: the header starts at the very top, behind the status
      // bar; its controls sit below the status bar.
      expect(tester.getTopLeft(find.byType(GradientHeader)).dy, 0);
      expect(
        tester.getTopLeft(find.byTooltip('Back')).dy,
        greaterThanOrEqualTo(24),
      );
      expect(find.byType(AppBar), findsNothing);
      expectTransparentStatusBar(icons: Brightness.light);

      await tester.drag(
        find.byType(EmergencyHeaderScrollView),
        const Offset(0, -1500),
      );
      await tester.pumpAndSettle();
      expectTransparentStatusBar(icons: Brightness.dark);
    });

    testWidgets('list: same header and status bar', (tester) async {
      phone(tester);
      await pump(tester, '/emergency-cards');
      expect(tester.getTopLeft(find.byType(GradientHeader)).dy, 0);
      expect(find.byType(AppBar), findsNothing);
      expectTransparentStatusBar(icons: Brightness.light);
      // Glass stats in the header.
      expect(find.text('Family members'), findsOneWidget);
      expect(find.text('Cards complete'), findsOneWidget);
    });

    testWidgets('form: plain canvas app bar, transparent status bar', (
      tester,
    ) async {
      phone(tester);
      await pump(tester, '/emergency-cards/${amit.id}/edit');
      expect(find.byType(AppBar), findsOneWidget);
      expectTransparentStatusBar(icons: Brightness.dark);
    });
  });

  group('content overlapping the header is tappable', () {
    testWidgets('top edge of "Show to responder"', (tester) async {
      phone(tester);
      repo.cards[kamla.id] = fullCard(kamla.id);
      await pump(tester, '/emergency-cards/${kamla.id}');

      final card = tester.getRect(
        find.ancestor(
          of: find.text('Show to responder'),
          matching: find.byType(GradientCard),
        ),
      );
      final header = tester.getRect(find.byType(GradientHeader));
      expect(card.top, lessThan(header.bottom), reason: 'overlaps the header');

      await tester.tapAt(Offset(card.center.dx, card.top + 4));
      await tester.pumpAndSettle();
      expect(find.byType(EmergencyCardResponderScreen), findsOneWidget);
    });

    testWidgets('top edge of the emergency number card', (tester) async {
      phone(tester);
      await pump(tester, '/emergency-cards');
      final card = tester.getRect(
        find.ancestor(
          of: find.text('In danger? Call 112'),
          matching: find.byType(GradientCard),
        ),
      );
      await tester.tapAt(Offset(card.center.dx, card.top + 4));
      await tester.pump();
      expect(launched.single.toString(), 'tel:112');
    });
  });

  testWidgets('responder view stays dark and high-contrast in the light '
      'theme', (tester) async {
    phone(tester, height: 3200);
    repo.cards[kamla.id] = fullCard(kamla.id);
    await pump(tester, '/emergency-cards/${kamla.id}');
    await tester.tap(find.text('Show to responder'));
    await tester.pumpAndSettle();

    final responder = find.byType(EmergencyCardResponderScreen);
    final context = tester.element(
      find.descendant(of: responder, matching: find.byType(Scaffold)),
    );
    final theme = Theme.of(context);
    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, AppSemanticColors.dark.canvas);
    // Huge, near-white text on the near-black canvas.
    final name = tester.widget<Text>(
      find.descendant(of: responder, matching: find.text('Kamla')),
    );
    expect(name.style?.color, theme.colorScheme.onSurface);
    expect(
      theme.colorScheme.onSurface.computeLuminance(),
      greaterThan(0.8),
      reason: 'maximum contrast',
    );
    expectTransparentStatusBar(icons: Brightness.light);
  });

  testWidgets('dark theme: list, card, responder and form render cleanly', (
    tester,
  ) async {
    phone(tester, height: 4000);
    repo.cards[kamla.id] = fullCard(kamla.id);
    final dark = AppTheme.dark();

    await pump(tester, '/emergency-cards', theme: dark);
    expect(tester.takeException(), isNull);
    expect(find.text('O+'), findsOneWidget);
    expectTransparentStatusBar(icons: Brightness.light);

    await tester.tap(find.text('Kamla'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Dr. Rao'), findsOneWidget);

    await tester.tap(find.text('Show to responder'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Close responder view'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Edit card'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Edit emergency card'), findsOneWidget);
    expectTransparentStatusBar(icons: Brightness.light);
  });

  testWidgets('blood group is picked with colourful chips and saved', (
    tester,
  ) async {
    phone(tester, height: 3200);
    await pump(tester, '/emergency-cards/${amit.id}/edit');

    ChoiceChip chip(String label) => tester.widget<ChoiceChip>(
      find.ancestor(of: find.text(label), matching: find.byType(ChoiceChip)),
    );
    expect(chip('Unknown').selected, isTrue);
    expect(chip('AB-').selected, isFalse);
    // Borderless (docs/12-DESIGN_LANGUAGE.md §5).
    expect(chip('AB-').side, BorderSide.none);

    await tester.tap(find.text('AB-'));
    await tester.pump();
    expect(chip('AB-').selected, isTrue);
    expect(chip('Unknown').selected, isFalse);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repo.saveCalls.single.$2.bloodGroup, BloodGroup.abNegative);
  });
}
