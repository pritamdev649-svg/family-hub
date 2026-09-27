// App-level tests: bootstrap policy, shell building blocks and a smoke test
// of the router wiring (session -> redirect -> refreshListenable).
import 'dart:async';

import 'package:family_hub/app.dart';
import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/providers/core_providers.dart';
import 'package:family_hub/core/router/app_router.dart';
import 'package:family_hub/features/home/splash_screen.dart';
import 'package:family_hub/features/home/widgets/top_banner_slot.dart';
import 'package:family_hub/shared/models/session_state.dart';
import 'package:family_hub/shared/providers/shared_providers.dart';
import 'package:family_hub/shared/session/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Session restore that the test completes by hand.
class _ManualSession extends SessionController {
  _ManualSession(this._restore);

  final Completer<SessionState> _restore;

  @override
  Future<SessionState> build() => _restore.future;
}

Widget _localizedApp(Widget home) => MaterialApp(
  theme: AppTheme.light(),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

void main() {
  // main.dart installs apiRetryPolicy as the ProviderScope default.
  group('apiRetryPolicy (app-wide provider retry)', () {
    test('retries connection and 5xx errors at most twice with backoff', () {
      const network = ApiException.network();
      expect(apiRetryPolicy(0, network), const Duration(milliseconds: 600));
      expect(apiRetryPolicy(1, network), const Duration(milliseconds: 1200));
      expect(apiRetryPolicy(2, network), isNull);

      expect(
        apiRetryPolicy(
          0,
          const ApiException(code: ApiErrorCode.internal, statusCode: 500),
        ),
        isNotNull,
      );
      expect(
        apiRetryPolicy(
          0,
          const ApiException(
            code: ApiErrorCode.serviceUnavailable,
            statusCode: 503,
          ),
        ),
        isNotNull,
      );
    });

    test(
      'never retries timeouts, 4xx, auth, cancellations or non-API errors',
      () {
        for (final error in <Object>[
          // A timeout already waited the full receive timeout.
          const ApiException.timeout(),
          const ApiException(code: ApiErrorCode.notFound, statusCode: 404),
          const ApiException(code: ApiErrorCode.forbidden, statusCode: 403),
          const ApiException(code: ApiErrorCode.validation, statusCode: 422),
          const ApiException(
            code: ApiErrorCode.tooManyRequests,
            statusCode: 429,
          ),
          const ApiException.sessionExpired(),
          const ApiException(code: ApiErrorCode.cancelled),
          const ApiException.unknown('bad json'),
          const FormatException('bad json'),
          StateError('bug'),
        ]) {
          expect(apiRetryPolicy(0, error), isNull, reason: '$error');
        }
      },
    );
  });

  group('TopBannerSlot', () {
    Future<double> childTopInset(WidgetTester tester, Widget banner) async {
      late double inset;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(padding: EdgeInsets.only(top: 24)),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: TopBannerSlot(
              banner: banner,
              child: Builder(
                builder: (context) {
                  inset = MediaQuery.paddingOf(context).top;
                  return const SizedBox.expand();
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump(); // banner height is applied one frame later
      return inset;
    }

    testWidgets('hidden banner: content keeps the status-bar inset', (
      tester,
    ) async {
      expect(await childTopInset(tester, const SizedBox.shrink()), 24);
    });

    testWidgets('visible banner: banner takes the inset, content loses it', (
      tester,
    ) async {
      const key = Key('banner');
      expect(
        await childTopInset(tester, const SizedBox(key: key, height: 40)),
        0,
      );
      expect(tester.getTopLeft(find.byKey(key)).dy, 24);
    });
  });

  testWidgets('SplashScreen shows the brand and a loading message', (
    tester,
  ) async {
    await tester.pumpWidget(_localizedApp(const SplashScreen()));
    await tester.pump();
    final l10n = AppLocalizations.of(tester.element(find.byType(SplashScreen)));
    expect(find.text(l10n.appName), findsOneWidget);
    expect(find.text(l10n.appTagline), findsOneWidget);
    expect(find.text(l10n.homeSplashLoading), findsOneWidget);
  });

  testWidgets('app starts on the splash and follows the session to welcome', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final restore = Completer<SessionState>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          sessionControllerProvider.overrideWith(() => _ManualSession(restore)),
        ],
        child: const FamilyHubApp(),
      ),
    );
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(FamilyHubApp)),
    );
    String location() => container
        .read(goRouterProvider)
        .routerDelegate
        .currentConfiguration
        .uri
        .path;

    expect(location(), AppRoutes.splash);
    expect(find.byType(SplashScreen), findsOneWidget);

    restore.complete(SessionState.signedOut);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(location(), AppRoutes.welcome);
  });
}
