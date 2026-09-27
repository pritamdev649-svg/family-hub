import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/network/api_exception.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/features/family/presentation/screens/member_detail_screen.dart';
import 'package:family_hub/features/family/presentation/screens/member_form_screen.dart';
import 'package:family_hub/features/family/presentation/screens/members_screen.dart';
import 'package:family_hub/features/family/presentation/widgets/member_tile.dart';
import 'package:family_hub/shared/models/member.dart';

import 'family_test_utils.dart';

void main() {
  late FakeFamilyRepository repo;

  setUp(
    () => repo = FakeFamilyRepository(members: [amit, kamla, aarav, anaya]),
  );

  testWidgets('admin: members with designation, badges and the add button', (
    tester,
  ) async {
    final l10n = await englishL10n();
    await pumpFamilyApp(
      tester,
      location: AppRoutes.members,
      repo: repo,
      session: FakeSession(sessionFor(amit)),
    );

    expect(find.byType(MembersScreen), findsOneWidget);
    expect(find.text(l10n.familyMembersTitle), findsOneWidget);
    expect(find.text(l10n.familyMembersCount(4)), findsOneWidget);
    for (final name in ['Amit', 'Kamla', 'Aarav', 'Anaya']) {
      expect(find.text(name), findsOneWidget);
    }
    expect(find.text('Head of Family'), findsOneWidget);
    expect(find.text('Chief Study Officer'), findsOneWidget);
    // Anaya has no designation: no empty line, the role badge is shown.
    expect(find.text(l10n.familyYouBadge), findsOneWidget); // Amit
    expect(find.text(l10n.roleAdmin), findsOneWidget);
    expect(find.text(l10n.familyInvitedBadge), findsOneWidget); // Aarav
    expect(find.text(l10n.familyNoAccountBadge), findsOneWidget); // Anaya
    expect(
      find.text(
        l10n.familyAgeGroupWithAge(l10n.ageGroupChild, l10n.ageYears(9)),
      ),
      findsOneWidget,
    );

    // Admin FAB → add form.
    expect(find.byType(FloatingActionButton), findsOneWidget);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.byType(MemberFormScreen), findsOneWidget);
    expect(find.text(l10n.familyAddMember), findsWidgets);
  });

  testWidgets('member: no add button; tapping a member opens details', (
    tester,
  ) async {
    await pumpFamilyApp(
      tester,
      location: AppRoutes.members,
      repo: repo,
      session: FakeSession(sessionFor(kamla)),
    );
    expect(find.byType(FloatingActionButton), findsNothing);

    await tester.tap(find.text('Aarav'));
    await tester.pumpAndSettle();
    expect(find.byType(MemberDetailScreen), findsOneWidget);
    // Served from the members list, no extra request.
    expect(repo.calls.where((c) => c.startsWith('getMember ')), isEmpty);
  });

  testWidgets('error with retry, then data', (tester) async {
    final l10n = await englishL10n();
    repo.getMembersError = const ApiException(
      code: ApiErrorCode.network,
      message: 'offline',
    );
    await pumpFamilyApp(
      tester,
      location: AppRoutes.members,
      repo: repo,
      session: FakeSession(sessionFor(amit)),
    );
    expect(find.text(l10n.errorNetwork), findsOneWidget);
    expect(find.text('Kamla'), findsNothing);

    repo.getMembersError = null;
    await tester.tap(find.text(l10n.commonRetry));
    await tester.pumpAndSettle();
    expect(find.text('Kamla'), findsOneWidget);
  });

  group('edge cases', () {
    testWidgets('empty list → empty state with the add action for admins', (
      tester,
    ) async {
      final l10n = await englishL10n();
      repo.members = [];
      await pumpFamilyApp(
        tester,
        location: AppRoutes.members,
        repo: repo,
        session: FakeSession(sessionFor(amit)),
      );
      expect(find.text(l10n.familyMembersEmptyTitle), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, l10n.familyAddMember));
      await tester.pumpAndSettle();
      expect(find.byType(MemberFormScreen), findsOneWidget);
    });

    testWidgets('a quick second tap opens the add form only once', (
      tester,
    ) async {
      await pumpFamilyApp(
        tester,
        location: AppRoutes.members,
        repo: repo,
        session: FakeSession(sessionFor(amit)),
      );
      final add = tester
          .widget<FloatingActionButton>(find.byType(FloatingActionButton))
          .onPressed!;
      add();
      await tester.pump();
      add(); // the first push is still animating in
      await tester.pumpAndSettle();
      expect(
        find.byType(MemberFormScreen, skipOffstage: false),
        findsOneWidget,
      );

      // Same for a member row.
      await tester.pageBack();
      await tester.pumpAndSettle();
      final open = tester.widget<MemberTile>(find.byType(MemberTile).at(1));
      open.onTap!();
      await tester.pump();
      open.onTap!();
      await tester.pumpAndSettle();
      expect(
        find.byType(MemberDetailScreen, skipOffstage: false),
        findsOneWidget,
      );
    });

    testWidgets(
      'demoted on another phone: the fresh list hides admin actions',
      (tester) async {
        final session = FakeSession(sessionFor(amit));
        repo.members = [amit.copyWith(role: MemberRole.member), kamla, aarav];
        await pumpFamilyApp(
          tester,
          location: AppRoutes.members,
          repo: repo,
          session: session,
        );
        expect(session.applied.single.member?.role, MemberRole.member);
        expect(find.byType(FloatingActionButton), findsNothing);
      },
    );

    testWidgets('removed from the family (NO_FAMILY) resyncs the session', (
      tester,
    ) async {
      final l10n = await englishL10n();
      final session = FakeSession(sessionFor(amit));
      repo.getMembersError = apiError(ApiErrorCode.noFamily, 403);
      await pumpFamilyApp(
        tester,
        location: AppRoutes.members,
        repo: repo,
        session: session,
      );
      expect(find.text(l10n.errorNoFamily), findsOneWidget);
      expect(session.refreshes, 1);
    });

    testWidgets('very long names and designations wrap or ellipsize', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final longName = 'Venkataraghavan${'a' * 45}';
      repo.members = [
        amit,
        kamla.copyWith(
          name: longName,
          designation: () => 'Chief ${'Very ' * 15}Important Officer',
        ),
      ];
      await pumpFamilyApp(
        tester,
        location: AppRoutes.members,
        repo: repo,
        session: FakeSession(sessionFor(amit)),
        tall: false,
        wrap: (child) => MediaQuery.withClampedTextScaling(
          minScaleFactor: 1.4,
          maxScaleFactor: 1.4,
          child: Directionality(textDirection: TextDirection.rtl, child: child),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text(longName));
      await tester.pumpAndSettle();
      expect(find.byType(MemberDetailScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  for (final location in [
    AppRoutes.members,
    AppRoutes.memberDetail(anaya.id),
    AppRoutes.memberEdit(anaya.id),
    AppRoutes.memberNew,
    AppRoutes.familySettings,
  ]) {
    testWidgets('$location: RTL, 1.4× text, 360 dp wide, no overflow', (
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
        wrap: (child) => MediaQuery.withClampedTextScaling(
          minScaleFactor: 1.4,
          maxScaleFactor: 1.4,
          child: Directionality(textDirection: TextDirection.rtl, child: child),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
