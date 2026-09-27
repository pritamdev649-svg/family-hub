import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/network/api_client.dart';
import 'package:family_hub/core/network/mock/mock_backend.dart';
import 'package:family_hub/core/network/mock/mock_interceptor.dart';
import 'package:family_hub/features/tasks/data/task_repository.dart';
import 'package:family_hub/features/tasks/data/tasks_mock_handlers.dart';
import 'package:family_hub/features/tasks/domain/family_task.dart';
import 'package:family_hub/features/tasks/domain/task_query.dart';
import 'package:family_hub/features/tasks/domain/task_requests.dart';

/// [TaskRepository] → [ApiClient] → Dio → mock backend (the contract wire
/// format end to end), signed in as [userId].
TaskRepository _repo(
  MockBackend backend, {
  String userId = MockSeed.amitUserId,
}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: MockBackend.baseUrl,
      contentType: Headers.jsonContentType,
      responseType: ResponseType.json,
    ),
  );
  dio.interceptors
    ..add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          options.headers['Authorization'] =
              'Bearer ${MockRequest.accessTokenFor(userId)}';
          handler.next(options);
        },
      ),
    )
    ..add(
      MockInterceptor(
        backend,
        minLatency: Duration.zero,
        maxLatency: Duration.zero,
      ),
    );
  return TaskRepository(ApiClient(dio));
}

void main() {
  late MockBackend backend;
  late TaskRepository repo;

  setUp(() {
    backend = MockBackend();
    registerTaskMocks(backend);
    repo = _repo(backend);
  });

  test('lists and parses the seeded tasks with paging', () async {
    final page = await repo.list(const TaskQuery(), limit: 5);
    expect(page.items, hasLength(5));
    expect(page.hasMore, isTrue);
    expect(page.items.every((t) => t.isPending), isTrue);
    expect(page.items.first.isOverdue, isTrue, reason: 'oldest due first');
    expect(page.items.every((t) => t.assigneeName.isNotEmpty), isTrue);

    final next = await repo.list(const TaskQuery(), page: 2, limit: 5);
    expect(next.page, 2);
    expect(
      next.items
          .map((t) => t.id)
          .toSet()
          .intersection(page.items.map((t) => t.id).toSet()),
      isEmpty,
    );

    final overdue = await repo.list(
      const TaskQuery(status: TaskListStatus.all, due: TaskDueFilter.overdue),
    );
    expect(overdue.items, isNotEmpty);
    expect(overdue.items.every((t) => t.isOverdue), isTrue);

    final mine = await repo.list(
      const TaskQuery(
        assigneeId: MockSeed.aaravMemberId,
        status: TaskListStatus.done,
      ),
    );
    expect(mine.items.every((t) => t.isDone), isTrue);
    expect(
      mine.items.every((t) => t.assigneeId == MockSeed.aaravMemberId),
      isTrue,
    );
  });

  test('create → update → complete → reopen → delete round trip', () async {
    final due = DateTime.now().add(const Duration(days: 3));
    final created = await repo.create(
      TaskDraft(
        title: 'Water the plants',
        description: 'Balcony only',
        assigneeId: MockSeed.kamlaMemberId,
        dueDate: DateTime(due.year, due.month, due.day),
        category: TaskCategory.chore,
        priority: TaskPriority.low,
      ),
    );
    expect(created.id, isNotEmpty);
    expect(created.assigneeName, 'Kamla');
    expect(created.createdByName, 'Amit');
    expect(created.dueDay, DateTime(due.year, due.month, due.day));

    final updated = await repo.update(
      created.id,
      TaskPatch.diff(
        created,
        title: 'Water all plants',
        description: '',
        assigneeId: created.assigneeId,
        dueDate: null,
        category: created.category,
        priority: TaskPriority.high,
      ),
    );
    expect(updated.title, 'Water all plants');
    expect(updated.description, isNull);
    expect(updated.dueDate, isNull);
    expect(updated.priority, TaskPriority.high);

    // An empty patch sends nothing and returns the current task.
    expect(await repo.update(created.id, TaskPatch()), updated);

    final done = await repo.complete(created.id);
    expect(done.isDone, isTrue);
    expect(done.completedById, MockSeed.amitMemberId);
    expect((await repo.reopen(created.id)).isPending, isTrue);

    await repo.delete(created.id);
    await expectLater(
      repo.get(created.id),
      throwsA(
        isA<ApiException>().having(
          (e) => e.code,
          'code',
          ApiErrorCode.notFound,
        ),
      ),
    );
  });

  test(
    'server validation / permission errors surface as ApiException',
    () async {
      await expectLater(
        repo.create(
          const TaskDraft(title: 'x', assigneeId: '64f1a0000000000000009999'),
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', ApiErrorCode.validation)
              .having((e) => e.details?['assigneeId'], 'field', isNotNull),
        ),
      );

      // Give Kamla (member role) an account to check member permissions.
      const kamlaUserId = '64f1a0000000000000000105';
      backend.db.insert(MockDb.users, {
        'id': kamlaUserId,
        'email': 'kamla@familyhub.app',
        'name': 'Kamla',
        'familyId': MockSeed.familyId,
        'memberId': MockSeed.kamlaMemberId,
      });
      final member = _repo(backend, userId: kamlaUserId);
      await expectLater(
        member.complete(MockTaskSeed.electricityBillId),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            ApiErrorCode.forbidden,
          ),
        ),
      );
      expect(
        (await member.complete(MockTaskSeed.bpTabletId)).isDone,
        isTrue,
        reason: 'assignee may complete',
      );
    },
  );

  test('blank ids fail fast without a request', () async {
    await expectLater(
      repo.get('  '),
      throwsA(
        isA<ApiException>().having(
          (e) => e.code,
          'code',
          ApiErrorCode.notFound,
        ),
      ),
    );
  });
}
