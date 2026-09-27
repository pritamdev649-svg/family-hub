import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/network/api_exception.dart';
import 'package:family_hub/core/network/mock/mock_backend.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/services/location_service.dart';
import 'package:family_hub/features/home/widgets/top_banner_slot.dart';
import 'package:family_hub/features/sos/application/sos_controller.dart';
import 'package:family_hub/features/sos/application/sos_providers.dart';
import 'package:family_hub/features/sos/data/sos_mock_handlers.dart';
import 'package:family_hub/features/sos/presentation/screens/sos_alert_screen.dart';
import 'package:family_hub/features/sos/presentation/screens/sos_screen.dart';
import 'package:family_hub/features/sos/presentation/widgets/sos_button.dart';
import 'package:family_hub/features/sos/presentation/widgets/sos_status_banner.dart';
import 'package:family_hub/features/sos/sos_routes.dart';
import 'package:family_hub/l10n/app_localizations.dart';
import 'package:family_hub/shared/models/member.dart';

import 'sos_test_utils.dart';

// Edge cases found in the hardening review (docs/progress/f-sos.md,
// "Hardening review"): questions that could hold an SOS back, stale lists
// after an alert ended, access changes on another phone, first-wins
// resolutions, rapid taps, expiry while a screen is open, the status bar
// above the banner, and the mock's shared lazy-expiry helper.

const _second = Duration(seconds: 1);

const _noFamily = ApiException(code: ApiErrorCode.noFamily, statusCode: 403);
const _forbidden = ApiException(code: ApiErrorCode.forbidden, statusCode: 403);

SosState _state(ProviderContainer c) => c.read(sosControllerProvider);

Future<void> _dispose(WidgetTester tester, ProviderContainer c) async {
  c.dispose();
  await settle(tester);
}

Future<SosLocationChoice?> _notAsked() async {
  fail('the location question must not be asked');
}

Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await settle(tester);
}

/// A tall window so whole screens are built.
void _tallWindow(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

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
];

void main() {
  group('an SOS is never held back', () {
    testWidgets('an unanswered location question sends without location '
        'after 10 s', (tester) async {
      final h = SosHarness(
        member: amit.copyWith(locationSharing: LocationSharingMode.never),
        fix: fixAt(testNow),
      );
      final c = await h.container();
      final unanswered = Completer<SosLocationChoice?>();
      final flow = c
          .read(sosControllerProvider.notifier)
          .start(
            askLocationChoice: () => unanswered.future,
            skipCountdown: true,
          );
      await settle(tester);
      await advance(tester, h.clock, const Duration(seconds: 9));
      await settle(tester);
      expect(h.repository.createCalls, isEmpty);
      expect(_state(c).phase, SosPhase.sending);

      await advance(tester, h.clock, _second);
      await settle(tester, 10);
      final outcome = await flow;
      expect(outcome.result, SosSendResult.sent);
      expect(outcome.note, SosLocationNote.sharingOff);
      expect(h.repository.createCalls.single, isNull);
      expect(h.me.calls, isEmpty, reason: 'silence never means "share"');
      expect(h.location.prompts, 0);
      await _dispose(tester, c);
    });

    testWidgets('an unanswered permission prompt sends without location; a '
        'late "allow" starts live tracking', (tester) async {
      final h = SosHarness(
        permission: LocationPermissionState.denied,
        fix: fixAt(testNow),
      );
      h.location.promptGate = Completer<LocationPermissionState>();
      final c = await h.container();
      final flow = c
          .read(sosControllerProvider.notifier)
          .start(askLocationChoice: _notAsked, skipCountdown: true);
      await settle(tester);
      await advance(tester, h.clock, const Duration(seconds: 9));
      await settle(tester);
      expect(h.repository.createCalls, isEmpty, reason: 'still waiting');

      await advance(tester, h.clock, _second);
      await settle(tester, 10);
      final outcome = await flow;
      expect(outcome.result, SosSendResult.sent);
      expect(outcome.note, SosLocationNote.permissionMissing);
      expect(h.repository.createCalls.single, isNull);
      expect(_state(c).sharing, SosSharing.unavailable);
      expect(h.location.tracks, 0);

      // The member answers the system prompt now.
      h.location.promptGate!.complete(LocationPermissionState.granted);
      await settle(tester, 10);
      expect(_state(c).sharing, SosSharing.live);
      expect(h.location.tracks, 1);
      expect(h.location.prompts, 1, reason: 'no second prompt');
      await _dispose(tester, c);
    });

    testWidgets('the location dialog answers itself with a visible '
        'countdown', (tester) async {
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
        await advance(tester, h.clock, _second);
      }
      await tester.pump();
      expect(find.text('Share your location?'), findsOneWidget);
      expect(
        find.text(
          "If you don't choose, it is sent without your location in 10 "
          'seconds.',
        ),
        findsOneWidget,
      );
      await advance(tester, h.clock, _second);
      expect(
        find.text(
          "If you don't choose, it is sent without your location in 9 "
          'seconds.',
        ),
        findsOneWidget,
      );
      for (var i = 0; i < 9; i++) {
        await advance(tester, h.clock, _second);
      }
      await settle(tester, 10);
      await tester.pumpAndSettle(); // the dialog's closing transition

      expect(find.text('Share your location?'), findsNothing);
      expect(h.repository.createCalls.single, isNull);
      expect(h.me.calls, isEmpty);
      expect(
        find.text('Your family has been alerted, without your location.'),
        findsOneWidget,
      );
      await _finish(tester);
    });
  });

  group('stale data', () {
    testWidgets('an ended alert never shows as active again from a list '
        'fetched before the end', (tester) async {
      final h = SosHarness();
      h.repository.alerts['mine'] = alertFor(amit, id: 'mine');
      h.repository.alerts['p1'] = alertFor(priya, id: 'p1');
      final c = await h.container();
      await settle(tester, 10);
      expect(_state(c).alert?.id, 'mine');

      // The refetch after each resolve is slow: the old list stays exposed.
      h.repository.activeGate = Completer<void>();
      final actions = c.read(sosAlertActionsProvider.notifier);
      final own = actions.resolve('mine', SosResolution.safe);
      await settle(tester);
      await own;
      final helped = actions.resolve('p1', SosResolution.helped);
      await settle(tester);
      await helped;

      expect(
        c.read(activeSosAlertsProvider).value?.map((a) => a.id),
        containsAll(<String>['mine', 'p1']),
        reason: 'the stale list is still loaded',
      );
      expect(c.read(myActiveSosAlertProvider), isNull, reason: 'no flash');
      expect(c.read(otherActiveSosAlertsProvider).value, isEmpty);
      expect(_state(c).phase, SosPhase.idle);

      h.repository.activeGate!.complete();
      h.repository.activeGate = null;
      await settle(tester, 10);
      expect(_state(c).phase, SosPhase.idle, reason: 'not adopted again');
      expect(h.location.isTracking, isFalse);
      await _dispose(tester, c);
    });

    testWidgets('removed from the family: a NO_FAMILY poll clears the list '
        'and resyncs the session', (tester) async {
      final h = SosHarness();
      h.repository.alerts['p1'] = alertFor(priya, id: 'p1');
      final c = await h.container();
      await settle(tester, 10);
      expect(c.read(otherActiveSosAlertsProvider).value, hasLength(1));

      h.repository.activeError = _noFamily;
      await advance(tester, h.clock, const Duration(seconds: 15));
      await settle(tester, 10);
      final list = c.read(activeSosAlertsProvider);
      expect(list.hasError, isFalse);
      expect(list.value, isEmpty, reason: 'no "Priya needs help" forever');
      expect(h.session.refreshCalls, 1);
      await _dispose(tester, c);
    });

    testWidgets('removed from the family while sending: the error is shown '
        'once (no retry) and the session resyncs', (tester) async {
      final h = SosHarness();
      h.repository.createErrors.add(_noFamily);
      final c = await h.container();
      final flow = c
          .read(sosControllerProvider.notifier)
          .start(askLocationChoice: _notAsked, skipCountdown: true);
      await settle(tester, 10);
      final outcome = await flow;
      expect(outcome.result, SosSendResult.failed);
      expect(h.repository.createCalls, hasLength(1));
      expect(_state(c).sendError, _noFamily);
      expect(h.session.refreshCalls, 1);
      await _dispose(tester, c);
    });

    testWidgets('demoted on another phone: FORBIDDEN on "Mark as helped" '
        'resyncs the session', (tester) async {
      final h = SosHarness();
      h.repository.alerts['p1'] = alertFor(priya, id: 'p1');
      h.repository.resolveError = _forbidden;
      final c = await h.container();
      await settle(tester, 10);
      final resolving = expectLater(
        c
            .read(sosAlertActionsProvider.notifier)
            .resolve('p1', SosResolution.helped),
        throwsA(_forbidden),
      );
      await settle(tester);
      await resolving;
      expect(h.session.refreshCalls, 1);
      expect(c.read(sosResolvingProvider('p1')), isNull, reason: 'not busy');
      await _dispose(tester, c);
    });
  });

  group('SosAlertScreen', () {
    testWidgets('"Mark as helped" after the owner said "I am okay": the '
        'first resolution wins and the admin is told', (tester) async {
      _tallWindow(tester);
      final h = SosHarness();
      h.repository.alerts['p1'] = alertFor(priya, id: 'p1');
      await pumpSosApp(
        tester,
        overrides: h.overrides,
        routes: _routes(),
        location: AppRoutes.sosAlert('p1'),
      );
      await settle(tester, 10);
      // Priya ends it on her phone before the admin's tap arrives.
      h.repository.alerts['p1'] = h.repository.alerts['p1']!.copyWith(
        status: SosStatus.resolved,
        resolution: () => SosResolution.safe,
        resolvedAt: () => testNow,
        resolvedById: () => priya.id,
      );
      await tester.tap(find.text('Mark as helped'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Mark as helped'),
        ),
      );
      await settle(tester, 10);
      await tester.pumpAndSettle(); // the dialog's closing transition
      expect(find.text('This SOS alert has already ended.'), findsOneWidget);
      expect(find.text('The SOS was marked as helped.'), findsNothing);
      expect(find.text('Mark as helped'), findsNothing);
      await _finish(tester);
    });

    testWidgets('the resolve actions disappear the moment the alert expires', (
      tester,
    ) async {
      _tallWindow(tester);
      final h = SosHarness();
      h.repository.alerts['p1'] = alertFor(priya, id: 'p1');
      await pumpSosApp(
        tester,
        overrides: h.overrides,
        routes: _routes(),
        location: AppRoutes.sosAlert('p1'),
      );
      await settle(tester, 10);
      expect(find.text('Mark as helped'), findsOneWidget);
      // Started 1 min before testNow: 14 minutes left.
      await advance(tester, h.clock, const Duration(minutes: 14));
      await tester.pump(_second);
      expect(find.text('Mark as helped'), findsNothing);
      expect(find.text('Ended'), findsWidgets);
      await _finish(tester);
    });

    testWidgets('an alert deleted while the screen is open shows "not '
        'available"', (tester) async {
      _tallWindow(tester);
      final h = SosHarness();
      h.repository.alerts['p1'] = alertFor(priya, id: 'p1');
      await pumpSosApp(
        tester,
        overrides: h.overrides,
        routes: _routes(),
        location: AppRoutes.sosAlert('p1'),
      );
      await settle(tester, 10);
      expect(find.text('Priya needs help'), findsOneWidget);
      h.repository.alerts.remove('p1');
      await advance(tester, h.clock, const Duration(seconds: 5));
      await settle(tester, 10);
      expect(find.text('Alert not available'), findsOneWidget);
      await _finish(tester);
    });
  });

  group('SosStatusBanner', () {
    testWidgets('a quick double tap on "Open" opens the alert once', (
      tester,
    ) async {
      final h = SosHarness();
      h.repository.alerts['p1'] = alertFor(priya, id: 'p1');
      final router = await pumpSosApp(
        tester,
        overrides: h.overrides,
        routes: _routes(),
        location: AppRoutes.home,
      );
      await settle(tester);
      await tester.tap(find.text('Open'));
      await tester.tap(find.text('Open'), warnIfMissed: false);
      await settle(tester, 10);
      await tester.pumpAndSettle();
      expect(find.byType(SosAlertScreen), findsOneWidget);
      expect(router.canPop(), isTrue);
      router.pop();
      await tester.pumpAndSettle();
      expect(find.text('home tab'), findsOneWidget, reason: 'one push only');
      await _finish(tester);
    });

    testWidgets('continues behind the transparent status bar with light '
        'status-bar icons', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 24);
      addTearDown(tester.view.reset);

      final h = SosHarness();
      h.repository.alerts['p1'] = alertFor(priya, id: 'p1');
      final boundary = GlobalKey();
      final router = GoRouter(
        initialLocation: AppRoutes.home,
        routes: [
          GoRoute(
            path: AppRoutes.home,
            builder: (context, state) => const Scaffold(
              body: TopBannerSlot(
                banner: SosStatusBanner(),
                child: Center(child: Text('home tab')),
              ),
            ),
          ),
          ...sosRoutes,
        ],
      );
      addTearDown(router.dispose);
      final theme = AppTheme.light();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: ProviderScope(
            retry: (_, _) => null,
            overrides: h.overrides,
            child: MaterialApp.router(
              theme: theme,
              locale: const Locale('en'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              routerConfig: router,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: child!,
              ),
            ),
          ),
        ),
      );
      await settle(tester, 10);
      await tester.pump();
      expect(find.text('Priya needs help'), findsOneWidget);

      // TopBannerSlot put the banner below the 24 px status bar.
      final bannerTop = tester.getTopLeft(find.byType(SosStatusBanner)).dy;
      expect(bannerTop, 24);

      final style = SystemChrome.latestStyle;
      expect(style?.statusBarIconBrightness, Brightness.light);
      expect(style?.statusBarBrightness, Brightness.dark);
      expect(style?.statusBarColor, Colors.transparent);
      expect(
        style?.systemNavigationBarColor,
        isNull,
        reason: 'the navigation bar is left to the screens',
      );

      // The strip above the banner has the banner colour.
      final sos = theme.extension<AppSemanticColors>()!.sos;
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = (await tester.runAsync(() => render.toImage()))!;
      addTearDown(image.dispose);
      final bytes = (await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
      ))!;
      int pixel(int x, int y) => bytes.getUint32((y * image.width + x) * 4);
      int rgba(Color c) =>
          ((c.r * 255).round() << 24) |
          ((c.g * 255).round() << 16) |
          ((c.b * 255).round() << 8) |
          (c.a * 255).round();
      expect(pixel(200, 5), rgba(sos), reason: 'status-bar strip');
      expect(pixel(200, 23), rgba(sos));
      await _finish(tester);
    });
  });

  group('mock', () {
    test('mockExpireStaleSosAlerts persists the lazy expiry', () {
      final db = MockDb();
      final started = DateTime.now().subtract(const Duration(minutes: 20));
      final doc = db.insert(MockDb.sosAlerts, {
        'familyId': MockSeed.familyId,
        'memberId': MockSeed.priyaMemberId,
        'status': 'active',
        'startedAt': MockDb.iso(started),
        'expiresAt': MockDb.iso(started.add(const Duration(minutes: 15))),
      });
      mockExpireStaleSosAlerts(db, MockSeed.familyId);
      expect(db.findById(MockDb.sosAlerts, doc['id'])?['status'], 'expired');
    });
  });
}
