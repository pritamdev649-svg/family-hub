import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/network/api_client.dart';
import 'package:family_hub/core/network/mock/mock_backend.dart';
import 'package:family_hub/core/network/mock/mock_interceptor.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/utils/formatters.dart';
import 'package:family_hub/features/ledger/application/ledger_providers.dart';
import 'package:family_hub/features/ledger/data/goal_repository.dart';
import 'package:family_hub/features/ledger/data/ledger_mock_handlers.dart';
import 'package:family_hub/features/ledger/data/ledger_repository.dart';
import 'package:family_hub/features/ledger/domain/ledger_entry.dart';
import 'package:family_hub/features/ledger/domain/ledger_requests.dart';
import 'package:family_hub/features/ledger/domain/ledger_summary.dart';
import 'package:family_hub/features/ledger/domain/savings_goal.dart';
import 'package:family_hub/features/ledger/ledger_routes.dart';
import 'package:family_hub/features/ledger/presentation/screens/money_screen.dart';
import 'package:family_hub/features/ledger/presentation/widgets/amount_field.dart';
import 'package:family_hub/l10n/app_localizations.dart';
import 'package:family_hub/shared/models/member.dart';
import 'package:family_hub/shared/providers/shared_providers.dart';

/// English / INR formatter used by every ledger widget test.
Fmt ledgerTestFmt() =>
    Fmt(locale: const Locale('en'), currency: 'INR', country: 'IN');

const testFamilyId = 'fam1';

Member testMember({
  String id = 'm-amit',
  String name = 'Amit',
  MemberRole role = MemberRole.admin,
}) => Member(
  id: id,
  familyId: testFamilyId,
  name: name,
  role: role,
  hasAccount: true,
  userId: 'u-$id',
);

LedgerEntry testEntry({
  String id = 'e1',
  LedgerType type = LedgerType.expense,
  double amount = 1250.5,
  LedgerCategory category = LedgerCategory.groceries,
  DateTime? date,
  String memberId = 'm-amit',
  String memberName = 'Amit',
  String createdById = 'm-amit',
  String? note = 'Weekly veggies',
  String? goalId,
}) => LedgerEntry(
  id: id,
  type: type,
  amount: amount,
  category: category,
  date: date ?? DateTime(2026, 9, 20),
  memberId: memberId,
  memberName: memberName,
  createdById: createdById,
  note: note,
  goalId: goalId,
);

SavingsGoal testGoal({
  String id = 'g1',
  String title = 'Goa vacation',
  double target = 60000,
  double saved = 12500,
  GoalStatus status = GoalStatus.active,
  DateTime? targetDate,
}) => SavingsGoal(
  id: id,
  title: title,
  targetAmount: target,
  savedAmount: saved,
  status: status,
  targetDate: targetDate,
  createdById: 'm-amit',
);

/// [LedgerRepository] backed by in-memory lists; records every call.
class FakeLedgerRepository extends LedgerRepository {
  FakeLedgerRepository({
    List<LedgerEntry>? entries,
    this.summaryResult,
    this.pageSizeOverride,
  }) : entries = entries ?? [],
       super(ApiClient(Dio()));

  final List<LedgerEntry> entries;
  LedgerSummary? summaryResult;
  int? pageSizeOverride;

  /// Thrown by the next `listEntries` call (then cleared).
  Object? failNextList;

  /// Thrown by the next create / update / delete (then cleared).
  Object? failNextWrite;

  /// Thrown by the next `summary` call (then cleared).
  Object? failNextSummary;

  void _throwWriteFailure() {
    final failure = failNextWrite;
    if (failure == null) return;
    failNextWrite = null;
    throw failure;
  }

  final List<({LedgerEntryQuery query, int page, int limit})> listCalls = [];
  final List<LedgerEntryInput> created = [];
  final List<(String, LedgerEntryPatch)> updated = [];
  final List<String> deleted = [];
  final List<String?> summaryCalls = [];

  @override
  Future<Paged<LedgerEntry>> listEntries({
    LedgerEntryQuery query = const LedgerEntryQuery(),
    int page = 1,
    int limit = 20,
  }) async {
    listCalls.add((query: query, page: page, limit: limit));
    final failure = failNextList;
    if (failure != null) {
      failNextList = null;
      throw failure;
    }
    final size = pageSizeOverride ?? limit;
    final matching = [
      for (final e in entries)
        if ((query.type == null || e.type == query.type) &&
            (query.goalId == null || e.goalId == query.goalId) &&
            (query.memberId == null || e.memberId == query.memberId))
          e,
    ];
    final start = (page - 1) * size;
    final slice = start >= matching.length
        ? <LedgerEntry>[]
        : matching.sublist(start, (start + size).clamp(0, matching.length));
    return Paged(
      items: slice,
      page: page,
      limit: size,
      total: matching.length,
      hasMore: start + slice.length < matching.length,
    );
  }

  @override
  Future<LedgerEntry> createEntry(LedgerEntryInput input) async {
    _throwWriteFailure();
    created.add(input);
    final entry = testEntry(
      id: 'new-${created.length}',
      type: input.type,
      amount: input.amount,
      category: input.category,
      date: input.date,
      note: input.note,
    );
    entries.insert(0, entry);
    return entry;
  }

  @override
  Future<LedgerEntry?> updateEntry(String id, LedgerEntryPatch patch) async {
    if (patch.isEmpty) return null;
    _throwWriteFailure();
    updated.add((id, patch));
    return entries.firstWhere((e) => e.id == id);
  }

  @override
  Future<void> deleteEntry(String id) async {
    _throwWriteFailure();
    deleted.add(id);
    entries.removeWhere((e) => e.id == id);
  }

  @override
  Future<LedgerSummary> summary({String? month}) async {
    summaryCalls.add(month);
    final failure = failNextSummary;
    if (failure != null) {
      failNextSummary = null;
      throw failure;
    }
    return summaryResult ?? LedgerSummary.empty(month: month ?? '');
  }
}

/// [GoalRepository] backed by an in-memory list.
class FakeGoalRepository extends GoalRepository {
  FakeGoalRepository({List<SavingsGoal>? goals})
    : goals = goals ?? [],
      super(ApiClient(Dio()));

  final List<SavingsGoal> goals;
  int listCalls = 0;

  /// Thrown by the next create / update / delete / contribute (then
  /// cleared).
  Object? failNextWrite;

  void _throwWriteFailure() {
    final failure = failNextWrite;
    if (failure == null) return;
    failNextWrite = null;
    throw failure;
  }

  final List<GoalInput> created = [];
  final List<(String, GoalPatch)> updated = [];
  final List<String> deleted = [];
  final List<(String, GoalContributionInput)> contributions = [];

  @override
  Future<List<SavingsGoal>> listGoals({
    GoalListFilter status = GoalListFilter.all,
  }) async {
    listCalls++;
    return List.of(goals);
  }

  @override
  Future<SavingsGoal> createGoal(GoalInput input) async {
    _throwWriteFailure();
    created.add(input);
    final goal = testGoal(
      id: 'g-new',
      title: input.title,
      target: input.targetAmount,
      saved: 0,
    );
    goals.add(goal);
    return goal;
  }

  @override
  Future<SavingsGoal?> updateGoal(String id, GoalPatch patch) async {
    if (patch.isEmpty) return null;
    _throwWriteFailure();
    updated.add((id, patch));
    return goals.firstWhere((g) => g.id == id);
  }

  @override
  Future<void> deleteGoal(String id) async {
    _throwWriteFailure();
    deleted.add(id);
    goals.removeWhere((g) => g.id == id);
  }

  @override
  Future<GoalContributionResult> contribute(
    String goalId,
    GoalContributionInput input,
  ) async {
    _throwWriteFailure();
    contributions.add((goalId, input));
    final index = goals.indexWhere((g) => g.id == goalId);
    final goal = goals[index];
    final saved = goal.savedAmount + input.amount;
    final next = goal.copyWith(
      savedAmount: saved,
      status: saved >= goal.targetAmount ? GoalStatus.achieved : goal.status,
    );
    goals[index] = next;
    return GoalContributionResult(
      goal: next,
      entry: testEntry(
        id: 'contrib-${contributions.length}',
        amount: input.amount,
        category: LedgerCategory.savings,
        goalId: goalId,
      ),
    );
  }
}

/// Counts background session resyncs instead of calling `/auth/me`.
class ResyncRecorder {
  int calls = 0;

  late final LedgerSessionResync resync = LedgerSessionResync(() async {
    calls++;
  });
}

/// Session + repository overrides for ledger widget / provider tests.
List<Override> ledgerOverrides({
  required FakeLedgerRepository ledger,
  required FakeGoalRepository goals,
  Member? me,
  List<Member>? members,
  bool signedIn = true,
  ResyncRecorder? resync,
  Override? isAdminOverride,
  Override? membersOverride,
}) {
  final member = me ?? testMember();
  return [
    ledgerSessionResyncProvider.overrideWithValue(
      (resync ?? ResyncRecorder()).resync,
    ),
    fmtProvider.overrideWithValue(ledgerTestFmt()),
    sessionUserIdProvider.overrideWithValue(signedIn ? member.userId : null),
    currentMemberProvider.overrideWithValue(member),
    isAdminOverride ?? isAdminProvider.overrideWithValue(member.isAdmin),
    membersOverride ??
        membersProvider.overrideWith((ref) async => members ?? [member]),
    ledgerRepositoryProvider.overrideWithValue(ledger),
    goalRepositoryProvider.overrideWithValue(goals),
  ];
}

/// Pumps [child] in a themed, localised app with [overrides].
Future<void> pumpLedgerApp(
  WidgetTester tester,
  Widget child, {
  required List<Override> overrides,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    ),
  );
}

/// Pumps the Money tab plus every ledger route behind a real [GoRouter]
/// (so `context.push` / `context.pop` work) and returns the router.
Future<GoRouter> pumpLedgerRouter(
  WidgetTester tester, {
  required List<Override> overrides,
  String initialLocation = AppRoutes.money,
}) async {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(path: AppRoutes.money, builder: (_, _) => const MoneyScreen()),
      ...ledgerRoutes,
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: overrides,
      child: MaterialApp.router(
        theme: AppTheme.light(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

/// The entry form's big amount input (`AmountField.hero`, whose caption
/// "Amount (₹)" sits above the text field rather than inside it).
Finder heroAmountInput() => find.descendant(
  of: find.byType(AmountField),
  matching: find.byType(TextField),
);

/// Makes the test surface tall enough that whole screens are built.
void useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 4800);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

/// A mock backend with the demo seed + ledger routes, and an [ApiClient]
/// talking to it as [userId] (no latency).
({MockBackend backend, ApiClient api}) mockLedgerApi({
  String userId = MockSeed.amitUserId,
}) {
  final backend = MockBackend();
  registerLedgerMocks(backend);
  final dio =
      Dio(
          BaseOptions(
            baseUrl: MockBackend.baseUrl,
            headers: {
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
  return (backend: backend, api: ApiClient(dio));
}

/// `ApiException`s as the API client throws them.
const notFoundError = ApiException(
  code: ApiErrorCode.notFound,
  statusCode: 404,
);
const forbiddenError = ApiException(
  code: ApiErrorCode.forbidden,
  statusCode: 403,
);
const noFamilyError = ApiException(
  code: ApiErrorCode.noFamily,
  statusCode: 403,
);
const timeoutError = ApiException.timeout();

/// `422 VALIDATION_ERROR` with `details` for [fields].
ApiException validationError(List<String> fields, {int status = 422}) =>
    ApiException(
      code: ApiErrorCode.validation,
      statusCode: status,
      details: {for (final f in fields) f: 'Invalid'},
    );
