import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/network/api_client.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/utils/formatters.dart';
import 'package:family_hub/features/tasks/application/task_clock.dart';
import 'package:family_hub/features/tasks/application/task_controller.dart';
import 'package:family_hub/features/tasks/data/task_repository.dart';
import 'package:family_hub/features/tasks/domain/family_task.dart';
import 'package:family_hub/features/tasks/domain/task_query.dart';
import 'package:family_hub/features/tasks/domain/task_requests.dart';
import 'package:family_hub/features/tasks/presentation/screens/tasks_screen.dart';
import 'package:family_hub/features/tasks/tasks_routes.dart';
import 'package:family_hub/l10n/app_localizations.dart';
import 'package:family_hub/shared/models/member.dart';
import 'package:family_hub/shared/providers/shared_providers.dart';

// ── Members ─────────────────────────────────────────────────────────────────

const familyId = 'fam-1';

final amit = Member(
  id: 'm-amit',
  familyId: familyId,
  name: 'Amit',
  role: MemberRole.admin,
  hasAccount: true,
  dateOfBirth: DateTime.utc(1985, 2, 1),
);

final aarav = Member(
  id: 'm-aarav',
  familyId: familyId,
  name: 'Aarav',
  hasAccount: true,
  dateOfBirth: DateTime.utc(DateTime.now().year - 15, 5, 14),
);

final anaya = Member(
  id: 'm-anaya',
  familyId: familyId,
  name: 'Anaya',
  dateOfBirth: DateTime.utc(DateTime.now().year - 8, 8, 1),
);

final kamla = Member(
  id: 'm-kamla',
  familyId: familyId,
  name: 'Kamla',
  dateOfBirth: DateTime.utc(1952, 11, 3),
);

final allMembers = [amit, kamla, aarav, anaya];

// ── Tasks ───────────────────────────────────────────────────────────────────

/// Local midnight [days] from today, as the API sends date-only values.
DateTime dueIn(int days) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day + days).toUtc();
}

FamilyTask makeTask(
  String id, {
  String? title,
  Member? assignee,
  Member? creator,
  DateTime? due,
  TaskStatus status = TaskStatus.pending,
  TaskCategory category = TaskCategory.chore,
  TaskPriority priority = TaskPriority.medium,
  DateTime? updatedAt,
}) {
  final a = assignee ?? amit;
  final c = creator ?? amit;
  final created = DateTime.utc(2026, 9, 1, 10);
  return FamilyTask(
    id: id,
    title: title ?? 'Task $id',
    assigneeId: a.id,
    assigneeName: a.name,
    createdById: c.id,
    createdByName: c.name,
    dueDate: due,
    category: category,
    priority: priority,
    status: status,
    completedAt: status == TaskStatus.done ? DateTime.utc(2026, 9, 2) : null,
    completedById: status == TaskStatus.done ? c.id : null,
    createdAt: created,
    updatedAt: updatedAt ?? created,
  );
}

// ── Fake repository ─────────────────────────────────────────────────────────

/// In-memory [TaskRepository] with call recording, injectable failures and
/// an optional [gate] that holds mutations until completed.
class FakeTaskRepository extends TaskRepository {
  FakeTaskRepository([List<FamilyTask>? tasks])
    : tasks = [...?tasks],
      super(ApiClient(Dio()));

  final List<FamilyTask> tasks;
  final List<String> calls = [];
  final List<TaskDraft> drafts = [];
  final List<TaskPatch> patches = [];

  /// Thrown (once) by the next mutation.
  Object? failNextMutation;

  /// Thrown by every `list` call while set.
  Object? failList;

  /// When set, mutations wait for it before answering.
  Completer<void>? gate;

  /// Thrown by every `get` call while set (e.g. a 404 after someone else
  /// deleted the task).
  Object? failGet;

  /// How often the controller asked to re-read the session (403 recovery,
  /// see `taskSessionRefreshProvider`).
  int sessionRefreshes = 0;

  int _clock = 0;

  Future<void> _mutation(String call) async {
    calls.add(call);
    final g = gate;
    if (g != null) await g.future;
    final error = failNextMutation;
    if (error != null) {
      failNextMutation = null;
      throw error;
    }
  }

  FamilyTask _find(String id) => tasks.firstWhere(
    (t) => t.id == id,
    orElse: () =>
        throw const ApiException(code: ApiErrorCode.notFound, statusCode: 404),
  );

  void _replace(FamilyTask task) {
    final i = tasks.indexWhere((t) => t.id == task.id);
    tasks[i] = task;
  }

  DateTime _now() => DateTime.utc(2026, 9, 10).add(Duration(minutes: ++_clock));

  @override
  Future<Paged<FamilyTask>> list(
    TaskQuery query, {
    int page = 1,
    int limit = TaskRepository.pageSize,
  }) async {
    calls.add('list ${query.status.name} ${query.assigneeId} p$page');
    await Future<void>.delayed(Duration.zero);
    final error = failList;
    if (error != null) throw error;
    final matching = [
      for (final t in tasks)
        if (query.status.includes(t.status) &&
            (query.assigneeId == null || t.assigneeId == query.assigneeId))
          t,
    ];
    final start = (page - 1) * limit;
    final items = start >= matching.length
        ? <FamilyTask>[]
        : matching.sublist(start, (start + limit).clamp(0, matching.length));
    return Paged(
      items: items,
      page: page,
      limit: limit,
      total: matching.length,
      hasMore: start + items.length < matching.length,
    );
  }

  @override
  Future<FamilyTask> get(String id) async {
    calls.add('get $id');
    await Future<void>.delayed(Duration.zero);
    final error = failGet;
    if (error != null) throw error;
    return _find(id);
  }

  @override
  Future<FamilyTask> create(TaskDraft draft) async {
    await _mutation('create');
    drafts.add(draft);
    final task = FamilyTask(
      id: 'new-${tasks.length + 1}',
      title: draft.title.trim(),
      description: draft.description,
      assigneeId: draft.assigneeId,
      dueDate: draft.dueDate?.toUtc(),
      category: draft.category,
      priority: draft.priority,
      createdAt: _now(),
      updatedAt: _now(),
    );
    tasks.add(task);
    return task;
  }

  @override
  Future<FamilyTask> update(String id, TaskPatch patch) async {
    await _mutation('update $id');
    patches.add(patch);
    final f = patch.fields;
    final updated = _find(
      id,
    ).copyWith(title: f['title'] as String?, updatedAt: _now);
    _replace(updated);
    return updated;
  }

  @override
  Future<FamilyTask> complete(String id) async {
    await _mutation('complete $id');
    final done = _find(
      id,
    ).copyWith(status: TaskStatus.done, completedAt: _now, updatedAt: _now);
    _replace(done);
    return done;
  }

  @override
  Future<FamilyTask> reopen(String id) async {
    await _mutation('reopen $id');
    final open = _find(id).copyWith(
      status: TaskStatus.pending,
      completedAt: () => null,
      completedById: () => null,
      updatedAt: _now,
    );
    _replace(open);
    return open;
  }

  @override
  Future<void> delete(String id) async {
    await _mutation('delete $id');
    tasks.removeWhere((t) => t.id == id);
  }

  int count(String prefix) => calls.where((c) => c.startsWith(prefix)).length;
}

// ── Provider overrides / containers ────────────────────────────────────────

/// Session + repository overrides for [me]. [withoutMember] signs in a user
/// who has no member profile (e.g. removed from the family meanwhile).
List<Override> taskOverrides(
  FakeTaskRepository repo, {
  Member? me,
  List<Member>? members,
  bool withoutMember = false,
  DateTime Function()? clock,
}) {
  final member = me ?? amit;
  return [
    taskRepositoryProvider.overrideWithValue(repo),
    taskSessionRefreshProvider.overrideWithValue(() async {
      repo.sessionRefreshes++;
    }),
    sessionUserIdProvider.overrideWithValue('user-${member.id}'),
    currentMemberProvider.overrideWithValue(withoutMember ? null : member),
    isAdminProvider.overrideWithValue(!withoutMember && member.isAdmin),
    membersProvider.overrideWith((ref) async => members ?? allMembers),
    fmtProvider.overrideWithValue(
      Fmt(locale: const Locale('en'), currency: 'INR', country: 'IN'),
    ),
    if (clock != null) taskClockProvider.overrideWithValue(clock),
  ];
}

ProviderContainer makeContainer(FakeTaskRepository repo, {Member? me}) {
  final container = ProviderContainer(
    overrides: taskOverrides(repo, me: me),
    retry: (_, _) => null,
  );
  addTearDown(container.dispose);
  return container;
}

// ── Widget harness ──────────────────────────────────────────────────────────

/// Pumps the app's task routes (`/tasks` tab screen + [taskRoutes]) at
/// [location] with a fake repository.
Future<GoRouter> pumpTasksApp(
  WidgetTester tester,
  FakeTaskRepository repo, {
  Member? me,
  List<Member>? members,
  bool withoutMember = false,
  DateTime Function()? clock,
  String location = AppRoutes.tasks,
  TextDirection? textDirection,
  double textScale = 1,
  Size surfaceSize = const Size(480, 1600),
}) async {
  tester.view.physicalSize = surfaceSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: AppRoutes.tasks,
        builder: (context, state) => const TasksScreen(),
      ),
      ...taskRoutes,
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: taskOverrides(
        repo,
        me: me,
        members: members,
        withoutMember: withoutMember,
        clock: clock,
      ),
      child: MaterialApp.router(
        routerConfig: router,
        theme: AppTheme.light(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) {
          Widget app = MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          );
          if (textDirection != null) {
            app = Directionality(textDirection: textDirection, child: app);
          }
          return app;
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}
