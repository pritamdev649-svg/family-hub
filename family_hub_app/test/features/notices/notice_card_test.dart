import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/notices/domain/notice.dart';
import 'package:family_hub/features/notices/presentation/widgets/notice_body_text.dart';
import 'package:family_hub/features/notices/presentation/widgets/notice_card.dart';
import 'package:family_hub/features/notices/presentation/widgets/notice_image_viewer.dart';
import 'package:family_hub/l10n/app_localizations.dart';

import 'notices_test_utils.dart';

final l10n = lookupAppLocalizations(const Locale('en'));

Future<void> pumpCard(
  WidgetTester tester,
  Widget card, {
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: noticeOverrides(FakeNoticesRepository()),
      child: MaterialApp(
        theme: theme ?? AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ListView(padding: AppSpacing.screen, children: [card]),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  const imagePath = '/nonexistent/notice-photo.jpg';

  testWidgets('photo opens full screen and closes again', (tester) async {
    await pumpCard(
      tester,
      NoticeCard(testNotice('a', title: 'Trip', imageUrl: imagePath)),
    );
    expect(find.byType(AppNetworkImage), findsOneWidget);
    expect(
      find.bySemanticsLabel(l10n.noticesImageLabel('Trip')),
      findsOneWidget,
    );

    // The ink overlay on top of the photo receives the tap.
    await tester.tap(find.bySemanticsLabel(l10n.noticesImageLabel('Trip')));
    await tester.pumpAndSettle();
    expect(find.byType(NoticeImageViewer), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);

    await tester.tap(find.byTooltip(l10n.commonClose));
    await tester.pumpAndSettle();
    expect(find.byType(NoticeImageViewer), findsNothing);
  });

  testWidgets('compact: clamped text, thumbnail, no "Read more", tappable', (
    tester,
  ) async {
    var taps = 0;
    await pumpCard(
      tester,
      NoticeCard(
        testNotice(
          'a',
          body: List.filled(80, 'Long text.').join(' '),
          imageUrl: imagePath,
        ),
        compact: true,
        showActions: false,
        onTap: () => taps++,
      ),
    );
    expect(find.byType(NoticeBodyText), findsNothing);
    expect(find.text(l10n.noticesReadMore), findsNothing);
    expect(find.byTooltip(l10n.noticesActions), findsNothing);
    final thumb = tester.getSize(find.byType(AppNetworkImage));
    expect(thumb.width, AppSizes.thumbnail);

    await tester.tap(find.text('Notice a'));
    expect(taps, 1);
  });

  testWidgets('unknown author shows "Former member"', (tester) async {
    await pumpCard(tester, NoticeCard(testNotice('a', authorName: '')));
    expect(find.text(l10n.noticesFormerMember), findsOneWidget);
  });

  testWidgets('short text has no "Read more"', (tester) async {
    await pumpCard(tester, NoticeCard(testNotice('a', body: 'Short.')));
    expect(find.text('Short.'), findsOneWidget);
    expect(find.text(l10n.noticesReadMore), findsNothing);
  });

  testWidgets('a createdAt in the future (clock skew) reads "Just now"', (
    tester,
  ) async {
    final now = DateTime.now().toUtc();
    await pumpCard(
      tester,
      NoticeCard(
        testNotice('f').copyWith(
          createdAt: now.add(const Duration(minutes: 7)),
          updatedAt: now.add(const Duration(minutes: 7)),
        ),
      ),
    );
    expect(find.text(l10n.commonJustNow), findsOneWidget);
    expect(find.text(l10n.commonToday), findsNothing);
  });

  testWidgets('a second tap while the photo viewer opens is ignored', (
    tester,
  ) async {
    await pumpCard(tester, NoticeCard(testNotice('i', imageUrl: imagePath)));
    final photo = find.bySemanticsLabel(l10n.noticesImageLabel('Notice i'));
    await tester.tap(photo);
    await tester.pump();
    // What a second tap on the photo does while the viewer animates in.
    final context = tester.element(find.byType(NoticeCard));
    unawaited(showNoticeImage(context, url: imagePath, title: 'Notice i'));
    await tester.pumpAndSettle();
    expect(find.byType(NoticeImageViewer), findsOneWidget);
  });

  test('Notice is the public model the card takes', () {
    final n = testNotice('x');
    expect(NoticeCard(n).notice, isA<Notice>());
  });

  testWidgets('pinned: solid amber pill with white text on the amber card', (
    tester,
  ) async {
    await pumpCard(tester, NoticeCard(testNotice('p', pinned: true)));
    final label = tester.widget<Text>(find.text(l10n.noticesPinned));
    expect(label.style?.color, Colors.white);
    final pill = tester.widget<DecoratedBox>(
      find
          .ancestor(
            of: find.text(l10n.noticesPinned),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    expect((pill.decoration as BoxDecoration).color, AppAccents.notices.dark);
    expect(
      tester.widget<AppCard>(find.byType(AppCard)).accent,
      AppAccents.notices,
    );
  });

  testWidgets('not pinned: plain card, no pill', (tester) async {
    await pumpCard(tester, NoticeCard(testNotice('a')));
    expect(find.text(l10n.noticesPinned), findsNothing);
    expect(tester.widget<AppCard>(find.byType(AppCard)).accent, isNull);
  });

  testWidgets('dark theme: card with photo and long text lays out', (
    tester,
  ) async {
    await pumpCard(
      tester,
      NoticeCard(
        testNotice(
          'd',
          pinned: true,
          imageUrl: imagePath,
          body: List.filled(60, 'Long text.').join(' '),
        ),
      ),
      theme: AppTheme.dark(),
    );
    expect(tester.takeException(), isNull);
    expect(find.text(l10n.noticesReadMore), findsOneWidget);
    expect(find.byType(AppNetworkImage), findsOneWidget);
  });
}
