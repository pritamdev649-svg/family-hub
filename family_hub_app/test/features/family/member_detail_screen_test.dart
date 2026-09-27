import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart' show LaunchMode;

import 'package:family_hub/core/network/api_exception.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/utils/url_actions.dart';
import 'package:family_hub/features/family/presentation/screens/member_detail_screen.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/family/presentation/screens/member_form_screen.dart';
import 'package:family_hub/features/family/presentation/screens/members_screen.dart';
import 'package:family_hub/features/family/presentation/widgets/member_gone_view.dart';
import 'package:family_hub/l10n/app_localizations.dart';
import 'package:family_hub/shared/models/member.dart';
import 'package:family_hub/shared/session/session_controller.dart';

import 'family_test_utils.dart';

void main() {
  late FakeFamilyRepository repo;
  late AppLocalizations l10n;
  final launched = <Uri>[];

  setUp(() async {
    repo = FakeFamilyRepository(members: [amit, kamla, aarav, anaya]);
    l10n = await englishL10n();
    launched.clear();
    UrlActions.launcherOverride = (Uri uri, LaunchMode mode) async {
      launched.add(uri);
      return true;
    };
  });

  tearDown(() => UrlActions.launcherOverride = null);

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('admin sees details, contact and every action', (tester) async {
    await pumpFamilyApp(
      tester,
      location: AppRoutes.memberDetail(kamla.id),
      repo: repo,
      session: FakeSession(sessionFor(amit)),
    );
    expect(find.byType(MemberDetailScreen), findsOneWidget);
    expect(find.text('Family Advisor'), findsOneWidget);
    expect(find.text(l10n.familyInfoDateOfBirth), findsOneWidget);
    expect(find.text(l10n.locationSharingNever), findsOneWidget);
    expect(find.text(l10n.familyAccountActive), findsOneWidget);
    expect(find.text(l10n.familyEmergencyCard), findsOneWidget);
    expect(find.text(l10n.familyAssignTask), findsOneWidget);
    expect(find.text(l10n.familyEditDetails), findsOneWidget);
    expect(find.text(l10n.familyRemoveMember), findsOneWidget);
    // Kamla has an email but no phone.
    expect(find.text(l10n.commonCall), findsNothing);
    // Contact actions are colourful action tiles.
    await tapVisible(
      tester,
      find.widgetWithText(ActionTile, l10n.familyEmailAction),
    );
    expect(launched.single.toString(), 'mailto:kamla@example.com');

    await tapVisible(tester, find.text(l10n.familyAssignTask));
    expect(
      find.text('route:${AppRoutes.taskNew(assigneeId: kamla.id)}'),
      findsOneWidget,
    );
  });

  testWidgets('guardian consent status is shown for minors', (tester) async {
    await pumpFamilyApp(
      tester,
      location: AppRoutes.memberDetail(anaya.id),
      repo: repo,
      session: FakeSession(sessionFor(amit)),
    );
    expect(find.text(l10n.familyInfoGuardianConsent), findsOneWidget);
    expect(find.text(l10n.familyGuardianConsentMissing), findsOneWidget);
    expect(find.text(l10n.familyAccountManaged), findsOneWidget);
  });

  testWidgets('remove: confirm, LAST_ADMIN error, then success', (
    tester,
  ) async {
    await pumpFamilyApp(
      tester,
      location: AppRoutes.memberDetail(kamla.id),
      repo: repo,
      session: FakeSession(sessionFor(amit)),
    );

    // Cancelling the dialog does nothing.
    await tapVisible(tester, find.text(l10n.familyRemoveMember));
    expect(find.text(l10n.familyRemoveConfirmTitle('Kamla')), findsOneWidget);
    await tester.tap(find.text(l10n.commonCancel));
    await tester.pumpAndSettle();
    expect(repo.calls.where((c) => c.startsWith('deleteMember')), isEmpty);

    repo.deleteError = const ApiException(
      code: ApiErrorCode.lastAdmin,
      message: 'last admin',
      statusCode: 409,
    );
    await tapVisible(tester, find.text(l10n.familyRemoveMember));
    await tester.tap(find.widgetWithText(FilledButton, l10n.commonRemove));
    await tester.pumpAndSettle();
    expect(find.text(l10n.errorLastAdmin), findsOneWidget);
    expect(find.byType(MemberDetailScreen), findsOneWidget);

    repo.deleteError = null;
    await tapVisible(tester, find.text(l10n.familyRemoveMember));
    await tester.tap(find.widgetWithText(FilledButton, l10n.commonRemove));
    await tester.pumpAndSettle();
    expect(
      repo.calls.where((c) => c == 'deleteMember ${kamla.id}'),
      hasLength(2),
    );
    expect(find.byType(MemberDetailScreen), findsNothing);
    expect(find.text(l10n.familyMemberRemoved('Kamla')), findsOneWidget);
  });

  testWidgets('own profile: edit yes, remove no, location sharing link', (
    tester,
  ) async {
    await pumpFamilyApp(
      tester,
      location: AppRoutes.memberDetail(amit.id),
      repo: repo,
      session: FakeSession(sessionFor(amit)),
    );
    expect(find.text(l10n.familyYouBadge), findsOneWidget);
    expect(find.text(l10n.familyRemoveMember), findsNothing);
    await tester.tap(find.text(l10n.commonCall));
    await tester.pumpAndSettle();
    expect(launched.single.toString(), 'tel:+919876543210');

    await tapVisible(tester, find.text(l10n.familyChangeAction));
    expect(find.text('route:${AppRoutes.settingsLocation}'), findsOneWidget);
  });

  testWidgets('members see others read-only (emergency card only)', (
    tester,
  ) async {
    await pumpFamilyApp(
      tester,
      location: AppRoutes.memberDetail(aarav.id),
      repo: repo,
      session: FakeSession(sessionFor(kamla)),
    );
    expect(find.text(l10n.familyEditDetails), findsNothing);
    expect(find.text(l10n.familyAssignTask), findsNothing);
    expect(find.text(l10n.familyRemoveMember), findsNothing);
    await tapVisible(tester, find.text(l10n.familyEmergencyCard));
    expect(
      find.text('route:${AppRoutes.emergencyCard(aarav.id)}'),
      findsOneWidget,
    );
  });

  testWidgets('edit button opens the form', (tester) async {
    await pumpFamilyApp(
      tester,
      location: AppRoutes.memberDetail(kamla.id),
      repo: repo,
      session: FakeSession(sessionFor(kamla)),
    );
    await tapVisible(tester, find.text(l10n.familyEditDetails));
    expect(find.byType(MemberFormScreen), findsOneWidget);
  });

  group('edge cases', () {
    testWidgets('unknown member (old notification) → "no longer in the '
        'family", Back returns', (tester) async {
      await pumpFamilyApp(
        tester,
        location: AppRoutes.memberDetail('missing'),
        repo: repo,
        session: FakeSession(sessionFor(amit)),
      );
      expect(find.byType(MemberGoneView), findsOneWidget);
      expect(find.text(l10n.familyMemberGoneTitle), findsOneWidget);
      expect(find.text(l10n.commonRetry), findsNothing);
      await tester.tap(find.text(l10n.commonBack));
      await tester.pumpAndSettle();
      expect(find.text('route:${AppRoutes.home}'), findsOneWidget);
    });

    testWidgets('malformed id (BAD_REQUEST) opened directly → gone view '
        'offering the member list', (tester) async {
      repo.getMemberError = apiError(ApiErrorCode.badRequest, 400);
      await pumpFamilyApp(
        tester,
        location: AppRoutes.memberDetail('bad id'),
        repo: repo,
        session: FakeSession(sessionFor(amit)),
        asRoot: true,
      );
      expect(find.byType(MemberGoneView), findsOneWidget);
      await tester.tap(find.text(l10n.familyViewMembers));
      await tester.pumpAndSettle();
      expect(find.byType(MembersScreen), findsOneWidget);
    });

    testWidgets('removed by another admin while open → gone view on refresh', (
      tester,
    ) async {
      await pumpFamilyApp(
        tester,
        location: AppRoutes.memberDetail(kamla.id),
        repo: repo,
        session: FakeSession(sessionFor(amit)),
      );
      expect(find.text(l10n.familyRemoveMember), findsOneWidget);
      repo.members = [amit, aarav, anaya];
      await markScopesChanged(tester, {DataScope.members});
      expect(find.byType(MemberGoneView), findsOneWidget);
      expect(find.text(l10n.familyRemoveMember), findsNothing);
    });

    testWidgets('remove: already removed elsewhere → info, screen closes', (
      tester,
    ) async {
      repo.deleteError = apiError(ApiErrorCode.notFound, 404);
      await pumpFamilyApp(
        tester,
        location: AppRoutes.memberDetail(kamla.id),
        repo: repo,
        session: FakeSession(sessionFor(amit)),
      );
      await tapVisible(tester, find.text(l10n.familyRemoveMember));
      await tester.tap(find.widgetWithText(FilledButton, l10n.commonRemove));
      await tester.pumpAndSettle();
      expect(find.byType(MemberDetailScreen), findsNothing);
      expect(
        find.text(l10n.familyMemberAlreadyRemoved('Kamla')),
        findsOneWidget,
      );
    });

    testWidgets('opened directly: after removing, the member list opens', (
      tester,
    ) async {
      await pumpFamilyApp(
        tester,
        location: AppRoutes.memberDetail(kamla.id),
        repo: repo,
        session: FakeSession(sessionFor(amit)),
        asRoot: true,
      );
      await tapVisible(tester, find.text(l10n.familyRemoveMember));
      await tester.tap(find.widgetWithText(FilledButton, l10n.commonRemove));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(MembersScreen), findsOneWidget);
      expect(find.text('Kamla'), findsNothing);
    });

    testWidgets('a quick second tap on Remove opens one dialog', (
      tester,
    ) async {
      await pumpFamilyApp(
        tester,
        location: AppRoutes.memberDetail(kamla.id),
        repo: repo,
        session: FakeSession(sessionFor(amit)),
      );
      final remove = tester
          .widget<AppButton>(
            find.widgetWithText(AppButton, l10n.familyRemoveMember),
          )
          .onPressed!;
      remove();
      await tester.pump();
      remove();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog, skipOffstage: false), findsOneWidget);
    });

    testWidgets('demoted while open → admin actions disappear', (tester) async {
      final session = FakeSession(sessionFor(amit));
      await pumpFamilyApp(
        tester,
        location: AppRoutes.memberDetail(kamla.id),
        repo: repo,
        session: session,
      );
      expect(find.text(l10n.familyRemoveMember), findsOneWidget);
      await session.applyMe(null, amit.copyWith(role: MemberRole.member));
      await tester.pumpAndSettle();
      expect(find.text(l10n.familyRemoveMember), findsNothing);
      expect(find.text(l10n.familyEditDetails), findsNothing);
      expect(find.text(l10n.familyEmergencyCard), findsOneWidget);
    });
  });
}
