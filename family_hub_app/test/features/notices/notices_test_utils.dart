import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/network/api_client.dart';
import 'package:family_hub/core/utils/formatters.dart';
import 'package:family_hub/features/notices/data/notices_repository.dart';
import 'package:family_hub/features/notices/domain/notice.dart';
import 'package:family_hub/features/notices/notices_routes.dart';
import 'package:family_hub/l10n/app_localizations.dart';
import 'package:family_hub/shared/models/models.dart';
import 'package:family_hub/shared/providers/shared_providers.dart';

const testFamilyId = 'f1';
const adminMemberId = 'm-admin';
const memberMemberId = 'm-member';

final DateTime testNow = DateTime.now().toUtc();

/// A notice created [age] ago.
Notice testNotice(
  String id, {
  String? title,
  String body = 'Body text',
  bool pinned = false,
  String authorId = memberMemberId,
  String authorName = 'Aarav',
  String? imageUrl,
  Duration age = const Duration(hours: 1),
}) {
  final created = testNow.subtract(age);
  return Notice(
    id: id,
    title: title ?? 'Notice $id',
    body: body,
    imageUrl: imageUrl,
    pinned: pinned,
    authorId: authorId,
    authorName: authorName,
    createdAt: created,
    updatedAt: created,
  );
}

/// In-memory [NoticesRepository] with the server's ordering, paging and
/// permission-free behaviour. Records calls; errors can be injected.
class FakeNoticesRepository implements NoticesRepository {
  FakeNoticesRepository([List<Notice> initial = const []])
    : notices = [...initial];

  final List<Notice> notices;
  final List<String> calls = [];

  /// Thrown (once) by the next [list] call.
  Object? listError;

  /// Thrown (once) by the next mutation.
  Object? mutationError;

  /// When set, mutations wait for it before answering.
  Completer<void>? gate;

  /// Thrown (once) by the next [create] **after** the notice was stored —
  /// a response lost to a timeout / dropped connection.
  Object? errorAfterCreate;

  NoticeDraft? lastDraft;
  NoticePatch? lastPatch;
  int _seq = 0;

  List<Notice> get sorted => [...notices]..sort(Notice.compareForBoard);

  Future<void> _tick() => Future<void>.delayed(Duration.zero);

  Future<void> _mutation() async {
    await _tick();
    final g = gate;
    if (g != null) await g.future;
    final error = mutationError;
    if (error != null) {
      mutationError = null;
      throw error;
    }
  }

  @override
  Future<Paged<Notice>> list({int page = 1, int limit = 20}) async {
    calls.add('list $page/$limit');
    await _tick();
    final error = listError;
    if (error != null) {
      listError = null;
      throw error;
    }
    final all = sorted;
    final start = (page - 1) * limit;
    final slice = start >= all.length
        ? const <Notice>[]
        : all.sublist(start, math.min(start + limit, all.length));
    return Paged(
      items: List.unmodifiable(slice),
      page: page,
      limit: limit,
      total: all.length,
      hasMore: start + slice.length < all.length,
    );
  }

  @override
  Future<Notice> create(NoticeDraft draft) async {
    calls.add('create');
    lastDraft = draft;
    await _mutation();
    final json = draft.toJson();
    final notice = Notice(
      id: 'new-${++_seq}',
      title: json['title'] as String,
      body: json['body'] as String,
      imageUrl: json['imageUrl'] as String?,
      pinned: json['pinned'] == true,
      authorId: adminMemberId,
      authorName: 'Amit',
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    );
    notices.add(notice);
    final lost = errorAfterCreate;
    if (lost != null) {
      errorAfterCreate = null;
      throw lost;
    }
    return notice;
  }

  @override
  Future<Notice> update(String id, NoticePatch patch) async {
    calls.add('update $id ${patch.fields}');
    lastPatch = patch;
    await _mutation();
    final index = notices.indexWhere((n) => n.id == id);
    if (index < 0) {
      throw const ApiException(code: ApiErrorCode.notFound, statusCode: 404);
    }
    final f = patch.fields;
    final updated = notices[index].copyWith(
      title: f['title'] as String?,
      body: f['body'] as String?,
      imageUrl: f.containsKey('imageUrl')
          ? () => f['imageUrl'] as String?
          : null,
      pinned: f['pinned'] as bool?,
      updatedAt: DateTime.now().toUtc(),
    );
    notices[index] = updated;
    return updated;
  }

  @override
  Future<void> delete(String id) async {
    calls.add('delete $id');
    await _mutation();
    final before = notices.length;
    notices.removeWhere((n) => n.id == id);
    if (notices.length == before) {
      throw const ApiException(code: ApiErrorCode.notFound, statusCode: 404);
    }
  }

  @override
  Future<Notice> findById(String id) async {
    calls.add('find $id');
    await _tick();
    for (final n in notices) {
      if (n.id == id) return n;
    }
    throw const ApiException(code: ApiErrorCode.notFound, statusCode: 404);
  }
}

const testFamily = Family(
  id: testFamilyId,
  name: 'Sharma Family',
  country: 'IN',
  currency: 'INR',
  timezone: 'Asia/Kolkata',
);

/// Session overrides: signed in as the admin (Amit) or a plain member
/// (Aarav), without touching the real session controller.
List<Override> sessionOverrides({bool admin = true, String? userId = 'u1'}) {
  final member = Member(
    id: admin ? adminMemberId : memberMemberId,
    familyId: testFamilyId,
    name: admin ? 'Amit' : 'Aarav',
    role: admin ? MemberRole.admin : MemberRole.member,
    hasAccount: true,
  );
  return [
    sessionUserIdProvider.overrideWithValue(userId),
    currentFamilyProvider.overrideWithValue(testFamily),
    currentMemberProvider.overrideWithValue(member),
    isAdminProvider.overrideWithValue(admin),
  ];
}

/// Overrides for a widget / container test with [repo].
List<Override> noticeOverrides(
  FakeNoticesRepository repo, {
  bool admin = true,
  String? userId = 'u1',
}) => [
  noticesRepositoryProvider.overrideWithValue(repo),
  fmtProvider.overrideWithValue(
    Fmt(locale: const Locale('en'), currency: 'INR', country: 'IN'),
  ),
  ...sessionOverrides(admin: admin, userId: userId),
];

/// Pumps the app's notice routes (plus a `/` home with a button that opens
/// [initialPush]) inside a themed, localised `MaterialApp.router`.
Future<GoRouter> pumpNoticeApp(
  WidgetTester tester, {
  required FakeNoticesRepository repo,
  bool admin = true,
  String initialPush = '/notices',
  Object? extra,
  TextDirection? textDirection,
  List<Override> overrides = const [],
  ThemeData? theme,
}) async {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => context.push(initialPush, extra: extra),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      ...noticeRoutes,
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        ...noticeOverrides(repo, admin: admin),
        ...overrides,
      ],
      child: MaterialApp.router(
        theme: theme ?? AppTheme.light(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
        builder: textDirection == null
            ? null
            : (context, child) =>
                  Directionality(textDirection: textDirection, child: child!),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return router;
}
