import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/features/notices/data/notices_repository.dart';
import 'package:family_hub/features/notices/domain/notice.dart';
import 'package:family_hub/features/notices/presentation/widgets/notice_actions.dart';

import 'notices_test_utils.dart';

void main() {
  group('Notice.fromJson', () {
    test('parses the contract shape', () {
      final n = Notice.fromJson({
        'id': '64f1a0000000000000000701',
        'title': ' Family meeting Sunday 7pm ',
        'body': 'Living room',
        'imageUrl': 'https://res.cloudinary.com/demo/image/upload/x.jpg',
        'pinned': true,
        'authorId': 'm1',
        'authorName': 'Amit',
        'authorAvatarUrl': 'https://res.cloudinary.com/demo/a.jpg',
        'createdAt': '2026-09-26T10:15:00.000Z',
        'updatedAt': '2026-09-26T11:00:00.000Z',
      });
      expect(n.id, '64f1a0000000000000000701');
      expect(n.title, 'Family meeting Sunday 7pm');
      expect(n.body, 'Living room');
      expect(n.hasImage, isTrue);
      expect(n.pinned, isTrue);
      expect(n.authorId, 'm1');
      expect(n.authorName, 'Amit');
      expect(n.authorAvatarUrl, isNotNull);
      expect(n.createdAt, DateTime.utc(2026, 9, 26, 10, 15));
      expect(n.updatedAt, DateTime.utc(2026, 9, 26, 11));
    });

    test('never throws on missing, null or wrongly typed fields', () {
      final n = Notice.fromJson({
        'id': 42,
        'title': null,
        'pinned': 'yes',
        'imageUrl': '   ',
        'authorAvatarUrl': ['not', 'a', 'url'],
        'authorName': null,
        'createdAt': 'not a date',
        'unexpected': {'nested': true},
      });
      expect(n.id, '42');
      expect(n.title, '');
      expect(n.body, '');
      expect(n.pinned, isTrue);
      expect(n.imageUrl, isNull, reason: 'blank image → no image');
      expect(n.authorAvatarUrl, isNull);
      expect(n.authorName, '');
      expect(n.createdAt, DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
      expect(n.updatedAt, n.createdAt);
    });

    test('missing createdAt falls back to updatedAt', () {
      final n = Notice.fromJson({'updatedAt': '2026-01-02T03:04:05.000Z'});
      expect(n.createdAt, DateTime.utc(2026, 1, 2, 3, 4, 5));
    });

    test('toJson round-trips and equality holds', () {
      final n = testNotice('a', imageUrl: '/tmp/x.jpg', pinned: true);
      final copy = Notice.fromJson(n.toJson());
      expect(copy, n);
      expect(copy.hashCode, n.hashCode);
      expect(n.toJson()['createdAt'], endsWith('Z'));
    });

    test('copyWith can clear the image', () {
      final n = testNotice('a', imageUrl: '/tmp/x.jpg');
      expect(n.copyWith(imageUrl: () => null).imageUrl, isNull);
      expect(n.copyWith(title: 'T').imageUrl, '/tmp/x.jpg');
    });
  });

  test('compareForBoard: pinned first, then newest, ties by id', () {
    final old = testNotice('1', age: const Duration(days: 3));
    final pinnedOld = testNotice(
      '2',
      pinned: true,
      age: const Duration(days: 9),
    );
    final newest = testNotice('3', age: const Duration(minutes: 1));
    final tieA = testNotice('4', age: const Duration(hours: 5));
    final tieB = tieA.copyWith(id: '5');
    final sorted = [old, newest, tieA, pinnedOld, tieB]
      ..sort(Notice.compareForBoard);
    expect(sorted.map((n) => n.id), ['2', '3', '5', '4', '1']);
  });

  group('NoticePermissions', () {
    final mine = testNotice('a', authorId: memberMemberId);
    final theirs = testNotice('b', authorId: adminMemberId);

    test('member: post, edit/delete own only, never pin', () {
      const p = NoticePermissions(memberId: memberMemberId, isAdmin: false);
      expect(p.canCreate, isTrue);
      expect(p.canPin, isFalse);
      expect(p.canEdit(mine), isTrue);
      expect(p.canDelete(mine), isTrue);
      expect(p.canEdit(theirs), isFalse);
      expect(p.canDelete(theirs), isFalse);
    });

    test('admin: everything', () {
      const p = NoticePermissions(memberId: adminMemberId, isAdmin: true);
      expect(p.canPin, isTrue);
      expect(p.canEdit(mine), isTrue);
      expect(p.canDelete(mine), isTrue);
    });

    test('without a member nothing is allowed', () {
      expect(NoticePermissions.none.canCreate, isFalse);
      expect(NoticePermissions.none.canEdit(mine), isFalse);
      const staleAdmin = NoticePermissions(memberId: null, isAdmin: true);
      expect(staleAdmin.canPin, isFalse);
    });

    test('action menu follows the permissions', () {
      const member = NoticePermissions(
        memberId: memberMemberId,
        isAdmin: false,
      );
      const admin = NoticePermissions(memberId: adminMemberId, isAdmin: true);
      expect(noticeActionsFor(theirs, member), [NoticeAction.copy]);
      expect(noticeActionsFor(mine, member), [
        NoticeAction.edit,
        NoticeAction.copy,
        NoticeAction.delete,
      ]);
      expect(noticeActionsFor(mine.copyWith(pinned: true), admin), [
        NoticeAction.edit,
        NoticeAction.unpin,
        NoticeAction.copy,
        NoticeAction.delete,
      ]);
    });
  });

  group('NoticeDraft', () {
    test('trims text and omits empty optional fields', () {
      const draft = NoticeDraft(title: '  Hi ', body: ' There  ');
      expect(draft.toJson(), {'title': 'Hi', 'body': 'There'});
    });

    test('sends image and pin when given', () {
      const draft = NoticeDraft(
        title: 'T',
        body: 'B',
        imageUrl: ' https://res.cloudinary.com/x.jpg ',
        pinned: false,
      );
      expect(draft.toJson(), {
        'title': 'T',
        'body': 'B',
        'imageUrl': 'https://res.cloudinary.com/x.jpg',
        'pinned': false,
      });
    });
  });

  group('NoticePatch.diff', () {
    final before = testNotice(
      'a',
      title: 'Title',
      body: 'Body',
      imageUrl: 'https://res.cloudinary.com/x.jpg',
    );

    test('no changes → empty patch', () {
      final p = NoticePatch.diff(
        before,
        title: ' Title ',
        body: 'Body',
        imageUrl: before.imageUrl,
      );
      expect(p.isEmpty, isTrue);
    });

    test('only changed fields; removing the image sends null', () {
      final p = NoticePatch.diff(
        before,
        title: 'New title',
        body: 'Body',
        imageUrl: null,
        pinned: true,
      );
      expect(p.toJson(), {
        'title': 'New title',
        'imageUrl': null,
        'pinned': true,
      });
    });

    test('blank title never clears the server value', () {
      final p = NoticePatch.diff(
        before,
        title: '   ',
        body: 'Body',
        imageUrl: before.imageUrl,
      );
      expect(p.isEmpty, isTrue);
    });

    test('pin-only patch', () {
      expect(NoticePatch.pin(false).toJson(), {'pinned': false});
    });
  });
}
