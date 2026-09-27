import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/network/mock/mock_backend.dart';
import 'package:family_hub/core/network/mock/mock_interceptor.dart';
import 'package:family_hub/core/providers/core_providers.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/utils/formatters.dart';
import 'package:family_hub/features/dashboard/application/dashboard_providers.dart';
import 'package:family_hub/features/dashboard/data/dashboard_repository.dart';
import 'package:family_hub/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:family_hub/features/sos/application/sos_runtime.dart';
import 'package:family_hub/features/sos/domain/sos_alert.dart';
import 'package:family_hub/l10n/app_localizations.dart';
import 'package:family_hub/shared/models/family.dart';
import 'package:family_hub/shared/models/member.dart';
import 'package:family_hub/shared/providers/shared_providers.dart';

// ── Fixtures ────────────────────────────────────────────────────────────────

const testFamilyId = 'fam1';
const testUserId = 'u-amit';
const testMemberId = 'm-amit';

/// Monday 21 Sep 2026, 09:30 local — a "morning" in the middle of a month.
final testNow = DateTime(2026, 9, 21, 9, 30);

Map<String, dynamic> familyJson({
  String id = testFamilyId,
  String name = 'Sharma Family',
  String? inviteCode = 'DEMO2345',
}) => {
  'id': id,
  'name': name,
  'inviteCode': inviteCode,
  'country': 'IN',
  'currency': 'INR',
  'timezone': 'Asia/Kolkata',
  'ownerId': testUserId,
  'memberCount': 3,
  'createdAt': '2026-01-01T00:00:00.000Z',
};

Map<String, dynamic> memberJson({
  String id = testMemberId,
  String? userId = testUserId,
  String name = 'Amit Sharma',
  String role = 'admin',
  String? designation = 'Head of Family',
  String familyId = testFamilyId,
  Map<String, dynamic>? lastLocation,
  String locationSharing = 'never',
}) => {
  'id': id,
  'familyId': familyId,
  'userId': userId,
  'name': name,
  'email': null,
  'phone': null,
  'avatarUrl': null,
  'dateOfBirth': '1985-02-01T00:00:00.000Z',
  'gender': null,
  'designation': designation,
  'role': role,
  'hasAccount': userId != null,
  'locationSharing': locationSharing,
  'lastLocation': lastLocation,
  'guardianConsent': false,
  'createdAt': '2026-01-01T00:00:00.000Z',
  'updatedAt': '2026-01-01T00:00:00.000Z',
};

Map<String, dynamic> statsJson(
  Map<String, dynamic> member, {
  int pending = 0,
  int overdue = 0,
  int done = 0,
}) => {
  'member': member,
  'pendingTasks': pending,
  'overdueTasks': overdue,
  'completedThisWeek': done,
};

Map<String, dynamic> taskJson({
  required String id,
  required String title,
  String assigneeId = testMemberId,
  String status = 'pending',
  String? dueDate,
}) => {
  'id': id,
  'title': title,
  'description': null,
  'assigneeId': assigneeId,
  'assigneeName': 'Amit Sharma',
  'createdById': testMemberId,
  'createdByName': 'Amit Sharma',
  'dueDate': dueDate,
  'category': 'chore',
  'priority': 'medium',
  'status': status,
  'completedAt': null,
  'completedById': null,
  'createdAt': '2026-09-01T00:00:00.000Z',
  'updatedAt': '2026-09-01T00:00:00.000Z',
};

Map<String, dynamic> goalJson({
  String id = 'g1',
  String title = 'Goa vacation',
  num target = 60000,
  num saved = 12500,
}) => {
  'id': id,
  'title': title,
  'description': null,
  'targetAmount': target,
  'savedAmount': saved,
  'targetDate': null,
  'status': 'active',
  'progress': saved / target,
  'createdById': testMemberId,
  'createdAt': '2026-08-01T00:00:00.000Z',
  'updatedAt': '2026-08-01T00:00:00.000Z',
};

Map<String, dynamic> noticeJson({
  String id = 'n1',
  String title = 'Family meeting Sunday 7pm',
  bool pinned = true,
}) => {
  'id': id,
  'title': title,
  'body': 'Everyone please join in the living room.',
  'imageUrl': null,
  'pinned': pinned,
  'authorId': testMemberId,
  'authorName': 'Amit Sharma',
  'authorAvatarUrl': null,
  'createdAt': '2026-09-20T10:00:00.000Z',
  'updatedAt': '2026-09-20T10:00:00.000Z',
};

Map<String, dynamic> sosJson({
  String id = 'sos1',
  String memberId = 'm-priya',
  String memberName = 'Priya',
  String status = 'active',
  DateTime? startedAt,
  Map<String, dynamic>? lastLocation,
}) {
  final start = startedAt ?? testNow.subtract(const Duration(minutes: 2));
  return {
    'id': id,
    'memberId': memberId,
    'memberName': memberName,
    'memberPhone': '+919876543210',
    'memberAvatarUrl': null,
    'status': status,
    'message': null,
    'locationShared': lastLocation != null,
    'lastLocation': lastLocation,
    'trail': const <Object?>[],
    'startedAt': start.toUtc().toIso8601String(),
    'expiresAt': start
        .add(const Duration(minutes: 15))
        .toUtc()
        .toIso8601String(),
    'resolvedAt': null,
    'resolvedById': null,
    'resolution': null,
  };
}

Map<String, dynamic> summaryJson({
  String month = '2026-09',
  String scope = 'family',
  num income = 150000,
  num expense = 42000.5,
}) => {
  'month': month,
  'currency': 'INR',
  'scope': scope,
  'income': income,
  'expense': expense,
  'net': income - expense,
  'byCategory': [
    {'type': 'income', 'category': 'salary', 'amount': income},
    {'type': 'expense', 'category': 'groceries', 'amount': expense},
  ],
};

/// A contract-shaped `GET /dashboard` payload for the demo admin Amit with
/// Priya (admin) and Aarav (member).
Map<String, dynamic> dashboardJson({
  Map<String, dynamic>? me,
  List<Map<String, dynamic>>? members,
  List<Map<String, dynamic>>? myTasks,
  List<Map<String, dynamic>>? goals,
  List<Map<String, dynamic>>? notices,
  List<Map<String, dynamic>>? activeSos,
  Map<String, dynamic>? monthSummary,
  Map<String, dynamic>? family,
}) {
  final amit = me ?? memberJson();
  return {
    'family': family ?? familyJson(),
    'me': amit,
    'members':
        members ??
        [
          statsJson(amit, pending: 2, overdue: 1, done: 3),
          statsJson(
            memberJson(
              id: 'm-priya',
              userId: 'u-priya',
              name: 'Priya Sharma',
              designation: 'Finance Head',
            ),
            pending: 1,
          ),
          statsJson(
            memberJson(
              id: 'm-aarav',
              userId: null,
              name: 'Aarav',
              role: 'member',
              designation: 'Chief Study Officer',
            ),
            done: 2,
          ),
        ],
    'myTasks':
        myTasks ??
        [
          taskJson(
            id: 't1',
            title: 'Pay electricity bill',
            dueDate: '2026-09-19T18:30:00.000Z',
          ),
          taskJson(id: 't2', title: 'Book car service'),
        ],
    'goals': goals ?? [goalJson()],
    'latestNotices': notices ?? [noticeJson()],
    'activeSos': activeSos ?? const <Map<String, dynamic>>[],
    'monthSummary': monthSummary ?? summaryJson(),
  };
}

DashboardData dashboardData([Map<String, dynamic>? json]) =>
    DashboardData.fromJson(json ?? dashboardJson());

final testFamily = Family.fromJson(familyJson());
final testMe = Member.fromJson(memberJson());

// ── Fakes ───────────────────────────────────────────────────────────────────

/// [DashboardRepository] answering from a queue of [responses] (a
/// [DashboardData], an error to throw or a [Completer] to wait on); the last
/// response repeats. Records every call.
class FakeDashboardRepository extends DashboardRepository {
  FakeDashboardRepository([List<Object>? responses])
    : responses = responses ?? [dashboardData()],
      super(ApiClient(Dio()));

  final List<Object> responses;
  int calls = 0;

  @override
  Future<DashboardData> fetch() async {
    final index = calls < responses.length ? calls : responses.length - 1;
    calls++;
    final response = responses[index];
    if (response is Completer<DashboardData>) return response.future;
    if (response is DashboardData) return response;
    throw response;
  }
}

/// Counts session resyncs instead of calling `/auth/me`.
class SessionRefreshRecorder {
  int calls = 0;

  Future<void> call() async => calls++;
}

/// Mutable session for provider tests (user / family / member).
class TestSession
    extends Notifier<({String? userId, Family? family, Member? member})> {
  @override
  ({String? userId, Family? family, Member? member}) build() =>
      (userId: testUserId, family: testFamily, member: testMe);

  void set({String? userId, Family? family, Member? member}) =>
      state = (userId: userId, family: family, member: member);
}

final testSessionProvider =
    NotifierProvider<
      TestSession,
      ({String? userId, Family? family, Member? member})
    >(TestSession.new);

Future<SharedPreferences> mockPrefs([Map<String, Object> values = const {}]) {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

Fmt dashboardTestFmt() =>
    Fmt(locale: const Locale('en'), currency: 'INR', country: 'IN');

/// A clock tests can move ([now] is read on every call).
class TestClock {
  TestClock([DateTime? now]) : now = now ?? testNow;

  DateTime now;

  DateTime call() => now;
}

/// Every override a dashboard test needs: session (mutable through
/// [testSessionProvider]), repository, storage, clock and SOS feed. Pass
/// [clock] to move time during a test (else it is frozen at [now] /
/// [testNow]).
List<Override> dashboardOverrides({
  required FakeDashboardRepository repository,
  required SharedPreferences prefs,
  SessionRefreshRecorder? sessionRefresh,
  List<SosAlert>? liveSos,
  Duration fallbackDelay = const Duration(milliseconds: 50),
  DateTime? now,
  TestClock? clock,
}) {
  final time = clock ?? TestClock(now);
  final refresh = sessionRefresh ?? SessionRefreshRecorder();
  return [
    sharedPreferencesProvider.overrideWithValue(prefs),
    sessionUserIdProvider.overrideWith(
      (ref) => ref.watch(testSessionProvider).userId,
    ),
    currentFamilyProvider.overrideWith(
      (ref) => ref.watch(testSessionProvider).family,
    ),
    currentMemberProvider.overrideWith(
      (ref) => ref.watch(testSessionProvider).member,
    ),
    isAdminProvider.overrideWith(
      (ref) => ref.watch(testSessionProvider).member?.isAdmin ?? false,
    ),
    membersProvider.overrideWith((ref) async => const <Member>[]),
    fmtProvider.overrideWithValue(dashboardTestFmt()),
    dashboardRepositoryProvider.overrideWithValue(repository),
    dashboardSessionRefreshProvider.overrideWithValue(refresh.call),
    dashboardOfflineFallbackDelayProvider.overrideWithValue(fallbackDelay),
    dashboardClockProvider.overrideWithValue(time.call),
    sosClockProvider.overrideWithValue(time.call),
    dashboardLiveSosAlertsProvider.overrideWithValue(liveSos),
  ];
}

// ── Widget harness ──────────────────────────────────────────────────────────

/// Pumps the dashboard as the `/home` tab behind a real [GoRouter] whose
/// other routes are stubs that print their location (`route:/tasks`), and
/// returns the router.
Future<GoRouter> pumpDashboard(
  WidgetTester tester, {
  required List<Override> overrides,
  TextDirection? textDirection,
  double? textScale,
  bool settle = true,
  ThemeMode themeMode = ThemeMode.light,
}) async {
  Widget stub(BuildContext context, GoRouterState state) =>
      Scaffold(body: Text('route:${state.uri}'));
  final router = GoRouter(
    initialLocation: AppRoutes.home,
    routes: [
      GoRoute(path: AppRoutes.home, builder: (_, _) => const DashboardScreen()),
      for (final path in [
        AppRoutes.tasks,
        AppRoutes.taskNewPath,
        AppRoutes.taskDetailPath,
        AppRoutes.money,
        AppRoutes.ledgerEntryNewPath,
        AppRoutes.goalNew,
        AppRoutes.goalDetailPath,
        AppRoutes.members,
        AppRoutes.memberNew,
        AppRoutes.memberDetailPath,
        AppRoutes.notices,
        AppRoutes.noticeNew,
        AppRoutes.emergencyCards,
        AppRoutes.sosAlertPath,
      ])
        GoRoute(path: path, builder: stub),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: overrides,
      child: MaterialApp.router(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: themeMode,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
        builder: (context, child) {
          Widget app = child!;
          if (textScale != null) {
            app = MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: app,
            );
          }
          if (textDirection != null) {
            app = Directionality(textDirection: textDirection, child: app);
          }
          return app;
        },
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
  return router;
}

/// Sets the logical size of the test surface and, optionally, a status-bar
/// inset ([statusBar], logical pixels) like a phone with a notch.
void useSurface(WidgetTester tester, Size logicalSize, {double statusBar = 0}) {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = logicalSize * 2;
  if (statusBar > 0) {
    tester.view.padding = FakeViewPadding(top: statusBar * 2);
    tester.view.viewPadding = FakeViewPadding(top: statusBar * 2);
  }
  addTearDown(tester.view.reset);
}

// ── Mock backend ────────────────────────────────────────────────────────────

/// An [ApiClient] talking to [backend] as [userId] (no latency).
ApiClient mockApiFor(MockBackend backend, {String? userId}) {
  final dio =
      Dio(
          BaseOptions(
            baseUrl: MockBackend.baseUrl,
            headers: {
              if (userId != null)
                'Authorization': 'Bearer ${MockRequest.accessTokenFor(userId)}',
            },
          ),
        )
        ..interceptors.add(
          MockInterceptor(
            backend,
            minLatency: Duration.zero,
            maxLatency: Duration.zero,
          ),
        );
  return ApiClient(dio);
}
