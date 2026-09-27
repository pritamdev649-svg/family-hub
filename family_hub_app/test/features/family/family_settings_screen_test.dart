import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/network/api_exception.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/auth/presentation/widgets/country_picker.dart';
import 'package:family_hub/features/family/presentation/screens/family_settings_screen.dart';
import 'package:family_hub/features/family/presentation/screens/members_screen.dart';
import 'package:family_hub/features/family/presentation/widgets/invite_code_card.dart';
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

  List<String> codeCells(WidgetTester tester) => tester
      .widgetList<Text>(
        find.descendant(
          of: find.byType(InviteCodeCells),
          matching: find.byType(Text),
        ),
      )
      .map((t) => t.data ?? '')
      .toList();

  testWidgets('admin: invite code cells, copy and regenerate', (tester) async {
    Object? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') clipboard = call.arguments;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await pumpFamilyApp(
      tester,
      location: AppRoutes.familySettings,
      repo: repo,
      session: FakeSession(sessionFor(amit)),
    );
    expect(find.byType(FamilySettingsScreen), findsOneWidget);
    expect(codeCells(tester), 'K7Q2M9XD'.split(''));

    await tapVisible(tester, find.text(l10n.familyCopyInviteCode));
    expect((clipboard! as Map)['text'], 'K7Q2M9XD');
    expect(find.text(l10n.familyInviteCodeCopied), findsOneWidget);

    await tapVisible(tester, find.text(l10n.familyNewInviteCode));
    expect(find.text(l10n.familyNewInviteCodeConfirmTitle), findsOneWidget);
    await tester.tap(find.text(l10n.familyNewInviteCodeConfirm));
    await tester.pumpAndSettle();
    expect(repo.calls, contains('regenerateInviteCode'));
    expect(codeCells(tester), 'N3WCQDE7'.split(''));
    expect(find.text(l10n.familyNewInviteCodeCreated), findsOneWidget);
  });

  testWidgets('admin: save is enabled only with changes and sends the diff', (
    tester,
  ) async {
    await pumpFamilyApp(
      tester,
      location: AppRoutes.familySettings,
      repo: repo,
      session: FakeSession(sessionFor(amit)),
    );
    FilledButton save() => tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, l10n.commonSave),
    );
    expect(save().onPressed, isNull);

    await tester.enterText(
      find.widgetWithText(TextFormField, l10n.familyNameFieldLabel),
      'Sharma Parivar',
    );
    await tester.pumpAndSettle();
    expect(save().onPressed, isNotNull);

    await tapVisible(
      tester,
      find.widgetWithText(FilledButton, l10n.commonSave),
    );
    expect(repo.lastBody('updateFamily'), {'name': 'Sharma Parivar'});
    expect(find.text(l10n.familySettingsSaved), findsOneWidget);
    expect(save().onPressed, isNull); // saved → clean again
  });

  testWidgets('country picker switches currency and time zone defaults', (
    tester,
  ) async {
    await pumpFamilyApp(
      tester,
      location: AppRoutes.familySettings,
      repo: repo,
      session: FakeSession(sessionFor(amit)),
    );
    await tapVisible(tester, find.byType(CountryPickerField));
    await tester.enterText(
      find.widgetWithText(TextFormField, l10n.commonSearch),
      'germ',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Germany'));
    await tester.pumpAndSettle();

    await tapVisible(
      tester,
      find.widgetWithText(FilledButton, l10n.commonSave),
    );
    expect(repo.lastBody('updateFamily'), {
      'country': 'DE',
      'currency': 'EUR',
      'timezone': 'Europe/Berlin',
    });
  });

  testWidgets('member: read-only summary, no invite code', (tester) async {
    repo.family = testFamily(inviteCode: null);
    await pumpFamilyApp(
      tester,
      location: AppRoutes.familySettings,
      repo: repo,
      session: FakeSession(sessionFor(kamla)),
    );
    expect(find.text('Sharma Family'), findsOneWidget);
    expect(find.text(l10n.familySettingsReadOnly), findsOneWidget);
    expect(find.text(l10n.familyInviteCodeAdminOnly), findsOneWidget);
    expect(find.byType(InviteCodeCells), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.widgetWithText(FilledButton, l10n.commonSave), findsNothing);

    await tapVisible(tester, find.text(l10n.familyMembersCount(4)));
    expect(find.byType(MembersScreen), findsOneWidget);
  });

  group('edge cases', () {
    testWidgets('promoted to admin while open → editable view with the code', (
      tester,
    ) async {
      final session = FakeSession(sessionFor(kamla));
      repo.family = testFamily(inviteCode: null);
      await pumpFamilyApp(
        tester,
        location: AppRoutes.familySettings,
        repo: repo,
        session: session,
      );
      expect(find.text(l10n.familySettingsReadOnly), findsOneWidget);

      repo.family = testFamily(); // the server now returns the code
      await session.applyMe(null, kamla.copyWith(role: MemberRole.admin));
      await tester.pumpAndSettle();
      expect(find.text(l10n.familySettingsReadOnly), findsNothing);
      expect(codeCells(tester), 'K7Q2M9XD'.split(''));
    });

    testWidgets('a quick second tap on "New code" opens one dialog', (
      tester,
    ) async {
      await pumpFamilyApp(
        tester,
        location: AppRoutes.familySettings,
        repo: repo,
        session: FakeSession(sessionFor(amit)),
      );
      final regenerate = tester
          .widget<AppButton>(
            find.widgetWithText(AppButton, l10n.familyNewInviteCode),
          )
          .onPressed!;
      regenerate();
      await tester.pump();
      regenerate();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog, skipOffstage: false), findsOneWidget);
    });

    testWidgets('a changed family (other phone) reaches the session', (
      tester,
    ) async {
      final session = FakeSession(sessionFor(amit));
      repo.family = testFamily(currency: 'USD');
      await pumpFamilyApp(
        tester,
        location: AppRoutes.familySettings,
        repo: repo,
        session: session,
      );
      expect(session.applied.single.family?.currency, 'USD');
    });

    testWidgets('removed from the family (NO_FAMILY) resyncs the session', (
      tester,
    ) async {
      final session = FakeSession(sessionFor(amit));
      repo.familyError = apiError(ApiErrorCode.noFamily, 403);
      await pumpFamilyApp(
        tester,
        location: AppRoutes.familySettings,
        repo: repo,
        session: session,
      );
      expect(find.text(l10n.errorNoFamily), findsOneWidget);
      expect(session.refreshes, 1);
    });

    testWidgets('save while offline keeps the edits; the retry succeeds', (
      tester,
    ) async {
      repo.updateFamilyError = const ApiException.network();
      await pumpFamilyApp(
        tester,
        location: AppRoutes.familySettings,
        repo: repo,
        session: FakeSession(sessionFor(amit)),
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, l10n.familyNameFieldLabel),
        'Sharma Parivar',
      );
      await tapVisible(
        tester,
        find.widgetWithText(FilledButton, l10n.commonSave),
      );
      expect(find.text(l10n.errorNetwork), findsOneWidget);
      expect(find.text('Sharma Parivar'), findsOneWidget);

      repo.updateFamilyError = null;
      await tapVisible(
        tester,
        find.widgetWithText(FilledButton, l10n.commonSave),
      );
      expect(repo.lastBody('updateFamily'), {'name': 'Sharma Parivar'});
      expect(find.text(l10n.familySettingsSaved), findsOneWidget);
    });
  });
}
