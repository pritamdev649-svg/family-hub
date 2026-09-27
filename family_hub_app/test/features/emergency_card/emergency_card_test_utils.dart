import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:family_hub/core/config/countries.dart';
import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/providers/core_providers.dart';
import 'package:family_hub/core/utils/formatters.dart';
import 'package:family_hub/features/emergency_card/application/emergency_card_providers.dart';
import 'package:family_hub/features/emergency_card/data/emergency_card_offline_store.dart';
import 'package:family_hub/features/emergency_card/data/emergency_card_repository.dart';
import 'package:family_hub/features/emergency_card/emergency_card_routes.dart';
import 'package:family_hub/l10n/app_localizations.dart';
import 'package:family_hub/shared/models/member.dart';
import 'package:family_hub/shared/providers/shared_providers.dart';

const testUserId = 'user-amit';

const amit = Member(
  id: 'm-amit',
  familyId: 'f1',
  userId: testUserId,
  name: 'Amit',
  phone: '+919876543210',
  designation: 'Head of Family',
  role: MemberRole.admin,
  hasAccount: true,
);

const kamla = Member(
  id: 'm-kamla',
  familyId: 'f1',
  name: 'Kamla',
  designation: 'Advisor',
);

const aarav = Member(
  id: 'm-aarav',
  familyId: 'f1',
  userId: 'user-aarav',
  name: 'Aarav',
  hasAccount: true,
);

final testMembers = [amit, kamla, aarav];

/// A fully filled-in card (every key detail present).
EmergencyCard fullCard(String memberId) => EmergencyCard(
  memberId: memberId,
  bloodGroup: BloodGroup.oPositive,
  allergies: const ['Penicillin'],
  medications: const ['Metformin 500 mg'],
  conditions: const ['Type 2 diabetes'],
  doctorName: 'Dr. Rao',
  doctorPhone: '+911123456789',
  insuranceProvider: 'Star Health',
  insurancePolicyNumber: 'SH-1',
  emergencyContacts: const [
    EmergencyContact(name: 'Amit', phone: '+919876543210', relation: 'Son'),
  ],
  notes: 'Glucose tablets in handbag',
  updatedAt: DateTime.utc(2026, 9, 1, 10),
  updatedById: 'm-amit',
);

/// In-memory [EmergencyCardRepository].
class FakeEmergencyCardRepository implements EmergencyCardRepository {
  final Map<String, EmergencyCard> cards = {};

  /// Thrown by [getCard] when set.
  Object? getError;

  /// When set, [getCard] waits for it before answering.
  Completer<void>? getGate;

  Object? saveError;
  Completer<void>? saveGate;

  final List<String> getCalls = [];
  final List<(String, EmergencyCard)> saveCalls = [];

  @override
  Future<EmergencyCard> getCard(String memberId) async {
    getCalls.add(memberId);
    await Future<void>.delayed(Duration.zero);
    final gate = getGate;
    if (gate != null) await gate.future;
    final error = getError;
    if (error != null) throw error;
    return cards[memberId] ?? EmergencyCard.empty(memberId);
  }

  @override
  Future<EmergencyCard> saveCard(String memberId, EmergencyCard card) async {
    saveCalls.add((memberId, card));
    await Future<void>.delayed(Duration.zero);
    final gate = saveGate;
    if (gate != null) await gate.future;
    final error = saveError;
    if (error != null) throw error;
    final stored = card.copyWith(
      memberId: memberId,
      updatedAt: () => DateTime.utc(2026, 9, 20),
      updatedById: () => 'm-amit',
      offlineSavedAt: () => null,
    );
    cards[memberId] = stored;
    return stored;
  }
}

/// In-memory [SecureKeyValueStore].
class InMemorySecureStore implements SecureKeyValueStore {
  final Map<String, String> data = {};
  bool fail = false;
  int writes = 0;

  void _check() {
    if (fail) throw StateError('keystore unavailable');
  }

  @override
  Future<String?> read(String key) async {
    _check();
    return data[key];
  }

  @override
  Future<void> write(String key, String value) async {
    _check();
    writes++;
    data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _check();
    data.remove(key);
  }

  @override
  Future<Map<String, String>> readAll() async {
    _check();
    return Map.of(data);
  }
}

/// Stands in for `SessionController.refreshMe` (counts the calls and runs
/// [onRefresh], e.g. to demote the signed-in member).
class SessionRefreshSpy {
  SessionRefreshSpy([this.onRefresh]);

  final void Function()? onRefresh;
  int calls = 0;

  Future<void> call() async {
    calls++;
    onRefresh?.call();
  }
}

const networkError = ApiException(code: ApiErrorCode.network);
const notFoundError = ApiException(
  code: ApiErrorCode.notFound,
  statusCode: 404,
);

Future<SharedPreferences> mockPrefs([Map<String, Object> values = const {}]) {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

/// Overrides shared by provider and widget tests: signed in as [me] (admin
/// by default), fake repository, in-memory keystore.
List<Override> emergencyOverrides({
  required SharedPreferences prefs,
  required FakeEmergencyCardRepository repository,
  required InMemorySecureStore secure,
  Member? me,
  bool? isAdmin,
  String? userId = testUserId,
  List<Member>? members,
  Object? membersError,
  Duration fallbackDelay = const Duration(seconds: 3),
  String? Function(Ref ref)? userIdBuilder,
  Member? Function(Ref ref)? meBuilder,
  SessionRefreshSpy? sessionRefresh,
}) {
  final current = me ?? amit;
  return [
    sharedPreferencesProvider.overrideWithValue(prefs),
    emergencyCardRepositoryProvider.overrideWithValue(repository),
    emergencyCardSecureStoreProvider.overrideWithValue(secure),
    emergencyCardOfflineFallbackDelayProvider.overrideWithValue(fallbackDelay),
    emergencyCardSessionRefreshProvider.overrideWithValue(
      (sessionRefresh ?? SessionRefreshSpy()).call,
    ),
    if (userIdBuilder != null)
      sessionUserIdProvider.overrideWith(userIdBuilder)
    else
      sessionUserIdProvider.overrideWithValue(userId),
    if (meBuilder != null) ...[
      currentMemberProvider.overrideWith(meBuilder),
      isAdminProvider.overrideWith(
        (ref) => ref.watch(currentMemberProvider)?.isAdmin ?? false,
      ),
    ] else ...[
      currentMemberProvider.overrideWithValue(userId == null ? null : current),
      isAdminProvider.overrideWithValue(isAdmin ?? current.isAdmin),
    ],
    currentCountryProvider.overrideWithValue(Countries.byCode('IN')),
    membersProvider.overrideWith((ref) async {
      await Future<void>.delayed(Duration.zero);
      if (membersError != null) throw membersError;
      return members ?? testMembers;
    }),
    fmtProvider.overrideWithValue(
      Fmt(locale: const Locale('en'), currency: 'INR', country: 'IN'),
    ),
  ];
}

/// Pumps the emergency card routes in a real [GoRouter] (so `context.push`
/// / `context.pop` work) starting at [location]. `/` is a blank home page
/// underneath — unless [deepLink] is set: then [location] is the only page
/// (as when opened from a link / notification). [theme] defaults to the
/// app's light theme.
Future<GoRouter> pumpEmergencyApp(
  WidgetTester tester, {
  required String location,
  required List<Override> overrides,
  TransitionBuilder? builder,
  bool deepLink = false,
  ThemeData? theme,
}) async {
  final router = GoRouter(
    initialLocation: deepLink ? location : '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(body: Text('home')),
      ),
      ...emergencyCardRoutes,
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: overrides,
      child: MaterialApp.router(
        theme: theme ?? AppTheme.light(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
        builder: builder,
      ),
    ),
  );
  if (!deepLink) unawaited(router.push(location));
  await tester.pumpAndSettle();
  return router;
}
