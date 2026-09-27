import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/network/api_client.dart';
import 'package:family_hub/core/network/mock/mock_backend.dart';
import 'package:family_hub/core/network/mock/mock_interceptor.dart';
import 'package:family_hub/features/notices/data/notices_mock_handlers.dart';
import 'package:family_hub/features/notices/data/notices_repository.dart';

/// End-to-end: [NoticesRepository] → [ApiClient] → Dio → [MockInterceptor]
/// → the `/notices` mock handlers (contract §9).
void main() {
  const aaravUserId = '64f1a0000000000000000103';
  const otherFamilyId = '64f1a0000000000000000002';
  const otherFamilyNoticeId = '64f1a0000000000000000799';
  const pinnedId = '64f1a0000000000000000701';
  const priyaNoticeId = '64f1a0000000000000000702';

  late MockBackend backend;

  ApiClient apiAs(String userId) {
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
    addTearDown(dio.close);
    return ApiClient(dio);
  }

  NoticesRepository repoAs(String userId) => NoticesRepository(apiAs(userId));

  late NoticesRepository admin; // Amit
  late NoticesRepository member; // Aarav (plain member)

  Future<ApiException> apiError(Future<Object?> call) async {
    try {
      await call;
    } on ApiException catch (e) {
      return e;
    }
    fail('expected an ApiException');
  }

  setUp(() {
    backend = MockBackend(MockDb());
    registerNoticeMocks(backend);
    final db = backend.db;
    // Give Aarav an account so a plain member can call the API.
    db.insert(MockDb.users, {
      'id': aaravUserId,
      'email': MockSeed.aaravEmail,
      'name': 'Aarav',
      'emailVerified': true,
      'familyId': MockSeed.familyId,
      'memberId': MockSeed.aaravMemberId,
    });
    db.update(MockDb.members, MockSeed.aaravMemberId, {'userId': aaravUserId});
    // Another family's notice must never be visible.
    db.insert(MockDb.notices, {
      'id': otherFamilyNoticeId,
      'familyId': otherFamilyId,
      'title': 'Secret',
      'body': 'Other family',
      'pinned': true,
      'authorId': '64f1a0000000000000000999',
    });
    admin = repoAs(MockSeed.amitUserId);
    member = repoAs(aaravUserId);
  });

  group('GET /notices', () {
    test('seed: 4 notices, pinned first, then newest first', () async {
      final page = await member.list();
      expect(page.total, 4);
      expect(page.hasMore, isFalse);
      expect(page.items.first.title, mockPinnedNoticeTitle);
      expect(page.items.first.pinned, isTrue);
      expect(page.items.where((n) => n.pinned), hasLength(1));
      final rest = page.items.skip(1).toList();
      for (var i = 1; i < rest.length; i++) {
        expect(
          rest[i - 1].createdAt.isAfter(rest[i].createdAt),
          isTrue,
          reason: 'unpinned notices are newest first',
        );
      }
      expect(page.items.map((n) => n.id), isNot(contains(otherFamilyNoticeId)));
      expect(page.items.any((n) => n.hasImage), isTrue);
      expect(page.items.first.authorName, 'Amit');
    });

    test('paginates with meta', () async {
      final first = await member.list(limit: 3);
      expect(first.items, hasLength(3));
      expect(first.hasMore, isTrue);
      final second = await member.list(page: 2, limit: 3);
      expect(second.items, hasLength(1));
      expect(second.hasMore, isFalse);
      expect({
        ...first.items.map((n) => n.id),
        ...second.items.map((n) => n.id),
      }, hasLength(4));
    });

    test('author name and avatar are resolved at read time', () async {
      backend.db.update(MockDb.members, MockSeed.amitMemberId, {
        'name': 'Amit S.',
        'avatarUrl': 'https://res.cloudinary.com/demo/image/upload/a.jpg',
      });
      final pinned = (await member.list()).items.first;
      expect(pinned.authorName, 'Amit S.');
      expect(pinned.authorAvatarUrl, contains('res.cloudinary.com'));
    });

    test('user without a family → 403 NO_FAMILY', () async {
      backend.db.insert(MockDb.users, {
        'id': '64f1a0000000000000000109',
        'email': 'solo@familyhub.app',
        'familyId': null,
        'memberId': null,
      });
      final e = await apiError(repoAs('64f1a0000000000000000109').list());
      expect(e.code, ApiErrorCode.noFamily);
      expect(e.statusCode, 403);
    });
  });

  group('POST /notices', () {
    test('member post: pinned is ignored, author is the caller', () async {
      final n = await member.create(
        const NoticeDraft(
          title: ' Cricket at 5 ',
          body: 'Bring the bat',
          pinned: true,
        ),
      );
      expect(n.title, 'Cricket at 5');
      expect(n.pinned, isFalse);
      expect(n.authorId, MockSeed.aaravMemberId);
      expect(n.authorName, 'Aarav');
      final board = (await member.list()).items;
      expect(board[1].id, n.id, reason: 'newest unpinned right after pinned');
    });

    test('admin post can be pinned and goes to the very top', () async {
      final n = await admin.create(
        const NoticeDraft(title: 'Holiday', body: 'Diwali plans', pinned: true),
      );
      expect(n.pinned, isTrue);
      expect((await member.list()).items.first.id, n.id);
    });

    test('validation errors carry field details', () async {
      var e = await apiError(
        member.create(const NoticeDraft(title: '   ', body: 'x')),
      );
      expect(e.code, ApiErrorCode.validation);
      expect(e.statusCode, 422);
      expect(e.details?['title'], isNotNull);

      e = await apiError(
        member.create(NoticeDraft(title: 'a' * 101, body: 'b' * 2001)),
      );
      expect(e.details?.keys, containsAll(['title', 'body']));

      e = await apiError(
        member.create(
          const NoticeDraft(
            title: 't',
            body: 'b',
            imageUrl: 'https://evil.example.com/x.jpg',
          ),
        ),
      );
      expect(e.details?['imageUrl'], isNotNull);

      e = await apiError(
        member.create(
          const NoticeDraft(
            title: 't',
            body: 'b',
            imageUrl: 'http://res.cloudinary.com/demo/x.jpg',
          ),
        ),
      );
      expect(e.details?['imageUrl'], isNotNull, reason: 'https only');
    });

    test('accepts Cloudinary URLs and local mock-upload paths', () async {
      final cloud = await member.create(
        const NoticeDraft(
          title: 't',
          body: 'b',
          imageUrl: 'https://res.cloudinary.com/demo/image/upload/x.jpg',
        ),
      );
      expect(cloud.imageUrl, contains('res.cloudinary.com'));
      final local = await member.create(
        const NoticeDraft(title: 't', body: 'b', imageUrl: '/tmp/pick.jpg'),
      );
      expect(local.imageUrl, '/tmp/pick.jpg');
    });
  });

  group('PATCH /notices/:id', () {
    test('member cannot edit someone else\'s notice', () async {
      final e = await apiError(
        member.update(pinnedId, NoticePatch(title: 'Hacked')),
      );
      expect(e.code, ApiErrorCode.forbidden);
    });

    test('author edits own notice; pin needs an admin', () async {
      final mine = await member.create(
        const NoticeDraft(title: 'Mine', body: 'Text', imageUrl: '/tmp/a.jpg'),
      );
      final edited = await member.update(
        mine.id,
        NoticePatch(title: 'Mine (edited)', clearImage: true),
      );
      expect(edited.title, 'Mine (edited)');
      expect(edited.imageUrl, isNull);

      final e = await apiError(member.update(mine.id, NoticePatch.pin(true)));
      expect(e.code, ApiErrorCode.forbidden);

      // Sending the unchanged value is harmless.
      final same = await member.update(mine.id, NoticePatch.pin(false));
      expect(same.pinned, isFalse);
    });

    test('admin pins / unpins anyone\'s notice', () async {
      final pinned = await admin.update(priyaNoticeId, NoticePatch.pin(true));
      expect(pinned.pinned, isTrue);
      final board = (await member.list()).items;
      expect(
        board.take(2).map((n) => n.id),
        containsAll([pinnedId, priyaNoticeId]),
      );
      final unpinned = await admin.update(pinnedId, NoticePatch.pin(false));
      expect(unpinned.pinned, isFalse);
    });

    test('other family / unknown → 404, malformed id → 400', () async {
      var e = await apiError(
        admin.update(otherFamilyNoticeId, NoticePatch(title: 'x')),
      );
      expect(e.code, ApiErrorCode.notFound);
      e = await apiError(
        admin.update('64f1a0000000000000000abc', NoticePatch(title: 'x')),
      );
      expect(e.code, ApiErrorCode.notFound);
      e = await apiError(admin.update('not-an-id', NoticePatch(title: 'x')));
      expect(e.code, ApiErrorCode.badRequest);
    });

    test('invalid body → 422 before any lookup', () async {
      final e = await apiError(
        admin.update(pinnedId, NoticePatch(body: 'x' * 2001)),
      );
      expect(e.code, ApiErrorCode.validation);
      expect(e.details?['body'], isNotNull);
    });
  });

  group('DELETE /notices/:id', () {
    test('member cannot delete others; admin can; then 404', () async {
      var e = await apiError(member.delete(priyaNoticeId));
      expect(e.code, ApiErrorCode.forbidden);

      await admin.delete(priyaNoticeId);
      expect((await member.list()).total, 3);

      e = await apiError(admin.delete(priyaNoticeId));
      expect(e.code, ApiErrorCode.notFound);
    });

    test('author deletes own notice; other family → 404', () async {
      final mine = await member.create(
        const NoticeDraft(title: 'Temp', body: 'x'),
      );
      await member.delete(mine.id);
      final e = await apiError(admin.delete(otherFamilyNoticeId));
      expect(e.code, ApiErrorCode.notFound);
      expect(
        backend.db.findById(MockDb.notices, otherFamilyNoticeId),
        isNotNull,
      );
    });
  });

  group('backend parity (edge cases)', () {
    const soloUserId = '64f1a0000000000000000109';

    void addUserWithoutFamily() => backend.db.insert(MockDb.users, {
      'id': soloUserId,
      'email': 'solo@familyhub.app',
      'familyId': null,
      'memberId': null,
    });

    test(
      'NO_FAMILY is checked before the id format (like the routes)',
      () async {
        addUserWithoutFamily();
        final solo = repoAs(soloUserId);
        var e = await apiError(
          solo.update('not-an-id', NoticePatch(title: 'x')),
        );
        expect(e.code, ApiErrorCode.noFamily);
        e = await apiError(solo.delete('not-an-id'));
        expect(e.code, ApiErrorCode.noFamily);
      },
    );

    test('pinned must be a real boolean: null → 422', () async {
      final api = apiAs(MockSeed.amitUserId);
      var e = await apiError(
        api.post('/notices', body: {'title': 't', 'body': 'b', 'pinned': null}),
      );
      expect(e.code, ApiErrorCode.validation);
      expect(e.details?['pinned'], isNotNull);
      e = await apiError(
        api.patch('/notices/$pinnedId', body: {'pinned': 'true'}),
      );
      expect(e.details?['pinned'], isNotNull);
    });

    test('an unchanged PATCH writes nothing and keeps updatedAt', () async {
      final before = backend.db.findById(MockDb.notices, priyaNoticeId)!;
      final same = await admin.update(
        priyaNoticeId,
        NoticePatch(title: before['title'] as String, pinned: false),
      );
      expect(same.updatedAt.toIso8601String(), isNot(isEmpty));
      expect(
        backend.db.findById(MockDb.notices, priyaNoticeId)!['updatedAt'],
        before['updatedAt'],
      );

      final edited = await admin.update(
        priyaNoticeId,
        NoticePatch(body: 'New text'),
      );
      expect(edited.body, 'New text');
      expect(edited.updatedAt.isAfter(same.updatedAt), isTrue);
    });

    test(
      'a removed author shows as unknown (Former member), not stale',
      () async {
        backend.db.remove(MockDb.members, MockSeed.priyaMemberId);
        final n = (await member.list()).items.firstWhere(
          (n) => n.id == priyaNoticeId,
        );
        expect(n.authorName, isEmpty);
        expect(n.authorAvatarUrl, isNull);
        expect(n.authorId, MockSeed.priyaMemberId);
        // Only an admin can still edit or delete it.
        final e = await apiError(member.delete(priyaNoticeId));
        expect(e.code, ApiErrorCode.forbidden);
        await admin.delete(priyaNoticeId);
      },
    );

    test('an author who moved to another family is unknown too', () async {
      backend.db.update(MockDb.members, MockSeed.priyaMemberId, {
        'familyId': otherFamilyId,
      });
      final json = mockFamilyNotices(
        backend.db,
        MockSeed.familyId,
      ).firstWhere((n) => n['id'] == priyaNoticeId);
      expect(json['authorName'], isNull);
      expect(json['authorAvatarUrl'], isNull);
    });

    test('very long, RTL and emoji text within the limits round-trips', () async {
      final title = 'اجتماع العائلة 👨‍👩‍👧 ${'x' * 60}';
      final body = 'परिवार ${'🙂' * 900}';
      expect(body.length, lessThanOrEqualTo(2000));
      final n = await member.create(NoticeDraft(title: title, body: body));
      expect(n.title, title);
      expect(n.body, body);
      // 1001 emoji = 2002 UTF-16 code units → over the limit, like the backend.
      final e = await apiError(
        member.create(NoticeDraft(title: 't', body: '🙂' * 1001)),
      );
      expect(e.details?['body'], isNotNull);
    });

    test('a page past the end is empty with hasMore false', () async {
      final page = await member.list(page: 9, limit: 20);
      expect(page.items, isEmpty);
      expect(page.hasMore, isFalse);
      expect(page.total, 4);
    });
  });

  group('NoticesRepository.findById', () {
    test('finds a notice by paging the board', () async {
      final n = await member.findById(priyaNoticeId);
      expect(n.id, priyaNoticeId);
    });

    test('unknown / other family / blank → NOT_FOUND', () async {
      for (final id in [otherFamilyNoticeId, '64f1a0000000000000000abc', ' ']) {
        final e = await apiError(member.findById(id));
        expect(e.code, ApiErrorCode.notFound, reason: id);
      }
    });
  });

  test('mockFamilyNotices serializes the contract shape', () {
    final list = mockFamilyNotices(backend.db, MockSeed.familyId);
    expect(list, hasLength(4));
    expect(list.first.keys, {
      'id',
      'title',
      'body',
      'imageUrl',
      'pinned',
      'authorId',
      'authorName',
      'authorAvatarUrl',
      'createdAt',
      'updatedAt',
    });
    expect(list.first.containsKey('familyId'), isFalse);
  });

  test('seeding is idempotent', () {
    registerNoticeMocks(backend);
    seedMockNotices(backend.db);
    expect(
      backend.db.count(
        MockDb.notices,
        (d) => d['familyId'] == MockSeed.familyId,
      ),
      4,
    );
  });
}
