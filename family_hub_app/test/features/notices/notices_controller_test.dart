import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/network/api_client.dart';
import 'package:family_hub/features/notices/application/notices_providers.dart';
import 'package:family_hub/features/notices/data/notices_repository.dart';
import 'package:family_hub/features/notices/domain/notice.dart';
import 'package:family_hub/shared/providers/shared_providers.dart';

import 'notices_test_utils.dart';

void main() {
  late FakeNoticesRepository repo;
  late ProviderContainer container;

  ProviderContainer create({bool admin = true, String? userId = 'u1'}) {
    final c = ProviderContainer(
      retry: (_, _) => null,
      overrides: noticeOverrides(repo, admin: admin, userId: userId),
    );
    addTearDown(c.dispose);
    // Keep the board alive like a mounted screen would.
    c.listen(noticeListProvider, (_, _) {});
    return c;
  }

  Future<NoticeListState> board() => container.read(noticeListProvider.future);

  int noticesVersion() =>
      container.read(dataRefreshProvider)[DataScope.notices]!;

  /// 25 notices: n0 is pinned, the rest n1 (newest) … n24 (oldest).
  List<Notice> many() => [
    testNotice('n0', pinned: true, age: const Duration(days: 30)),
    for (var i = 1; i < 25; i++) testNotice('n$i', age: Duration(minutes: i)),
  ];

  setUp(() => repo = FakeNoticesRepository(many()));

  group('NoticeListController', () {
    test('first page: pinned first, 20 items, hasMore', () async {
      container = create();
      final state = await board();
      expect(state.items, hasLength(NoticeListController.pageSize));
      expect(state.items.first.id, 'n0');
      expect(state.items[1].id, 'n1');
      expect(state.hasMore, isTrue);
      expect(repo.calls, ['list 1/20']);
    });

    test('loadMore appends the next page and stops at the end', () async {
      container = create();
      await board();
      final notifier = container.read(noticeListProvider.notifier);
      final pending = notifier.loadMore();
      expect(container.read(noticeListProvider).value!.isLoadingMore, isTrue);
      // A second call while loading is ignored.
      await notifier.loadMore();
      await pending;
      final state = container.read(noticeListProvider).value!;
      expect(state.items, hasLength(25));
      expect(state.hasMore, isFalse);
      expect(state.isLoadingMore, isFalse);
      await notifier.loadMore();
      expect(repo.calls, ['list 1/20', 'list 2/20']);
    });

    test('loadMore drops duplicates when offsets shifted', () async {
      container = create();
      await board();
      // Someone posts a notice: page 2 now starts one item earlier.
      repo.notices.add(testNotice('fresh', age: Duration.zero));
      await container.read(noticeListProvider.notifier).loadMore();
      final ids = container
          .read(noticeListProvider)
          .value!
          .items
          .map((n) => n.id);
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('loadMore failure keeps the loaded notices and rethrows', () async {
      container = create();
      await board();
      repo.listError = const ApiException.network();
      await expectLater(
        container.read(noticeListProvider.notifier).loadMore(),
        throwsA(isA<ApiException>()),
      );
      final state = container.read(noticeListProvider).value!;
      expect(state.items, hasLength(20));
      expect(state.isLoadingMore, isFalse);
      expect(state.hasMore, isTrue);
    });

    test('markChanged refetches the whole loaded window', () async {
      container = create();
      await board();
      await container.read(noticeListProvider.notifier).loadMore();
      repo.calls.clear();
      container.read(dataRefreshProvider.notifier).markChanged({
        DataScope.notices,
      });
      final state = await board();
      expect(repo.calls, ['list 1/25']);
      expect(state.items, hasLength(25));
    });

    test('signed out → empty board without a request', () async {
      container = create(userId: null);
      final state = await board();
      expect(state.isEmpty, isTrue);
      expect(repo.calls, isEmpty);
    });

    test('first-load error surfaces as AsyncError', () async {
      repo.listError = const ApiException(
        code: ApiErrorCode.forbidden,
        statusCode: 403,
      );
      container = create();
      await expectLater(board(), throwsA(isA<ApiException>()));
      expect(container.read(noticeListProvider).hasError, isTrue);
    });
  });

  group('NoticesController', () {
    NoticesController controller() =>
        container.read(noticesControllerProvider.notifier);

    test('create: shows up at once and announces the change', () async {
      container = create();
      await board();
      final before = noticesVersion();
      final created = await controller().create(
        const NoticeDraft(title: 'Dinner', body: 'At 8', pinned: true),
      );
      expect(repo.lastDraft?.pinned, isTrue);
      expect(noticesVersion(), before + 1);
      final items = container.read(noticeListProvider).value!.items;
      expect(items.first.id, created.id, reason: 'newest pinned on top');
    });

    test('setPinned re-sorts the board locally and refetches', () async {
      container = create();
      await board();
      final target = container.read(noticeListProvider).value!.find('n5')!;
      final before = noticesVersion();
      final updated = await controller().setPinned(target, true);
      expect(updated?.pinned, isTrue);
      expect(repo.lastPatch?.toJson(), {'pinned': true});
      expect(noticesVersion(), before + 1);
      final state = await board();
      expect(state.items.take(2).map((n) => n.id), ['n5', 'n0']);
    });

    test('setPinned to the current value makes no request', () async {
      container = create();
      await board();
      final pinned = container.read(noticeListProvider).value!.find('n0')!;
      await controller().setPinned(pinned, true);
      expect(repo.calls.where((c) => c.startsWith('update')), isEmpty);
    });

    test(
      'busy guard: a second mutation of the same notice is ignored',
      () async {
        container = create();
        await board();
        final target = container.read(noticeListProvider).value!.find('n3')!;
        repo.gate = Completer<void>();
        final first = controller().setPinned(target, true);
        await Future<void>.delayed(Duration.zero);
        expect(container.read(noticesControllerProvider), contains('n3'));
        expect(await controller().delete(target), isFalse);
        repo.gate!.complete();
        await first;
        expect(container.read(noticesControllerProvider), isEmpty);
        expect(repo.calls.where((c) => c.startsWith('delete')), isEmpty);
      },
    );

    test('delete removes the notice; already gone counts as deleted', () async {
      container = create();
      await board();
      final target = container.read(noticeListProvider).value!.find('n2')!;
      expect(await controller().delete(target), isTrue);
      expect(container.read(noticeListProvider).value!.find('n2'), isNull);
      // Second delete: the fake answers NOT_FOUND → still success.
      expect(await controller().delete(target), isTrue);
    });

    test('update NOT_FOUND drops the stale notice and rethrows', () async {
      container = create();
      await board();
      final target = container.read(noticeListProvider).value!.find('n4')!;
      repo.notices.removeWhere((n) => n.id == 'n4');
      await expectLater(
        controller().update(target, NoticePatch(title: 'x')),
        throwsA(
          isA<ApiException>().having((e) => e.isNotFound, 'isNotFound', true),
        ),
      );
      expect(container.read(noticeListProvider).value!.find('n4'), isNull);
      expect(container.read(noticesControllerProvider), isEmpty);
    });

    test('FORBIDDEN is rethrown and leaves the board unchanged', () async {
      container = create(admin: false);
      await board();
      final target = container.read(noticeListProvider).value!.find('n1')!;
      repo.mutationError = const ApiException(
        code: ApiErrorCode.forbidden,
        statusCode: 403,
      );
      final version = noticesVersion();
      await expectLater(
        controller().setPinned(target, true),
        throwsA(isA<ApiException>()),
      );
      expect(noticesVersion(), version);
      expect(container.read(noticeListProvider).value!.find('n1'), target);
    });

    test('empty patch returns the notice without a request', () async {
      container = create();
      await board();
      final target = container.read(noticeListProvider).value!.find('n1')!;
      final result = await controller().update(
        target,
        NoticePatch.diff(
          target,
          title: target.title,
          body: target.body,
          imageUrl: target.imageUrl,
        ),
      );
      expect(result, target);
      expect(repo.calls.where((c) => c.startsWith('update')), isEmpty);
    });
  });

  group('edge cases', () {
    NoticesController controller() =>
        container.read(noticesControllerProvider.notifier);

    test(
      'a member change (renamed / removed author) refetches the board',
      () async {
        container = create();
        await board();
        repo.calls.clear();
        container.read(dataRefreshProvider.notifier).markChanged({
          DataScope.members,
        });
        await board();
        expect(repo.calls, ['list 1/20']);
      },
    );

    test(
      'loadMore after deletions elsewhere reloads the window, skipping nothing',
      () async {
        container = create();
        await board();
        // Another member deletes two notices of the loaded first page: page 2
        // now starts two notices later than expected.
        repo.notices.removeWhere((n) => n.id == 'n1' || n.id == 'n2');
        repo.calls.clear();
        await container.read(noticeListProvider.notifier).loadMore();
        final state = await board();
        expect(repo.calls, ['list 2/20', 'list 1/23']);
        final ids = state.items.map((n) => n.id).toList();
        expect(ids, hasLength(23));
        expect(ids, isNot(contains('n1')));
        expect(ids, containsAll(['n20', 'n21']), reason: 'nothing skipped');
        expect(state.hasMore, isFalse);
      },
    );

    test(
      'create: response lost but the notice exists → no duplicate',
      () async {
        container = create();
        await board();
        repo.errorAfterCreate = const ApiException.timeout();
        final created = await controller().create(
          const NoticeDraft(title: ' Dinner ', body: 'At 8'),
        );
        expect(created.title, 'Dinner');
        expect(repo.calls.where((c) => c == 'create'), hasLength(1));
        final items = container.read(noticeListProvider).value!.items;
        expect(items.where((n) => n.id == created.id), hasLength(1));
      },
    );

    test(
      'create: timeout and nothing posted → rethrows and refetches',
      () async {
        container = create();
        await board();
        repo.mutationError = const ApiException.timeout();
        final version = noticesVersion();
        await expectLater(
          controller().create(const NoticeDraft(title: 'Dinner', body: 'At 8')),
          throwsA(
            isA<ApiException>().having(
              (e) => e.code,
              'code',
              ApiErrorCode.timeout,
            ),
          ),
        );
        expect(noticesVersion(), version + 1);
      },
    );

    test('create: still offline during the lookup → original error', () async {
      container = create();
      await board();
      repo.mutationError = const ApiException.network();
      repo.listError = const ApiException.network();
      await expectLater(
        controller().create(const NoticeDraft(title: 'Dinner', body: 'At 8')),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            ApiErrorCode.network,
          ),
        ),
      );
    });

    test('create: validation errors are not treated as uncertain', () async {
      container = create();
      await board();
      repo.mutationError = const ApiException(
        code: ApiErrorCode.validation,
        statusCode: 422,
      );
      repo.calls.clear();
      await expectLater(
        controller().create(const NoticeDraft(title: 'Dinner', body: 'At 8')),
        throwsA(isA<ApiException>()),
      );
      expect(repo.calls, ['create'], reason: 'no lookup');
    });

    test('logout resets the board and the busy set', () async {
      container = create();
      await board();
      container.read(noticesControllerProvider);
      container.updateOverrides([...noticeOverrides(repo, userId: null)]);
      final state = await board();
      expect(state.isEmpty, isTrue);
      expect(container.read(noticesControllerProvider), isEmpty);
    });
  });

  group('noticeByIdProvider', () {
    test('served from the loaded board without a request', () async {
      container = create();
      await board();
      repo.calls.clear();
      final n = await container.read(noticeByIdProvider('n7').future);
      expect(n.id, 'n7');
      expect(repo.calls, isEmpty);
    });

    test('falls back to the repository lookup', () async {
      container = ProviderContainer(
        retry: (_, _) => null,
        overrides: noticeOverrides(repo),
      );
      addTearDown(container.dispose);
      final sub = container.listen(noticeByIdProvider('n24'), (_, _) {});
      addTearDown(sub.close);
      final n = await container.read(noticeByIdProvider('n24').future);
      expect(n.id, 'n24');
      expect(repo.calls, ['find n24']);
    });
  });

  test('noticePermissionsProvider mirrors the session', () {
    container = create(admin: false);
    final p = container.read(noticePermissionsProvider);
    expect(p.memberId, memberMemberId);
    expect(p.isAdmin, isFalse);
    expect(p.canPin, isFalse);
  });
}
