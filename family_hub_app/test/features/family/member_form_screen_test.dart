import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/network/api_exception.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/features/family/presentation/screens/member_form_screen.dart';
import 'package:family_hub/features/family/presentation/screens/members_screen.dart';
import 'package:family_hub/features/family/presentation/widgets/guardian_consent_field.dart';
import 'package:family_hub/features/family/presentation/widgets/member_gone_view.dart';
import 'package:family_hub/l10n/app_localizations.dart';
import 'package:family_hub/shared/models/member.dart';

import 'family_test_utils.dart';

void main() {
  late FakeFamilyRepository repo;
  late AppLocalizations l10n;

  setUp(() async {
    repo = FakeFamilyRepository(members: [amit, kamla, aarav, anaya]);
    l10n = await englishL10n();
  });

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  testWidgets('guardian consent is mandatory for a minor (country law shown)', (
    tester,
  ) async {
    await pumpFamilyApp(
      tester,
      location: AppRoutes.memberEdit(anaya.id),
      repo: repo,
      session: FakeSession(sessionFor(amit)),
    );
    expect(find.text(l10n.familyEditMemberTitle), findsOneWidget);
    expect(find.byType(GuardianConsentField), findsOneWidget);
    expect(
      find.textContaining('Digital Personal Data Protection Act, 2023'),
      findsOneWidget,
    );

    await tapVisible(tester, find.text(l10n.commonSave));
    expect(find.text(l10n.familyGuardianConsentRequired), findsOneWidget);
    expect(repo.calls.where((c) => c.startsWith('updateMember')), isEmpty);

    await tapVisible(tester, find.byType(CheckboxListTile));
    await tapVisible(tester, find.text(l10n.commonSave));

    expect(repo.calls, contains('updateMember ${anaya.id}'));
    expect(repo.lastBody('updateMember'), {'guardianConsent': true});
    expect(find.byType(MemberFormScreen), findsNothing); // popped
    expect(find.text(l10n.commonSaved), findsOneWidget);
  });

  testWidgets('no consent section for adults', (tester) async {
    await pumpFamilyApp(
      tester,
      location: AppRoutes.memberEdit(kamla.id),
      repo: repo,
      session: FakeSession(sessionFor(amit)),
    );
    expect(find.byType(GuardianConsentField), findsNothing);
    // Kamla has an account: her email is read-only.
    expect(find.text(l10n.familyEmailLinkedHint), findsOneWidget);
    expect(find.text(l10n.familyInfoRole), findsOneWidget);
  });

  testWidgets('a member editing themselves only sees the allowed fields', (
    tester,
  ) async {
    final session = FakeSession(sessionFor(kamla));
    await pumpFamilyApp(
      tester,
      location: AppRoutes.memberEdit(kamla.id),
      repo: repo,
      session: session,
    );
    expect(find.text(l10n.familyEditMyDetailsTitle), findsOneWidget);
    expect(field(l10n.familyNameLabel), findsOneWidget);
    expect(field(l10n.familyPhoneLabel), findsOneWidget);
    expect(field(l10n.familyEmailLabel), findsNothing);
    expect(field(l10n.familyInfoDesignation), findsNothing);
    expect(find.text(l10n.familyInfoRole), findsNothing);

    await tester.enterText(field(l10n.familyNameLabel), 'Kamla Devi');
    await tapVisible(tester, find.text(l10n.commonSave));

    expect(repo.lastBody('updateMember'), {'name': 'Kamla Devi'});
    expect(session.applied.single.member?.name, 'Kamla Devi');
    expect(find.byType(MemberFormScreen), findsNothing);
  });

  testWidgets("members can't edit others or add members", (tester) async {
    await pumpFamilyApp(
      tester,
      location: AppRoutes.memberEdit(amit.id),
      repo: repo,
      session: FakeSession(sessionFor(kamla)),
    );
    expect(find.text(l10n.familyCannotEditTitle), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
  });

  testWidgets('admin adds a member: suggestion chip, invite snackbar', (
    tester,
  ) async {
    await pumpFamilyApp(
      tester,
      location: AppRoutes.memberNew,
      repo: repo,
      session: FakeSession(sessionFor(amit)),
    );
    expect(find.text(l10n.familyEmailInviteHint), findsOneWidget);

    // Validation first: the name is required.
    await tapVisible(
      tester,
      find.widgetWithText(FilledButton, l10n.familyAddMember),
    );
    expect(find.text(l10n.validationRequired), findsOneWidget);
    expect(repo.calls, isNot(contains('addMember')));

    await tester.enterText(field(l10n.familyNameLabel), 'Dadi');
    await tester.enterText(field(l10n.familyEmailLabel), ' Dadi@Example.com ');
    await tapVisible(tester, find.text(l10n.familyDesignationFamilyAdvisor));
    expect(
      tester
          .widget<TextFormField>(field(l10n.familyInfoDesignation))
          .controller
          ?.text,
      l10n.familyDesignationFamilyAdvisor,
    );

    await tapVisible(
      tester,
      find.widgetWithText(FilledButton, l10n.familyAddMember),
    );

    final body = repo.lastBody('addMember')! as Map<String, dynamic>;
    expect(body['name'], 'Dadi');
    expect(body['email'], 'dadi@example.com');
    expect(body['designation'], l10n.familyDesignationFamilyAdvisor);
    expect(body['role'], 'member');
    expect(body['guardianConsent'], isFalse);
    expect(find.byType(MemberFormScreen), findsNothing);
    expect(
      find.text(l10n.familyMemberAddedInvited('Dadi', 'dadi@example.com')),
      findsOneWidget,
    );
  });

  testWidgets('leaving with unsaved changes asks first', (tester) async {
    await pumpFamilyApp(
      tester,
      location: AppRoutes.memberNew,
      repo: repo,
      session: FakeSession(sessionFor(amit)),
    );
    await tester.enterText(field(l10n.familyNameLabel), 'Someone');
    await tester.pumpAndSettle();

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text(l10n.commonDiscardChangesTitle), findsOneWidget);
    await tester.tap(find.text(l10n.commonCancel));
    await tester.pumpAndSettle();
    expect(find.byType(MemberFormScreen), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.commonDiscard));
    await tester.pumpAndSettle();
    expect(find.byType(MemberFormScreen), findsNothing);
    expect(repo.calls, isNot(contains('addMember')));
  });

  group('edge cases', () {
    Finder addButton() =>
        find.widgetWithText(FilledButton, l10n.familyAddMember);

    int addCalls() => repo.calls.where((c) => c == 'addMember').length;

    testWidgets('same name as an existing member asks first', (tester) async {
      await pumpFamilyApp(
        tester,
        location: AppRoutes.memberNew,
        repo: repo,
        session: FakeSession(sessionFor(amit)),
      );
      await tester.enterText(field(l10n.familyNameLabel), ' aarav ');
      await tapVisible(tester, addButton());
      expect(find.text(l10n.familyDuplicateNameTitle('Aarav')), findsOneWidget);
      await tester.tap(find.text(l10n.commonCancel));
      await tester.pumpAndSettle();
      expect(addCalls(), 0);
      expect(find.byType(MemberFormScreen), findsOneWidget);

      await tapVisible(tester, addButton());
      await tester.tap(find.text(l10n.familyDuplicateNameConfirm));
      await tester.pumpAndSettle();
      expect(addCalls(), 1);
      expect(find.byType(MemberFormScreen), findsNothing);
    });

    testWidgets('server asks for guardian consent → the checkbox appears and '
        'its value is sent', (tester) async {
      repo.addErrors.add(apiError(ApiErrorCode.guardianConsentRequired, 422));
      await pumpFamilyApp(
        tester,
        location: AppRoutes.memberNew,
        repo: repo,
        session: FakeSession(sessionFor(amit)),
      );
      // No date of birth: the app's rule needs no consent.
      await tester.enterText(field(l10n.familyNameLabel), 'Rohan');
      expect(find.byType(GuardianConsentField), findsNothing);
      await tapVisible(tester, addButton());
      expect(find.text(l10n.errorGuardianConsentRequired), findsOneWidget);
      expect(find.byType(GuardianConsentField), findsOneWidget);
      expect(find.text(l10n.familyGuardianConsentRequired), findsOneWidget);

      // The error snack bar floats over the bottom of the (tall) form until
      // it times out (errors stay longer); wait for it like a user would.
      await tester.pump(AppDurations.snackbar * 2);
      await tester.pumpAndSettle();
      expect(find.text(l10n.errorGuardianConsentRequired), findsNothing);

      // Not ticked: blocked locally, no second request.
      await tapVisible(tester, addButton());
      expect(addCalls(), 1);

      await tapVisible(tester, find.byType(CheckboxListTile));
      await tapVisible(tester, addButton());
      expect(addCalls(), 2);
      expect((repo.lastBody('addMember')! as Map)['guardianConsent'], isTrue);
      expect(find.byType(MemberFormScreen), findsNothing);
    });

    testWidgets('MEMBER_EMAIL_EXISTS is shown at the email field until it '
        'changes', (tester) async {
      repo.addErrors.add(apiError(ApiErrorCode.memberEmailExists));
      await pumpFamilyApp(
        tester,
        location: AppRoutes.memberNew,
        repo: repo,
        session: FakeSession(sessionFor(amit)),
      );
      await tester.enterText(field(l10n.familyNameLabel), 'Dadi');
      await tester.enterText(field(l10n.familyEmailLabel), 'priya@example.com');
      await tapVisible(tester, addButton());
      final emailError = find.descendant(
        of: field(l10n.familyEmailLabel),
        matching: find.text(l10n.errorMemberEmailExists),
      );
      expect(emailError, findsOneWidget);
      expect(find.byType(MemberFormScreen), findsOneWidget);

      await tester.enterText(field(l10n.familyEmailLabel), 'dadi@example.com');
      await tester.pumpAndSettle();
      expect(emailError, findsNothing);
      await tapVisible(tester, addButton());
      expect(addCalls(), 2);
      expect(find.byType(MemberFormScreen), findsNothing);
    });

    testWidgets('VALIDATION_ERROR details are shown at their fields', (
      tester,
    ) async {
      repo.addErrors.add(
        const ApiException(
          code: ApiErrorCode.validation,
          statusCode: 422,
          details: {'phone': 'Invalid phone number', 'unknownField': 'x'},
        ),
      );
      await pumpFamilyApp(
        tester,
        location: AppRoutes.memberNew,
        repo: repo,
        session: FakeSession(sessionFor(amit)),
      );
      await tester.enterText(field(l10n.familyNameLabel), 'Dadi');
      await tester.enterText(field(l10n.familyPhoneLabel), '+91 98765 43210');
      await tapVisible(tester, addButton());
      expect(
        find.descendant(
          of: field(l10n.familyPhoneLabel),
          matching: find.text('Invalid phone number'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('offline: the form stays with its values and can be retried', (
      tester,
    ) async {
      repo.addErrors.add(const ApiException.network());
      await pumpFamilyApp(
        tester,
        location: AppRoutes.memberNew,
        repo: repo,
        session: FakeSession(sessionFor(amit)),
      );
      await tester.enterText(field(l10n.familyNameLabel), 'Dadi');
      await tapVisible(tester, addButton());
      expect(find.text(l10n.errorNetwork), findsOneWidget);
      expect(find.byType(MemberFormScreen), findsOneWidget);
      expect(find.text('Dadi'), findsOneWidget);
      await tapVisible(tester, addButton());
      expect(addCalls(), 2);
      expect(find.byType(MemberFormScreen), findsNothing);
    });

    testWidgets('demoted while the add form is open → "admins only"', (
      tester,
    ) async {
      final session = FakeSession(sessionFor(amit));
      await pumpFamilyApp(
        tester,
        location: AppRoutes.memberNew,
        repo: repo,
        session: session,
      );
      await session.applyMe(null, amit.copyWith(role: MemberRole.member));
      await tester.pumpAndSettle();
      expect(find.text(l10n.commonAdminOnly), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
    });

    testWidgets('editing a member who was removed meanwhile → gone view', (
      tester,
    ) async {
      repo.updateError = apiError(ApiErrorCode.notFound, 404);
      await pumpFamilyApp(
        tester,
        location: AppRoutes.memberEdit(kamla.id),
        repo: repo,
        session: FakeSession(sessionFor(amit)),
      );
      await tester.enterText(field(l10n.familyNameLabel), 'Kamla Devi');
      repo.members = [amit, aarav, anaya];
      await tapVisible(tester, find.text(l10n.commonSave));
      expect(find.byType(MemberGoneView), findsOneWidget);
    });

    testWidgets('opened directly: saving continues to the member list', (
      tester,
    ) async {
      await pumpFamilyApp(
        tester,
        location: AppRoutes.memberEdit(kamla.id),
        repo: repo,
        session: FakeSession(sessionFor(amit)),
        asRoot: true,
      );
      await tester.enterText(field(l10n.familyNameLabel), 'Kamla Devi');
      await tapVisible(tester, find.text(l10n.commonSave));
      expect(tester.takeException(), isNull);
      expect(find.byType(MembersScreen), findsOneWidget);
      expect(find.text('Kamla Devi'), findsOneWidget);
    });
  });
}
