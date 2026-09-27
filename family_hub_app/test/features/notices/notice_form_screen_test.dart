import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart' show XFile;

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/network/api_client.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/services/cloudinary_service.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/notices/domain/notice.dart';
import 'package:family_hub/features/notices/presentation/screens/notice_form_screen.dart';
import 'package:family_hub/features/notices/presentation/widgets/notice_photo_field.dart';
import 'package:family_hub/l10n/app_localizations.dart';

import 'notices_test_utils.dart';

/// Upload service whose uploads finish only when [gate] completes.
class GatedCloudinaryService implements CloudinaryService {
  final Completer<void> gate = Completer<void>();
  final List<UploadFolder> folders = [];

  @override
  int get maxBytes => CloudinaryService.defaultMaxBytes;

  @override
  Future<String> uploadImage(
    XFile file, {
    required UploadFolder folder,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    folders.add(folder);
    await gate.future;
    return 'https://res.cloudinary.com/demo/image/upload/${file.name}';
  }
}

/// Starts an upload the way [ImagePickerField] does: through the
/// `cloudinaryServiceProvider` of the picker's own scope.
Future<String> startUpload(WidgetTester tester) {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(ImagePickerField)),
  );
  return container
      .read(cloudinaryServiceProvider)
      .uploadImage(XFile('/tmp/photo.jpg'), folder: UploadFolder.notices);
}

final l10n = lookupAppLocalizations(const Locale('en'));

Finder field(String label) => find.widgetWithText(TextFormField, label);

/// The form's own scroll view (text fields contain scrollables too).
Finder get formScrollable => find
    .descendant(
      of: find.byType(SingleChildScrollView),
      matching: find.byType(Scrollable),
    )
    .first;

/// Scrolls [finder] into view (the form is taller than the test surface)
/// and taps it.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  // A focused field keeps scrolling its caret back into view.
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder, 200, scrollable: formScrollable);
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Removes the current snackbar (it floats over the form's button).
Future<void> dismissSnackBar(WidgetTester tester) async {
  tester
      .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
      .removeCurrentSnackBar();
  await tester.pumpAndSettle();
}

void main() {
  late FakeNoticesRepository repo;

  setUp(() {
    repo = FakeNoticesRepository([
      testNotice(
        'mine',
        title: 'Old title',
        body: 'Old body',
        authorId: memberMemberId,
      ),
      testNotice('theirs', title: 'Admin notice', authorId: adminMemberId),
    ]);
  });

  testWidgets('create: required fields are validated before sending', (
    tester,
  ) async {
    await pumpNoticeApp(tester, repo: repo, initialPush: AppRoutes.noticeNew);
    await tapVisible(tester, find.text(l10n.noticesPost));
    expect(find.text(l10n.validationRequired), findsNWidgets(2));
    expect(repo.calls.where((c) => c == 'create'), isEmpty);
  });

  testWidgets('admin posts a pinned notice and returns to the board', (
    tester,
  ) async {
    await pumpNoticeApp(tester, repo: repo, initialPush: AppRoutes.noticeNew);
    expect(find.text(l10n.noticesFieldPinned), findsOneWidget);

    await tester.enterText(field(l10n.noticesFieldTitle), '  Dinner at 8  ');
    await tester.enterText(field(l10n.noticesFieldBody), 'At grandma\'s');
    await tapVisible(tester, find.byType(Switch));
    await tapVisible(tester, find.text(l10n.noticesPost));

    expect(repo.lastDraft?.toJson(), {
      'title': 'Dinner at 8',
      'body': 'At grandma\'s',
      'pinned': true,
    });
    expect(find.byType(NoticeFormScreen), findsNothing);
    expect(find.text('open'), findsOneWidget, reason: 'popped back');
    expect(find.text(l10n.noticesPosted), findsOneWidget);
  });

  testWidgets('member: no pin switch and pinned is not sent', (tester) async {
    await pumpNoticeApp(
      tester,
      repo: repo,
      admin: false,
      initialPush: AppRoutes.noticeNew,
    );
    expect(find.byType(Switch), findsNothing);
    await tester.enterText(field(l10n.noticesFieldTitle), 'Cricket');
    await tester.enterText(field(l10n.noticesFieldBody), 'At 5');
    await tapVisible(tester, find.text(l10n.noticesPost));
    expect(repo.lastDraft?.toJson().containsKey('pinned'), isFalse);
  });

  testWidgets('server validation errors are shown under the field', (
    tester,
  ) async {
    repo.mutationError = const ApiException(
      code: ApiErrorCode.validation,
      statusCode: 422,
      details: {'title': 'Title is too long'},
    );
    await pumpNoticeApp(tester, repo: repo, initialPush: AppRoutes.noticeNew);
    await tester.enterText(field(l10n.noticesFieldTitle), 'Title');
    await tester.enterText(field(l10n.noticesFieldBody), 'Body');
    await tapVisible(tester, find.text(l10n.noticesPost));
    expect(find.text('Title is too long'), findsOneWidget);
    expect(find.byType(NoticeFormScreen), findsOneWidget, reason: 'stays');

    // Editing the field clears the server message.
    await tester.enterText(field(l10n.noticesFieldTitle), 'Shorter');
    await tester.pump();
    expect(find.text('Title is too long'), findsNothing);
  });

  testWidgets('edit (notice passed as extra): prefilled, sends only changes', (
    tester,
  ) async {
    await pumpNoticeApp(
      tester,
      repo: repo,
      admin: false,
      initialPush: AppRoutes.noticeEdit('mine'),
      extra: repo.notices.first,
    );
    expect(find.text(l10n.noticesEditTitle), findsOneWidget);
    expect(find.text('Old title'), findsOneWidget);
    expect(repo.calls.where((c) => c.startsWith('find')), isEmpty);

    await tester.enterText(field(l10n.noticesFieldTitle), 'New title');
    await tapVisible(tester, find.text(l10n.commonSave));

    expect(repo.lastPatch?.toJson(), {'title': 'New title'});
    expect(find.text(l10n.noticesUpdated), findsOneWidget);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('edit by deep link looks the notice up', (tester) async {
    await pumpNoticeApp(
      tester,
      repo: repo,
      initialPush: AppRoutes.noticeEdit('theirs'),
    );
    expect(repo.calls, contains('find theirs'));
    expect(find.text('Admin notice'), findsOneWidget);
  });

  testWidgets('link to a deleted notice: "no longer available" + back', (
    tester,
  ) async {
    await pumpNoticeApp(
      tester,
      repo: repo,
      initialPush: AppRoutes.noticeEdit('gone'),
    );
    expect(find.text(l10n.noticesNotFoundTitle), findsOneWidget);
    expect(find.text(l10n.commonRetry), findsNothing, reason: 'no retry');
    await tester.tap(find.text(l10n.commonBack));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('a failed lookup (offline) still offers retry', (tester) async {
    repo.notices.clear();
    final offline = _OfflineFindRepository(repo);
    await pumpNoticeApp(
      tester,
      repo: offline,
      initialPush: AppRoutes.noticeEdit('mine'),
    );
    expect(find.text(l10n.commonRetry), findsOneWidget);
  });

  testWidgets('edit: notice deleted meanwhile → message and back', (
    tester,
  ) async {
    await pumpNoticeApp(
      tester,
      repo: repo,
      admin: false,
      initialPush: AppRoutes.noticeEdit('mine'),
      extra: repo.notices.first,
    );
    await tester.enterText(field(l10n.noticesFieldTitle), 'New title');
    repo.notices.removeWhere((n) => n.id == 'mine');
    await tapVisible(tester, find.text(l10n.commonSave));

    expect(find.text(l10n.noticesGone), findsOneWidget);
    expect(find.byType(NoticeFormScreen), findsNothing);
    expect(find.text(l10n.commonDiscardChangesTitle), findsNothing);
  });

  testWidgets('saving while the photo uploads is refused, then works', (
    tester,
  ) async {
    final uploads = GatedCloudinaryService();
    await pumpNoticeApp(
      tester,
      repo: repo,
      initialPush: AppRoutes.noticeNew,
      overrides: [cloudinaryServiceProvider.overrideWithValue(uploads)],
    );
    await tester.enterText(field(l10n.noticesFieldTitle), 'Trip');
    await tester.enterText(field(l10n.noticesFieldBody), 'Photos inside');

    final upload = startUpload(tester);
    await tester.pump();
    expect(uploads.folders, [UploadFolder.notices]);

    await tapVisible(tester, find.text(l10n.noticesPost));
    expect(find.text(l10n.noticesPhotoUploading), findsOneWidget);
    expect(repo.calls.where((c) => c == 'create'), isEmpty);

    uploads.gate.complete();
    await upload;
    await dismissSnackBar(tester);
    await tapVisible(tester, find.text(l10n.noticesPost));
    expect(repo.calls.where((c) => c == 'create'), hasLength(1));
  });

  testWidgets('leaving while a photo uploads asks first', (tester) async {
    final uploads = GatedCloudinaryService();
    await pumpNoticeApp(
      tester,
      repo: repo,
      initialPush: AppRoutes.noticeNew,
      overrides: [cloudinaryServiceProvider.overrideWithValue(uploads)],
    );
    unawaited(startUpload(tester));
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text(l10n.commonDiscardChangesTitle), findsOneWidget);
    uploads.gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('rapid double tap on Post creates one notice', (tester) async {
    repo.gate = Completer<void>();
    await pumpNoticeApp(tester, repo: repo, initialPush: AppRoutes.noticeNew);
    await tester.enterText(field(l10n.noticesFieldTitle), 'Once');
    await tester.enterText(field(l10n.noticesFieldBody), 'Only once');
    // A focused field keeps scrolling its caret back into view.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    final post = find.text(l10n.noticesPost);
    await tester.ensureVisible(post);
    await tester.pumpAndSettle();
    await tester.tap(post);
    await tester.pump();
    await tester.tap(find.byType(AppButton), warnIfMissed: false);
    await tester.pump();
    repo.gate!.complete();
    await tester.pumpAndSettle();
    expect(repo.calls.where((c) => c == 'create'), hasLength(1));
  });

  testWidgets('whitespace-only text is rejected; emoji over the limit too', (
    tester,
  ) async {
    await pumpNoticeApp(tester, repo: repo, initialPush: AppRoutes.noticeNew);
    await tester.enterText(field(l10n.noticesFieldTitle), '   ');
    await tester.enterText(field(l10n.noticesFieldBody), '\n\n  ');
    await tapVisible(tester, find.text(l10n.noticesPost));
    expect(find.text(l10n.validationRequired), findsNWidgets(2));

    // 1500 emoji fit the 2000-character counter but are 3000 UTF-16 code
    // units — more than the server accepts.
    await tester.enterText(field(l10n.noticesFieldTitle), 'Emoji');
    await tester.enterText(field(l10n.noticesFieldBody), '🙂' * 1500);
    await tapVisible(tester, find.text(l10n.noticesPost));
    expect(find.text(l10n.validationMaxLength(2000)), findsOneWidget);
    expect(repo.calls.where((c) => c == 'create'), isEmpty);
  });

  testWidgets('member without pin rights never sends pinned on edit', (
    tester,
  ) async {
    await pumpNoticeApp(
      tester,
      repo: repo,
      admin: false,
      initialPush: AppRoutes.noticeEdit('mine'),
      extra: repo.notices.first,
    );
    expect(find.byType(Switch), findsNothing);
    await tester.enterText(field(l10n.noticesFieldBody), 'Changed');
    await tapVisible(tester, find.text(l10n.commonSave));
    expect(repo.lastPatch?.toJson(), {'body': 'Changed'});
  });

  testWidgets('member cannot edit someone else\'s notice', (tester) async {
    await pumpNoticeApp(
      tester,
      repo: repo,
      admin: false,
      initialPush: AppRoutes.noticeEdit('theirs'),
    );
    expect(find.text(l10n.noticesEditNotAllowed), findsOneWidget);
    expect(field(l10n.noticesFieldTitle), findsNothing);
  });

  testWidgets('leaving with unsaved changes asks first', (tester) async {
    await pumpNoticeApp(tester, repo: repo, initialPush: AppRoutes.noticeNew);
    await tester.enterText(field(l10n.noticesFieldTitle), 'Draft');
    await tester.pump();

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text(l10n.commonDiscardChangesTitle), findsOneWidget);

    await tester.tap(find.text(l10n.commonCancel));
    await tester.pumpAndSettle();
    expect(find.byType(NoticeFormScreen), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.commonDiscard));
    await tester.pumpAndSettle();
    expect(find.byType(NoticeFormScreen), findsNothing);
    expect(repo.calls.where((c) => c == 'create'), isEmpty);
  });

  testWidgets('leaving an untouched form does not ask', (tester) async {
    await pumpNoticeApp(tester, repo: repo, initialPush: AppRoutes.noticeNew);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(NoticeFormScreen), findsNothing);
  });

  testWidgets('sections: message card, big photo picker, pin row with badge', (
    tester,
  ) async {
    await pumpNoticeApp(tester, repo: repo, initialPush: AppRoutes.noticeNew);
    expect(
      find.widgetWithText(SectionHeader, l10n.noticesSectionMessage),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(SectionHeader, l10n.noticesFieldImage),
      findsOneWidget,
    );
    final picker = tester.widget<ImagePickerField>(
      find.byType(ImagePickerField),
    );
    expect(picker.size, NoticePhotoField.defaultSize);
    expect(picker.folder, UploadFolder.notices);
    final badge = tester.widget<IconBadge>(
      find.descendant(
        of: find.byType(SwitchListTile),
        matching: find.byType(IconBadge),
      ),
    );
    expect(badge.accent, AppAccents.notices);
  });

  testWidgets('a failed check scrolls the first invalid field into view', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 1920); // 360 × 640 dp
    addTearDown(tester.view.resetPhysicalSize);
    await pumpNoticeApp(tester, repo: repo, initialPush: AppRoutes.noticeNew);
    final post = find.text(l10n.noticesPost);
    await tester.ensureVisible(post);
    await tester.pumpAndSettle();
    final top = tester.getRect(find.byType(AppBar)).bottom;
    expect(
      tester.getRect(field(l10n.noticesFieldTitle)).bottom,
      lessThan(top),
      reason: 'the title field is scrolled away while Post is visible',
    );

    await tester.tap(post);
    await tester.pumpAndSettle();
    expect(find.text(l10n.validationRequired), findsNWidgets(2));
    final title = tester.getRect(field(l10n.noticesFieldTitle));
    // Revealed right below the app bar.
    expect(title.top, inInclusiveRange(top - 1, top + AppSpacing.xxxl));
    expect(repo.calls.where((c) => c == 'create'), isEmpty);
  });

  testWidgets('dark theme and 1.4× text: the form lays out', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpNoticeApp(
      tester,
      repo: repo,
      initialPush: AppRoutes.noticeNew,
      theme: AppTheme.dark(),
    );
    expect(tester.takeException(), isNull);
    expect(field(l10n.noticesFieldTitle), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
  });
}

/// Answers every lookup with a network error.
class _OfflineFindRepository extends FakeNoticesRepository {
  _OfflineFindRepository(FakeNoticesRepository base) : super(base.notices);

  @override
  Future<Notice> findById(String id) async {
    calls.add('find $id');
    throw const ApiException.network();
  }
}
