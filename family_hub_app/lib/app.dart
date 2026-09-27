import 'dart:async';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/router/app_router.dart';
import 'package:family_hub/core/services/push_notification_service.dart';
import 'package:family_hub/core/settings/settings_controller.dart';
import 'package:family_hub/core/settings/text_scale.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Root widget: theme, locale, text scale and routing.
///
/// Also starts push notifications and routes notification taps (including
/// the tap that cold-started the app) through [DeepLinkOpener], which waits
/// for the session to be restored before navigating.
class FamilyHubApp extends ConsumerStatefulWidget {
  const FamilyHubApp({super.key});

  @override
  ConsumerState<FamilyHubApp> createState() => _FamilyHubAppState();
}

class _FamilyHubAppState extends ConsumerState<FamilyHubApp> {
  // Themes are pure functions of the design tokens: build them once.
  final ThemeData _lightTheme = AppTheme.light();
  final ThemeData _darkTheme = AppTheme.dark();

  StreamSubscription<String>? _routeTaps;

  @override
  void initState() {
    super.initState();
    final push = ref.read(pushNotificationServiceProvider);
    // Subscribe before init() so the cold-start tap is not missed.
    _routeTaps = push.routeTaps.listen(
      (route) => ref.read(deepLinkOpenerProvider).open(route),
      onError: (Object e, StackTrace s) => _log('route tap failed: $e'),
    );
    unawaited(
      Future<void>.sync(push.init).catchError(
        (Object e) => _log('push init failed: $e'),
      ),
    );
  }

  @override
  void dispose() {
    unawaited(_routeTaps?.cancel());
    super.dispose();
  }

  static void _log(String message) {
    if (kDebugMode) debugPrint('[App] $message');
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(goRouterProvider);
    final locale = ref.watch(resolvedLocaleProvider);
    final themeMode = ref.watch(settingsControllerProvider.select((s) => s.themeMode));
    final largeText = ref.watch(settingsControllerProvider.select((s) => s.largeText));

    return MaterialApp.router(
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => context.l10n.appName,
      theme: _lightTheme,
      darkTheme: _darkTheme,
      themeMode: themeMode,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        // App-wide fallback: transparent status bar with icons that contrast
        // with the theme's canvas. App bars and the gradient header override
        // it with their own nested region.
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: AppSystemUi.forTheme(Theme.of(context)),
          child: MediaQuery(
            data: media.copyWith(
              textScaler: AppTextScale.resolve(
                media.textScaler,
                largeText: largeText,
              ),
            ),
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}
