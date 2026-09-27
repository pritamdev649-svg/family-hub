import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/settings/settings_controller.dart';
import 'package:family_hub/features/settings/domain/app_info.dart';
import 'package:family_hub/features/settings/domain/notification_status.dart';
import 'package:family_hub/features/settings/presentation/screens/more_screen.dart';
import 'package:family_hub/l10n/app_localizations.dart';

import 'settings_test_utils.dart';

void main() {
  late SettingsHarness h;
  late AppLocalizations l10n;

  setUpAll(() async => l10n = await englishL10n());
  tearDown(() => h.dispose());

  testWidgets('shows the profile header, all sections and the version', (
    tester,
  ) async {
    h = await SettingsHarness.create(
      session: sessionWith(member: {'locationSharing': 'sos_only'}),
      prefs: {SettingsKeys.localeCode: 'hi', SettingsKeys.themeMode: 'dark'},
    );
    await pumpSettingsScreen(tester, h, const MoreScreen());

    // Profile header.
    expect(find.text('Amit'), findsOneWidget);
    expect(find.text('Head of Family'), findsOneWidget);
    expect(find.text('Sharma Family'), findsOneWidget);

    // Sections.
    for (final title in [
      l10n.settingsSectionFamily,
      l10n.settingsSectionPreferences,
      l10n.settingsSectionAccount,
    ]) {
      expect(find.text(title), findsOneWidget);
    }
    for (final entry in [
      l10n.settingsMembers,
      l10n.settingsFamilySettings,
      l10n.settingsNoticeBoard,
      l10n.settingsEmergencyCards,
      l10n.settingsSosHistory,
      l10n.settingsChangePassword,
      l10n.settingsPrivacy,
      l10n.settingsAbout,
    ]) {
      expect(find.text(entry), findsOneWidget, reason: entry);
    }

    // Preference subtitles: native language name, theme, location mode,
    // notification status.
    expect(find.text('हिन्दी'), findsOneWidget);
    expect(find.text(l10n.settingsThemeDark), findsOneWidget);
    expect(find.text(l10n.locationSharingSosOnly), findsOneWidget);
    expect(find.text(l10n.settingsNotificationsEnabled), findsOneWidget);

    expect(
      find.text(l10n.settingsVersion(AppInfo.displayVersion)),
      findsOneWidget,
    );
  });

  testWidgets('members do not see family settings', (tester) async {
    h = await SettingsHarness.create(
      session: sessionWith(
        user: {'role': 'member'},
        member: {'role': 'member', 'designation': null},
      ),
    );
    await pumpSettingsScreen(tester, h, const MoreScreen());

    expect(find.text(l10n.settingsMembers), findsOneWidget);
    expect(find.text(l10n.settingsFamilySettings), findsNothing);
    // No designation → the role is shown instead.
    expect(find.text(l10n.roleMember), findsOneWidget);
  });

  testWidgets('without a family: no shortcuts, preferences still shown', (
    tester,
  ) async {
    h = await SettingsHarness.create(session: sessionWith(withFamily: false));
    await pumpSettingsScreen(tester, h, const MoreScreen());

    // Account name and email instead of a family profile; nothing to edit.
    expect(find.text('Amit Sharma'), findsOneWidget);
    expect(find.text('amit@example.com'), findsOneWidget);
    expect(find.text(l10n.settingsEditProfile), findsNothing);
    // Family shortcuts and member-only rows are hidden.
    expect(find.text(l10n.settingsMembers), findsNothing);
    expect(find.text(l10n.settingsSectionFamily), findsNothing);
    expect(find.text(l10n.settingsLocationSharing), findsNothing);
    expect(find.text(l10n.settingsLanguage), findsOneWidget);
    expect(find.text(l10n.settingsLogout), findsOneWidget);
  });

  testWidgets('large text keeps the current value readable', (tester) async {
    h = await SettingsHarness.create(prefs: {SettingsKeys.themeMode: 'system'});
    await pumpSettingsScreen(
      tester,
      h,
      const MoreScreen(),
      textScale: 1.6,
      surfaceSize: const Size(360, 3200),
    );
    expect(tester.takeException(), isNull);
    // Too long to share a line with "Appearance": shown in full below it.
    final value = find.text(l10n.settingsThemeSystem);
    expect(value, findsOneWidget);
    expect(
      tester.getTopLeft(value).dy,
      greaterThan(tester.getTopLeft(find.text(l10n.settingsAppearance)).dy),
    );
  });

  testWidgets('entries navigate with AppRoutes', (tester) async {
    h = await SettingsHarness.create();
    await pumpSettingsScreen(tester, h, const MoreScreen());

    await tester.tap(find.text(l10n.settingsMembers));
    await tester.pumpAndSettle();
    expect(find.text('route:${AppRoutes.members}'), findsOneWidget);
  });

  testWidgets('profile header opens the profile screen', (tester) async {
    h = await SettingsHarness.create();
    await pumpSettingsScreen(tester, h, const MoreScreen());

    await tester.tap(find.text('Head of Family'));
    await tester.pumpAndSettle();
    expect(find.text('route:${AppRoutes.settingsProfile}'), findsOneWidget);
  });

  testWidgets('disabled notifications link to the phone settings', (
    tester,
  ) async {
    h = await SettingsHarness.create(
      system: FakeSystemSettings(NotificationStatus.disabled),
    );
    await pumpSettingsScreen(tester, h, const MoreScreen());

    await tester.tap(find.text(l10n.settingsNotificationsDisabled));
    await tester.pumpAndSettle();
    expect(h.system.opened, 1);
  });

  testWidgets('unavailable push cannot be tapped', (tester) async {
    h = await SettingsHarness.create(
      system: FakeSystemSettings(NotificationStatus.unavailable),
    );
    await pumpSettingsScreen(tester, h, const MoreScreen());

    await tester.tap(find.text(l10n.settingsNotificationsUnavailable));
    await tester.pumpAndSettle();
    expect(h.system.opened, 0);
  });

  testWidgets('log out asks for confirmation, then signs out', (tester) async {
    h = await SettingsHarness.create(
      handlers: {'POST /auth/logout': (_) => null},
    );
    await pumpSettingsScreen(tester, h, const MoreScreen());

    await tester.tap(find.text(l10n.settingsLogout));
    await tester.pumpAndSettle();
    expect(find.text(l10n.settingsLogoutConfirmTitle), findsOneWidget);

    // Cancel keeps the session.
    await tester.tap(find.text(l10n.commonCancel));
    await tester.pumpAndSettle();
    expect(h.session.isSignedIn, isTrue);

    await tester.tap(find.text(l10n.settingsLogout));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(l10n.settingsLogout),
      ),
    );
    await tester.pumpAndSettle();
    expect(h.session.isSignedIn, isFalse);
  });

  testWidgets('large text + RTL renders without overflow', (tester) async {
    h = await SettingsHarness.create();
    await pumpSettingsScreen(
      tester,
      h,
      const MoreScreen(),
      textScale: 1.6,
      textDirection: TextDirection.rtl,
      surfaceSize: const Size(360, 3200),
    );
    expect(tester.takeException(), isNull);
    expect(find.text(l10n.settingsMembers), findsOneWidget);
  });
}
