import 'dart:async';
import 'dart:developer' as developer;

import 'package:family_hub/app.dart';
import 'package:family_hub/core/providers/core_providers.dart';
import 'package:family_hub/core/services/push_notification_service.dart';
import 'package:family_hub/firebase_options.dart';
import 'package:family_hub/shared/providers/shared_providers.dart'
    show apiRetryPolicy;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting();
  final prefs = await SharedPreferences.getInstance();

  if (await _initFirebase()) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      // App-wide default for every provider (Riverpod 3 would otherwise
      // retry 10x and show a spinner for ~40 s on a 403 / 404). Same policy
      // the feature data providers pass explicitly.
      retry: apiRetryPolicy,
      child: const FamilyHubApp(),
    ),
  );
}

/// Initialises Firebase for push notifications. Returns `false` (and the app
/// runs without push) when Firebase is not configured for this build
/// (`lib/firebase_options.dart` stub) or initialisation fails.
Future<bool> _initFirebase() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 10));
    return true;
  } on Object catch (error, stack) {
    developer.log(
      'Firebase not initialised - push notifications disabled',
      name: 'FamilyHub',
      error: error,
      stackTrace: stack,
    );
    return false;
  }
}
