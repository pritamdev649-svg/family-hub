import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/utils/formatters.dart';
import 'package:family_hub/l10n/app_localizations.dart';

/// Formatter used by widget tests (English UI, Indian rupees).
Fmt testFmt() =>
    Fmt(locale: const Locale('en'), currency: 'INR', country: 'IN');

/// Pumps [child] inside a themed, localised `MaterialApp` + `Scaffold` with a
/// `ProviderScope` (no automatic retries, [fmtProvider] overridden).
Future<void> pumpHarness(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const [],
  ThemeData? theme,
  TextDirection? textDirection,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [fmtProvider.overrideWithValue(testFmt()), ...overrides],
      child: MaterialApp(
        theme: theme ?? AppTheme.light(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: textDirection == null
            ? null
            : (context, app) =>
                  Directionality(textDirection: textDirection, child: app!),
        home: Scaffold(body: child),
      ),
    ),
  );
}
