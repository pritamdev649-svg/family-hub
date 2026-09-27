import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/network/api_client.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/notices/presentation/screens/notice_form_screen.dart';
import 'package:family_hub/features/notices/presentation/screens/notices_screen.dart';
import 'package:family_hub/features/notices/presentation/widgets/notice_card.dart';
import 'package:family_hub/features/notices/presentation/widgets/notices_header.dart';
import 'package:family_hub/l10n/app_localizations.dart';

import 'notices_test_utils.dart';

final l10n = lookupAppLocalizations(const Locale('en'));

Finder cardOf(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(NoticeCard));

Finder menuOf(String title) => find.descendant(
  of: cardOf(title),
  matching: find.byTooltip(l10n.noticesActions),
);

Future<void> openMenu(WidgetTester tester, String title) async {
  await tester.tap(menuOf(title));
  await tester.pumpAndSettle();
}

void main() {
  final longBody = List.filled(
    60,
    'Remember to bring the documents.',
  ).join(' ');

  late FakeNoticesRepository repo;

  setUp(() {
    repo = FakeNoticesRepository([
      testNotice('a', title: 'Electricity bill paid', authorName: 'Priya'),
      testNotice(
        'p',
        title: 'Family meeting Sunday 7pm',
        pinned: true,
        authorId: adminMemberId,
        authorName: 'Amit',
        age: const Duration(days: 2),
      ),
      testNotice(
        'l',
        title: 'Long notice',
        body: longBody,
        age: const Duration(days: 1),
      ),
    ]);
  });

  testWidgets('pinned first with badge, author, relative time and FAB', (
    tester,
  ) async {
    await pumpNoticeApp(tester, repo: repo);

    expect(find.byType(NoticesScreen), findsOneWidget);
    expect(find.text(l10n.noticesTitle), findsOneWidget);
    final cards = tester.widgetList<NoticeCard>(find.byType(NoticeCard));
    expect(cards.first.notice.title, 'Family meeting Sunday 7pm');
    expect(
      find.descendant(
        of: cardOf('Family meeting Sunday 7pm'),
        matching: find.text(l10n.noticesPinned),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: cardOf('Electricity bill paid'),
        matching: find.text(l10n.noticesPinned),
      ),
      findsNothing,
    );
    expect(find.text('Amit'), findsOneWidget);
    expect(find.text(l10n.commonHoursAgo(1)), findsOneWidget);
    expect(
      find.widgetWithText(FloatingActionButton, l10n.noticesNew),
      findsOneWidget,
    );
  });

  testWidgets('long text collapses with "Read more" and expands', (
    tester,
  ) async {
    await pumpNoticeApp(tester, repo: repo);
    await tester.scrollUntilVisible(find.text(l10n.noticesReadMore), 200);
    await tester.ensureVisible(find.text(l10n.noticesReadMore));
    await tester.pumpAndSettle();
    expect(find.text(l10n.noticesReadMore), findsOneWidget);
    await tester.tap(find.text(l10n.noticesReadMore));
    await tester.pumpAndSettle();
    expect(find.text(l10n.noticesShowLess), findsOneWidget);
    expect(find.text(l10n.noticesReadMore), findsNothing);
  });

  testWidgets('empty board shows the empty state with a call to action', (
    tester,
  ) async {
    await pumpNoticeApp(tester, repo: FakeNoticesRepository());
    expect(find.text(l10n.noticesEmptyTitle), findsOneWidget);
    expect(find.widgetWithText(AppButton, l10n.noticesNew), findsOneWidget);
  });

  testWidgets('error with retry, then data', (tester) async {
    // Not a transient error, so the provider's retry policy surfaces it.
    repo.listError = const ApiException(
      code: ApiErrorCode.forbidden,
      statusCode: 403,
    );
    await pumpNoticeApp(tester, repo: repo);
    expect(find.byType(ErrorView), findsOneWidget);
    expect(find.text(l10n.errorForbidden), findsOneWidget);
    await tester.tap(find.text(l10n.commonRetry));
    await tester.pumpAndSettle();
    expect(find.byType(ErrorView), findsNothing);
    expect(find.text('Family meeting Sunday 7pm'), findsOneWidget);
  });

  testWidgets('admin menu: edit, unpin, copy, delete', (tester) async {
    await pumpNoticeApp(tester, repo: repo);
    await openMenu(tester, 'Family meeting Sunday 7pm');
    expect(find.widgetWithText(ListTile, l10n.commonEdit), findsOneWidget);
    expect(find.widgetWithText(ListTile, l10n.noticesUnpin), findsOneWidget);
    expect(find.widgetWithText(ListTile, l10n.noticesCopyText), findsOneWidget);
    expect(find.widgetWithText(ListTile, l10n.commonDelete), findsOneWidget);
  });

  testWidgets('member sees only "Copy text" on someone else\'s notice', (
    tester,
  ) async {
    await pumpNoticeApp(tester, repo: repo, admin: false);
    await openMenu(tester, 'Family meeting Sunday 7pm');
    expect(find.widgetWithText(ListTile, l10n.noticesCopyText), findsOneWidget);
    expect(find.widgetWithText(ListTile, l10n.commonEdit), findsNothing);
    expect(find.widgetWithText(ListTile, l10n.noticesUnpin), findsNothing);
    expect(find.widgetWithText(ListTile, l10n.commonDelete), findsNothing);
  });

  testWidgets('member can edit and delete own notice (long-press)', (
    tester,
  ) async {
    await pumpNoticeApp(tester, repo: repo, admin: false);
    await tester.longPress(find.text('Electricity bill paid'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, l10n.commonEdit), findsOneWidget);
    expect(find.widgetWithText(ListTile, l10n.commonDelete), findsOneWidget);
    expect(find.widgetWithText(ListTile, l10n.noticesPin), findsNothing);
  });

  testWidgets('delete asks for confirmation, then removes the notice', (
    tester,
  ) async {
    await pumpNoticeApp(tester, repo: repo);
    await openMenu(tester, 'Electricity bill paid');
    await tester.tap(find.widgetWithText(ListTile, l10n.commonDelete));
    await tester.pumpAndSettle();
    expect(find.text(l10n.noticesDeleteTitle), findsOneWidget);

    // Cancel keeps it.
    await tester.tap(find.text(l10n.commonCancel));
    await tester.pumpAndSettle();
    expect(repo.calls.where((c) => c.startsWith('delete')), isEmpty);

    await openMenu(tester, 'Electricity bill paid');
    await tester.tap(find.widgetWithText(ListTile, l10n.commonDelete));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, l10n.commonDelete));
    await tester.pumpAndSettle();

    expect(repo.calls, contains('delete a'));
    expect(find.text('Electricity bill paid'), findsNothing);
    expect(find.text(l10n.noticesDeleted), findsOneWidget);
  });

  testWidgets('admin pins a notice; it moves to the top', (tester) async {
    await pumpNoticeApp(tester, repo: repo);
    await openMenu(tester, 'Electricity bill paid');
    await tester.tap(find.widgetWithText(ListTile, l10n.noticesPin));
    await tester.pumpAndSettle();

    expect(repo.lastPatch?.toJson(), {'pinned': true});
    expect(find.text(l10n.noticesPinnedSuccess), findsOneWidget);
    expect(
      find.descendant(
        of: cardOf('Electricity bill paid'),
        matching: find.text(l10n.noticesPinned),
      ),
      findsOneWidget,
    );
    final first = tester.widgetList<NoticeCard>(find.byType(NoticeCard)).first;
    expect(first.notice.title, 'Electricity bill paid');
  });

  testWidgets('a failed pin shows a localized error', (tester) async {
    repo.mutationError = const ApiException(
      code: ApiErrorCode.forbidden,
      statusCode: 403,
    );
    await pumpNoticeApp(tester, repo: repo);
    await openMenu(tester, 'Electricity bill paid');
    await tester.tap(find.widgetWithText(ListTile, l10n.noticesPin));
    await tester.pumpAndSettle();
    expect(find.text(l10n.errorForbidden), findsOneWidget);
  });

  testWidgets('load more appends the next page', (tester) async {
    final many = FakeNoticesRepository([
      for (var i = 0; i < 25; i++)
        testNotice(
          'n$i',
          title: 'Notice $i',
          age: Duration(minutes: i + 1),
        ),
    ]);
    await pumpNoticeApp(tester, repo: many);
    expect(many.calls, ['list 1/20']);
    await tester.scrollUntilVisible(find.text('Notice 24'), 300);
    await tester.pumpAndSettle();
    expect(find.text('Notice 24'), findsOneWidget);
    expect(many.calls, ['list 1/20', 'list 2/20']);
    expect(find.text(l10n.commonLoadMore), findsNothing);
  });

  testWidgets('FAB opens the new-notice form', (tester) async {
    await pumpNoticeApp(tester, repo: repo);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text(l10n.noticesFieldTitle), findsOneWidget);
    expect(find.text(l10n.noticesPost), findsOneWidget);
  });

  testWidgets('a second FAB tap while the form opens does not stack forms', (
    tester,
  ) async {
    await pumpNoticeApp(tester, repo: repo);
    final fab = tester.widget<FloatingActionButton>(
      find.byType(FloatingActionButton),
    );
    fab.onPressed!();
    await tester.pump();
    // The form is animating in; a second tap reaches the FAB.
    fab.onPressed!();
    await tester.pumpAndSettle();
    expect(find.byType(NoticeFormScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(NoticesScreen), findsOneWidget);
  });

  testWidgets('coming back to the app refreshes the visible board', (
    tester,
  ) async {
    await pumpNoticeApp(tester, repo: repo);
    repo.notices.add(testNotice('b', title: 'Posted on another phone'));
    repo.calls.clear();
    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    expect(repo.calls, isEmpty, reason: 'nothing while in the background');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(repo.calls, ['list 1/20']);
    expect(find.text('Posted on another phone'), findsOneWidget);

    // A system dialog / the notification shade (inactive only) does not.
    repo.calls.clear();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(repo.calls, isEmpty);
  });

  testWidgets('pinning a notice deleted elsewhere removes it with a message', (
    tester,
  ) async {
    await pumpNoticeApp(tester, repo: repo);
    repo.notices.removeWhere((n) => n.id == 'a');
    await openMenu(tester, 'Electricity bill paid');
    await tester.tap(find.widgetWithText(ListTile, l10n.noticesPin));
    await tester.pumpAndSettle();
    expect(find.text(l10n.noticesGone), findsOneWidget);
    expect(find.text('Electricity bill paid'), findsNothing);
  });

  testWidgets('copy puts title and text on the clipboard', (tester) async {
    final copied = <String?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String?);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await pumpNoticeApp(tester, repo: repo, admin: false);
    await openMenu(tester, 'Electricity bill paid');
    await tester.tap(find.widgetWithText(ListTile, l10n.noticesCopyText));
    await tester.pumpAndSettle();
    expect(copied, ['Electricity bill paid\n\nBody text']);
    expect(find.text(l10n.commonCopied), findsOneWidget);
  });

  testWidgets('very long author names and titles stay inside the card', (
    tester,
  ) async {
    final long = FakeNoticesRepository([
      testNotice(
        'x',
        title: 'T' * 100,
        authorName: 'Venkatanarasimharajuvaripeta Subramanyam ' * 3,
        body: 'https://example.com/${'a' * 300}',
      ),
    ]);
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpNoticeApp(tester, repo: long);
    expect(tester.takeException(), isNull);
    expect(find.byType(NoticeCard), findsOneWidget);
  });

  testWidgets('RTL and 1.6× text render without layout errors', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpNoticeApp(tester, repo: repo, textDirection: TextDirection.rtl);
    expect(tester.takeException(), isNull);
    expect(find.text('Family meeting Sunday 7pm'), findsOneWidget);
  });

  group('redesign', () {
    testWidgets('amber header: family, title, stats and a back button', (
      tester,
    ) async {
      await pumpNoticeApp(tester, repo: repo);
      final header = find.byType(NoticesHeader);
      Finder inHeader(String text) =>
          find.descendant(of: header, matching: find.text(text));

      expect(find.byType(GradientHeaderScrollView), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      expect(inHeader('Sharma Family'), findsOneWidget);
      expect(inHeader(l10n.noticesTitle), findsOneWidget);
      expect(inHeader(l10n.noticesSubtitle), findsOneWidget);
      // Three notices on the board, one of them pinned.
      expect(inHeader('3'), findsOneWidget);
      expect(inHeader(l10n.noticesStatTotal), findsOneWidget);
      expect(inHeader('1'), findsOneWidget);
      expect(inHeader(l10n.noticesPinned), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(NoticesScreen), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets(
      'status bar stays transparent with white icons while scrolling',
      (tester) async {
        tester.view.padding = const FakeViewPadding(top: 72);
        addTearDown(tester.view.resetPadding);
        final many = FakeNoticesRepository([
          for (var i = 0; i < 12; i++)
            testNotice(
              'n$i',
              title: 'Notice $i',
              age: Duration(minutes: i + 1),
            ),
        ]);
        await pumpNoticeApp(tester, repo: many);
        expect(SystemChrome.latestStyle?.statusBarColor, Colors.transparent);
        expect(
          SystemChrome.latestStyle?.statusBarIconBrightness,
          Brightness.light,
        );

        // The header scrolls away; a strip of the header gradient takes its
        // place behind the status bar instead of the cards, so the icons stay
        // white on amber.
        await tester.drag(find.byType(Scrollable), const Offset(0, -900));
        await tester.pumpAndSettle();
        expect(
          find.byType(NoticesHeader),
          findsNothing,
          reason: 'header scrolled out of view',
        );
        expect(SystemChrome.latestStyle?.statusBarColor, Colors.transparent);
        expect(
          SystemChrome.latestStyle?.statusBarIconBrightness,
          Brightness.light,
        );
      },
    );

    testWidgets('pinned notices sit on the soft amber card', (tester) async {
      await pumpNoticeApp(tester, repo: repo);
      AppCard cardFor(String title) => tester.widget<AppCard>(
        find
            .descendant(of: cardOf(title), matching: find.byType(AppCard))
            .first,
      );
      expect(cardFor('Family meeting Sunday 7pm').accent, AppAccents.notices);
      expect(cardFor('Electricity bill paid').accent, isNull);
    });

    testWidgets('empty board: amber badge card with the call to action', (
      tester,
    ) async {
      await pumpNoticeApp(tester, repo: FakeNoticesRepository());
      final badge = tester.widget<IconBadge>(find.byType(IconBadge));
      expect(badge.accent, AppAccents.notices);
      expect(
        find.ancestor(
          of: find.text(l10n.noticesEmptyTitle),
          matching: find.byType(AppCard),
        ),
        findsOneWidget,
      );
      // Header stats reflect the empty board.
      expect(
        find.descendant(
          of: find.byType(NoticesHeader),
          matching: find.text('0'),
        ),
        findsNWidgets(2),
      );
    });

    testWidgets('a failed page is retried with "Load more", not by scrolling', (
      tester,
    ) async {
      final many = FakeNoticesRepository([
        for (var i = 0; i < 25; i++)
          testNotice(
            'n$i',
            title: 'Notice $i',
            age: Duration(minutes: i + 1),
          ),
      ]);
      await pumpNoticeApp(tester, repo: many);
      many.listError = const ApiException(
        code: ApiErrorCode.forbidden,
        statusCode: 403,
      );
      await tester.scrollUntilVisible(find.text(l10n.commonLoadMore), 300);
      await tester.pumpAndSettle();
      expect(many.calls, ['list 1/20', 'list 2/20']);
      expect(find.text(l10n.errorForbidden), findsOneWidget);

      await tester.drag(find.byType(Scrollable), const Offset(0, -100));
      await tester.pumpAndSettle();
      expect(many.calls, hasLength(2), reason: 'no automatic retry');

      tester
          .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
          .removeCurrentSnackBar();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(l10n.commonLoadMore));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.commonLoadMore));
      await tester.pumpAndSettle();
      expect(many.calls, ['list 1/20', 'list 2/20', 'list 2/20']);
      expect(find.text('Notice 24'), findsOneWidget);
      expect(find.text(l10n.commonLoadMore), findsNothing);
    });

    testWidgets('dark theme renders header, cards and FAB without errors', (
      tester,
    ) async {
      await pumpNoticeApp(tester, repo: repo, theme: AppTheme.dark());
      expect(tester.takeException(), isNull);
      expect(
        Theme.of(tester.element(find.byType(NoticeCard).first)).brightness,
        Brightness.dark,
      );
      expect(find.text('Family meeting Sunday 7pm'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });
  });
}
