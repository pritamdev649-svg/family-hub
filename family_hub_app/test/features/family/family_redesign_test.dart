// The "modern & colourful" family screens (docs/12-DESIGN_LANGUAGE.md):
// gradient headers behind a transparent status bar, glass statistics,
// colourful action tiles, the membership card, and the dark theme.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/family/presentation/screens/member_detail_screen.dart';
import 'package:family_hub/features/family/presentation/screens/members_screen.dart';
import 'package:family_hub/features/family/presentation/widgets/family_glass.dart';
import 'package:family_hub/features/family/presentation/widgets/invite_code_card.dart';
import 'package:family_hub/l10n/app_localizations.dart';

import 'family_test_utils.dart';

void main() {
  late FakeFamilyRepository repo;
  late AppLocalizations l10n;

  setUp(() async {
    repo = FakeFamilyRepository(members: [amit, kamla, aarav, anaya]);
    l10n = await englishL10n();
  });

  /// System UI styles requested inside the screen of type [screen].
  List<SystemUiOverlayStyle> overlayStyles(WidgetTester tester, Type screen) =>
      tester
          .widgetList<AnnotatedRegion<SystemUiOverlayStyle>>(
            find.descendant(
              of: find.byType(screen),
              matching: find.byWidgetPredicate(
                (w) => w is AnnotatedRegion<SystemUiOverlayStyle>,
              ),
            ),
          )
          .map((r) => r.value)
          .toList();

  group('gradient header behind a transparent status bar', () {
    testWidgets('member list: no app bar, white icons on the header', (
      tester,
    ) async {
      await pumpFamilyApp(
        tester,
        location: AppRoutes.members,
        repo: repo,
        session: FakeSession(sessionFor(amit)),
      );
      expect(
        find.descendant(
          of: find.byType(MembersScreen),
          matching: find.byType(AppBar),
        ),
        findsNothing,
      );
      expect(find.byType(GradientHeaderScrollView), findsOneWidget);
      final style = overlayStyles(tester, MembersScreen).single;
      expect(style.statusBarColor, Colors.transparent);
      expect(style.statusBarIconBrightness, Brightness.light);
      // Back lives in the header now (tooltip "Back", like the app bar's).
      expect(find.byTooltip('Back'), findsOneWidget);
      expect(find.byTooltip(l10n.familySettingsTooltip), findsOneWidget);
    });

    testWidgets('member detail: header with the member, transparent bar', (
      tester,
    ) async {
      await pumpFamilyApp(
        tester,
        location: AppRoutes.memberDetail(kamla.id),
        repo: repo,
        session: FakeSession(sessionFor(amit)),
      );
      expect(
        find.descendant(
          of: find.byType(MemberDetailScreen),
          matching: find.byType(AppBar),
        ),
        findsNothing,
      );
      final style = overlayStyles(tester, MemberDetailScreen).single;
      expect(style.statusBarColor, Colors.transparent);
      expect(
        find.descendant(
          of: find.byType(GradientHeader),
          matching: find.text('Kamla'),
        ),
        findsOneWidget,
      );
      // Role and age as glass pills on the header.
      expect(
        find.widgetWithText(FamilyGlassPill, l10n.roleMember),
        findsOneWidget,
      );
    });

    testWidgets('back in the header pops like the app bar did', (tester) async {
      await pumpFamilyApp(
        tester,
        location: AppRoutes.memberDetail(kamla.id),
        repo: repo,
        session: FakeSession(sessionFor(amit)),
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(MemberDetailScreen), findsNothing);
      expect(find.text('route:${AppRoutes.home}'), findsOneWidget);
    });

    testWidgets('opened directly: no back button in the header', (
      tester,
    ) async {
      await pumpFamilyApp(
        tester,
        location: AppRoutes.members,
        repo: repo,
        session: FakeSession(sessionFor(amit)),
        asRoot: true,
      );
      expect(find.byTooltip('Back'), findsNothing);
      expect(find.byTooltip(l10n.familySettingsTooltip), findsOneWidget);
    });

    testWidgets('unknown member keeps a plain app bar with back', (
      tester,
    ) async {
      await pumpFamilyApp(
        tester,
        location: AppRoutes.memberDetail('missing'),
        repo: repo,
        session: FakeSession(sessionFor(amit)),
      );
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byType(GradientHeaderScrollView), findsNothing);
    });
  });

  testWidgets('member list header: glass statistics', (tester) async {
    await pumpFamilyApp(
      tester,
      location: AppRoutes.members,
      repo: repo,
      session: FakeSession(sessionFor(amit)),
    );
    // The first text of a stat is its number, the second its label.
    Iterable<Text> texts(String label) => tester.widgetList<Text>(
      find.descendant(
        of: find.widgetWithText(FamilyGlassStat, label),
        matching: find.byType(Text),
      ),
    );
    expect(texts(l10n.familyStatAdmins).first.data, '1'); // Amit
    expect(texts(l10n.familyStatAppUsers).first.data, '2'); // Amit, Kamla
    expect(texts(l10n.familyStatKids).first.data, '2'); // Aarav, Anaya
  });

  testWidgets('member detail: colourful action tiles by permission', (
    tester,
  ) async {
    await pumpFamilyApp(
      tester,
      location: AppRoutes.memberDetail(amit.id),
      repo: repo,
      session: FakeSession(sessionFor(amit)),
    );
    for (final label in [
      l10n.commonCall,
      l10n.familyEmailAction,
      l10n.familyEmergencyCard,
      l10n.familyAssignTask,
    ]) {
      expect(find.widgetWithText(ActionTile, label), findsOneWidget);
    }
  });

  testWidgets('members: the membership card asks for an admin', (tester) async {
    repo.family = testFamily(inviteCode: null);
    await pumpFamilyApp(
      tester,
      location: AppRoutes.familySettings,
      repo: repo,
      session: FakeSession(sessionFor(kamla)),
    );
    final card = find.byType(InviteCodeCard);
    expect(
      find.descendant(of: card, matching: find.text('Sharma Family')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: card,
        matching: find.text(l10n.familyInviteCodeAdminOnly),
      ),
      findsOneWidget,
    );
    expect(find.byType(InviteCodeCells), findsNothing);
  });

  testWidgets('admins: the membership card shows the saved family name', (
    tester,
  ) async {
    await pumpFamilyApp(
      tester,
      location: AppRoutes.familySettings,
      repo: repo,
      session: FakeSession(sessionFor(amit)),
    );
    final card = find.byType(InviteCodeCard);
    expect(
      find.descendant(of: card, matching: find.text('Sharma Family')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.byType(InviteCodeCells)),
      findsOneWidget,
    );
  });

  for (final location in [
    AppRoutes.members,
    AppRoutes.memberDetail(amit.id),
    AppRoutes.memberDetail(anaya.id),
    AppRoutes.memberEdit(anaya.id),
    AppRoutes.memberNew,
    AppRoutes.familySettings,
  ]) {
    testWidgets('$location: dark theme, RTL, 1.4× text, 360 dp, no overflow', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpFamilyApp(
        tester,
        location: location,
        repo: repo,
        session: FakeSession(sessionFor(amit)),
        tall: false,
        theme: AppTheme.dark(),
        wrap: (child) => MediaQuery.withClampedTextScaling(
          minScaleFactor: 1.4,
          maxScaleFactor: 1.4,
          child: Directionality(textDirection: TextDirection.rtl, child: child),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        Theme.of(tester.element(find.byType(Scaffold).last)).brightness,
        Brightness.dark,
      );
    });
  }
}
