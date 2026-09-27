import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:family_hub/core/providers/core_providers.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/utils/url_actions.dart';
import 'package:family_hub/features/emergency_card/application/emergency_card_providers.dart';
import 'package:family_hub/features/emergency_card/data/emergency_card_offline_store.dart';
import 'package:family_hub/features/emergency_card/data/emergency_card_repository.dart';
import 'package:family_hub/features/sos/domain/sos_alert.dart';
import 'package:family_hub/features/sos/presentation/screens/sos_alert_screen.dart';
import 'package:family_hub/features/sos/presentation/screens/sos_screen.dart';
import 'package:family_hub/features/sos/presentation/widgets/sos_alert_tile.dart';
import 'package:family_hub/features/sos/presentation/widgets/sos_button.dart';
import 'package:family_hub/features/sos/presentation/widgets/sos_status_banner.dart';
import 'package:family_hub/features/sos/sos_routes.dart';
import 'package:family_hub/shared/models/member.dart';

import 'sos_test_utils.dart';

/// Routes around the SOS feature: the SOS tab, a home tab with the banner,
/// the feature's full-screen routes and a stand-in for the location
/// settings.
List<RouteBase> _routes() => [
  GoRoute(path: AppRoutes.sos, builder: (context, state) => const SosScreen()),
  GoRoute(
    path: AppRoutes.home,
    builder: (context, state) => const Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SosStatusBanner(),
          Expanded(child: Center(child: Text('home tab'))),
        ],
      ),
    ),
  ),
  ...sosRoutes,
  GoRoute(
    path: AppRoutes.settingsLocation,
    builder: (context, state) =>
        const Scaffold(body: Text('location settings')),
  ),
];

/// A tall window so the whole SOS tab is built.
void _tallWindow(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await settle(tester);
}

class _FakeCardRepository implements EmergencyCardRepository {
  @override
  Future<EmergencyCard> getCard(String memberId) async {
    await Future<void>.delayed(Duration.zero);
    return EmergencyCard(
      memberId: memberId,
      bloodGroup: BloodGroup.bPositive,
      allergies: const ['Peanuts'],
    );
  }

  @override
  Future<EmergencyCard> saveCard(String memberId, EmergencyCard card) =>
      throw UnimplementedError();
}

class _MemoryStore implements SecureKeyValueStore {
  final data = <String, String>{};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
  @override
  Future<void> delete(String key) async => data.remove(key);
  @override
  Future<Map<String, String>> readAll() async => Map.of(data);
}

Future<List<Override>> _cardOverrides() async {
  SharedPreferences.setMockInitialValues(const {});
  final prefs = await SharedPreferences.getInstance();
  return [
    sharedPreferencesProvider.overrideWithValue(prefs),
    emergencyCardRepositoryProvider.overrideWithValue(_FakeCardRepository()),
    emergencyCardSecureStoreProvider.overrideWithValue(_MemoryStore()),
  ];
}

void main() {
  final launched = <Uri>[];

  setUp(() {
    launched.clear();
    UrlActions.launcherOverride = (uri, mode) async {
      launched.add(uri);
      return true;
    };
  });
  tearDown(() => UrlActions.launcherOverride = null);

  group('SosScreen', () {
    testWidgets('idle: button, emergency number, disclaimer, sharing mode', (
      tester,
    ) async {
      _tallWindow(tester);
      final h = SosHarness();
      await pumpSosApp(
        tester,
        overrides: h.overrides,
        routes: _routes(),
        location: AppRoutes.sos,
      );
      await settle(tester);

      final semantics = tester.ensureSemantics();
      await tester.pump();
      expect(
        find.bySemanticsLabel('Send an SOS alert to your family'),
        findsOneWidget,
      );
      semantics.dispose();
      expect(
        find.text('Tap to alert your family. You can cancel within 3 seconds.'),
        findsOneWidget,
      );
      expect(find.text('Alerts your family only'), findsOneWidget);
      expect(find.text('Only during SOS'), findsOneWidget);
      expect(
        find.text('No one in your family needs help right now.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Call emergency services 112'));
      await settle(tester);
      expect(launched.single.toString(), 'tel:112');

      await tester.tap(find.text('Your location during SOS'));
      await tester.pumpAndSettle();
      expect(find.text('location settings'), findsOneWidget);
      await _finish(tester);
    });

    testWidgets('countdown can be cancelled; nothing is sent', (tester) async {
      _tallWindow(tester);
      final h = SosHarness();
      await pumpSosApp(
        tester,
        overrides: h.overrides,
        routes: _routes(),
        location: AppRoutes.sos,
      );
      await settle(tester);

      await tester.tap(find.byType(SosButton));
      await tester.pump();
      expect(find.text('3'), findsOneWidget);
      expect(find.text('Sending in 3 seconds'), findsOneWidget);

      await advance(tester, h.clock, const Duration(seconds: 1));
      expect(find.text('2'), findsOneWidget);

      await tester.tap(find.text('Cancel SOS'));
      await settle(tester);
      expect(find.text('SOS cancelled. Nobody was alerted.'), findsOneWidget);
      expect(find.text('Cancel SOS'), findsNothing);

      await advance(tester, h.clock, const Duration(seconds: 5));
      expect(h.repository.createCalls, isEmpty);
      await _finish(tester);
    });

    testWidgets('sends after the countdown, then "I am okay" ends it', (
      tester,
    ) async {
      _tallWindow(tester);
      final h = SosHarness(fix: fixAt(testNow));
      await pumpSosApp(
        tester,
        overrides: h.overrides,
        routes: _routes(),
        location: AppRoutes.sos,
      );
      await settle(tester);

      await tester.tap(find.byType(SosButton));
      await tester.pump();
      for (var i = 0; i < 3; i++) {
        await advance(tester, h.clock, const Duration(seconds: 1));
      }
      await settle(tester, 10);

      expect(h.repository.createCalls, hasLength(1));
      expect(find.text('Your family has been alerted.'), findsOneWidget);
      expect(find.text('Your SOS is active'), findsOneWidget);
      expect(
        find.text('Sharing your live location with family'),
        findsOneWidget,
      );
      expect(find.text('Ends in 15:00'), findsOneWidget);
      expect(h.location.isTracking, isTrue);

      await tester.tap(find.text('I am okay'));
      await settle(tester, 10);
      expect(h.repository.resolveCalls.single.$2, SosResolution.safe);
      expect(
        find.text('Glad you are okay. Your family has been told.'),
        findsOneWidget,
      );
      expect(find.text('Your SOS is active'), findsNothing);
      expect(h.location.isTracking, isFalse);
      await _finish(tester);
    });

    testWidgets('sharing "never": asks, then sends without location', (
      tester,
    ) async {
      _tallWindow(tester);
      final h = SosHarness(
        member: amit.copyWith(locationSharing: LocationSharingMode.never),
      );
      await pumpSosApp(
        tester,
        overrides: h.overrides,
        routes: _routes(),
        location: AppRoutes.sos,
      );
      await settle(tester);
      await tester.tap(find.byType(SosButton));
      await tester.pump();
      for (var i = 0; i < 3; i++) {
        await advance(tester, h.clock, const Duration(seconds: 1));
      }
      await tester.pump();
      expect(find.text('Share your location?'), findsOneWidget);
      await tester.tap(find.text('Send without location'));
      await settle(tester, 10);

      expect(h.repository.createCalls.single, isNull);
      expect(
        find.text('Your family has been alerted, without your location.'),
        findsOneWidget,
      );
      expect(find.text('Your location is not being shared'), findsOneWidget);
      await _finish(tester);
    });

    testWidgets('shows other members\' active alerts', (tester) async {
      _tallWindow(tester);
      final h = SosHarness();
      h.repository.alerts['p1'] = alertFor(priya, id: 'p1');
      await pumpSosApp(
        tester,
        overrides: h.overrides,
        routes: _routes(),
        location: AppRoutes.sos,
      );
      await settle(tester);
      expect(find.byType(SosAlertTile), findsOneWidget);
      expect(find.text('Priya needs help'), findsOneWidget);
      expect(find.text('Live location'), findsOneWidget);
      await _finish(tester);
    });
  });

  group('SosStatusBanner', () {
    testWidgets('hidden without active alerts', (tester) async {
      final h = SosHarness();
      await pumpSosApp(
        tester,
        overrides: h.overrides,
        routes: _routes(),
        location: AppRoutes.home,
      );
      await settle(tester);
      expect(find.text('home tab'), findsOneWidget);
      expect(find.text('Open'), findsNothing);
      expect(find.text('I am okay'), findsNothing);
      await _finish(tester);
    });

    testWidgets('"<name> needs help" opens the alert', (tester) async {
      final h = SosHarness();
      h.repository.alerts['p1'] = alertFor(priya, id: 'p1');
      await pumpSosApp(
        tester,
        overrides: h.overrides,
        routes: _routes(),
        location: AppRoutes.home,
      );
      await settle(tester);
      expect(find.text('Priya needs help'), findsOneWidget);
      await tester.tap(find.text('Open'));
      await settle(tester, 10);
      expect(find.byType(SosAlertScreen), findsOneWidget);
      expect(find.text('Priya needs help'), findsWidgets);
      await _finish(tester);
    });

    testWidgets('several alerts show a count', (tester) async {
      final h = SosHarness();
      h.repository.alerts['p1'] = alertFor(priya, id: 'p1');
      h.repository.alerts['k1'] = alertFor(
        priya.copyWith(id: 'm-kamla', name: 'Kamla'),
        id: 'k1',
      );
      await pumpSosApp(
        tester,
        overrides: h.overrides,
        routes: _routes(),
        location: AppRoutes.home,
      );
      await settle(tester);
      expect(find.text('2 family members need help'), findsOneWidget);
      await _finish(tester);
    });

    testWidgets('own active alert: "I am okay" resolves it', (tester) async {
      final h = SosHarness();
      h.repository.alerts['mine'] = alertFor(amit, id: 'mine');
      await pumpSosApp(
        tester,
        overrides: h.overrides,
        routes: _routes(),
        location: AppRoutes.home,
      );
      await settle(tester, 10);
      expect(
        find.text('Your SOS is active – sharing live location'),
        findsOneWidget,
      );
      await tester.tap(find.text('I am okay'));
      await settle(tester, 10);
      expect(h.repository.resolveCalls.single, ('mine', SosResolution.safe));
      expect(find.text('I am okay'), findsNothing);
      await _finish(tester);
    });
  });

  group('SosAlertScreen', () {
    testWidgets('someone else\'s alert: location, calls, card, helped', (
      tester,
    ) async {
      _tallWindow(tester);
      final h = SosHarness();
      h.repository.alerts['p1'] = alertFor(
        priya,
        id: 'p1',
        message: 'Car broke down',
        lastLocation: GeoPoint(
          lat: 28.6139,
          lng: 77.209,
          accuracy: 12,
          recordedAt: testNow.subtract(const Duration(seconds: 20)),
        ),
        trail: [
          GeoPoint(lat: 28.61, lng: 77.2, recordedAt: testNow),
          GeoPoint(lat: 28.6139, lng: 77.209, recordedAt: testNow),
        ],
      );
      await pumpSosApp(
        tester,
        overrides: [...h.overrides, ...await _cardOverrides()],
        routes: _routes(),
        location: AppRoutes.sosAlert('p1'),
      );
      await settle(tester, 10);

      expect(find.text('Priya needs help'), findsOneWidget);
      expect(find.text('Car broke down'), findsOneWidget);
      expect(find.text('28.613900, 77.209000'), findsOneWidget);
      expect(find.text('Accurate to about 12 m'), findsOneWidget);
      expect(find.text('Updated 20 seconds ago'), findsOneWidget);
      expect(find.text('Recent locations'), findsOneWidget);
      expect(find.text('Emergency card'), findsOneWidget);
      expect(find.text('Peanuts'), findsOneWidget);

      await tester.tap(find.text('Open in Maps'));
      await settle(tester);
      expect(launched.last.host, 'www.google.com');
      await tester.tap(find.text('Call Priya'));
      await settle(tester);
      expect(launched.last.toString(), 'tel:+919876543211');

      // Amit is an admin: mark as helped (with confirmation).
      await tester.tap(find.text('Mark as helped'));
      await tester.pumpAndSettle();
      expect(find.text('End this SOS?'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Mark as helped'),
        ),
      );
      await settle(tester, 10);
      expect(h.repository.resolveCalls.single, ('p1', SosResolution.helped));
      expect(find.text('The SOS was marked as helped.'), findsOneWidget);
      expect(find.text('Helped'), findsWidgets);
      await _finish(tester);
    });

    testWidgets('an unknown alert shows "not available"', (tester) async {
      final h = SosHarness();
      await pumpSosApp(
        tester,
        overrides: h.overrides,
        routes: _routes(),
        location: AppRoutes.sosAlert('missing'),
      );
      await settle(tester, 10);
      expect(find.text('Alert not available'), findsOneWidget);
      await tester.tap(find.text('Go to SOS'));
      await tester.pumpAndSettle();
      expect(find.byType(SosScreen), findsOneWidget);
      await _finish(tester);
    });
  });

  group('SosHistoryScreen', () {
    testWidgets('lists ended alerts; empty state', (tester) async {
      final h = SosHarness();
      h.repository.historyPage = Paged<SosAlert>(
        items: [
          alertFor(
            priya,
            id: 'old',
            status: SosStatus.resolved,
            startedAt: testNow.subtract(const Duration(days: 3)),
            resolution: SosResolution.safe,
            resolvedAt: testNow.subtract(const Duration(days: 3)),
          ),
        ],
        page: 1,
        limit: 20,
        total: 1,
        hasMore: false,
      );
      await pumpSosApp(
        tester,
        overrides: h.overrides,
        routes: _routes(),
        location: AppRoutes.sosHistory,
      );
      await settle(tester, 10);
      expect(find.text('SOS history'), findsOneWidget);
      expect(find.text('Priya'), findsOneWidget);
      expect(find.text('Safe'), findsOneWidget);
      await _finish(tester);

      final empty = SosHarness();
      await pumpSosApp(
        tester,
        overrides: empty.overrides,
        routes: _routes(),
        location: AppRoutes.sosHistory,
      );
      await settle(tester, 10);
      expect(find.text('No past alerts'), findsOneWidget);
      await _finish(tester);
    });
  });
}
