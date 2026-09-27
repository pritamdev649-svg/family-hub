import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/network/api_exception.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/services/location_service.dart';
import 'package:family_hub/core/settings/settings_controller.dart';
import 'package:family_hub/core/settings/text_scale.dart';
import 'package:family_hub/features/settings/presentation/screens/about_screen.dart';
import 'package:family_hub/features/settings/presentation/screens/appearance_screen.dart';
import 'package:family_hub/features/settings/presentation/screens/change_password_screen.dart';
import 'package:family_hub/features/settings/presentation/screens/data_export_screen.dart';
import 'package:family_hub/features/settings/presentation/screens/language_screen.dart';
import 'package:family_hub/features/settings/presentation/screens/location_sharing_screen.dart';
import 'package:family_hub/features/settings/presentation/screens/privacy_screen.dart';
import 'package:family_hub/features/settings/presentation/screens/profile_screen.dart';
import 'package:family_hub/l10n/app_localizations.dart';
import 'package:family_hub/shared/models/models.dart';

import 'settings_test_utils.dart';

void main() {
  late SettingsHarness h;
  late AppLocalizations l10n;

  setUpAll(() async => l10n = await englishL10n());
  tearDown(() => h.dispose());

  group('ProfileScreen', () {
    testWidgets('save is enabled only after a change; sends the diff', (
      tester,
    ) async {
      h = await SettingsHarness.create(
        handlers: {
          'PATCH /me': (call) =>
              meResponse(member: {'name': call.json['name']}),
        },
      );
      await pumpSettingsScreen(tester, h, const ProfileScreen());

      final save = find.widgetWithText(FilledButton, l10n.commonSave);
      expect(tester.widget<FilledButton>(save).onPressed, isNull);

      await tester.enterText(
        find.widgetWithText(TextFormField, l10n.settingsProfileName),
        'Amit Kumar',
      );
      await tester.pump();
      expect(tester.widget<FilledButton>(save).onPressed, isNotNull);

      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(h.api.callsTo('PATCH /me').single.json, {'name': 'Amit Kumar'});
      expect(h.session.member!.name, 'Amit Kumar');
      expect(find.text('route:${AppRoutes.more}'), findsOneWidget);
    });

    testWidgets('validates name and phone before sending', (tester) async {
      h = await SettingsHarness.create();
      await pumpSettingsScreen(tester, h, const ProfileScreen());

      await tester.enterText(
        find.widgetWithText(TextFormField, l10n.settingsProfileName),
        '   ',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, l10n.settingsProfilePhone),
        'abc',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, l10n.commonSave));
      await tester.pumpAndSettle();

      expect(find.text(l10n.validationRequired), findsOneWidget);
      expect(find.text(l10n.validationPhone), findsOneWidget);
      expect(h.api.calls, isEmpty);
    });

    testWidgets('choosing a gender and clearing it', (tester) async {
      h = await SettingsHarness.create(
        handlers: {
          'PATCH /me': (call) => meResponse(member: {'gender': null}),
        },
      );
      await pumpSettingsScreen(tester, h, const ProfileScreen());

      await tester.tap(find.text(l10n.genderUnspecified));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, l10n.commonSave));
      await tester.pumpAndSettle();

      expect(h.api.callsTo('PATCH /me').single.json, {'gender': null});
    });

    testWidgets('unchanged date of birth is not re-sent', (tester) async {
      // Server DOB = local midnight in India, stored as UTC.
      h = await SettingsHarness.create(
        handlers: {
          'PATCH /me': (call) => meResponse(member: {'phone': null}),
        },
      );
      await pumpSettingsScreen(tester, h, const ProfileScreen());

      await tester.enterText(
        find.widgetWithText(TextFormField, l10n.settingsProfilePhone),
        '',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, l10n.commonSave));
      await tester.pumpAndSettle();

      final body = h.api.callsTo('PATCH /me').single.json;
      expect(body, {'phone': null});
    });

    testWidgets('without a family shows the empty state', (tester) async {
      h = await SettingsHarness.create(session: sessionWith(withFamily: false));
      await pumpSettingsScreen(tester, h, const ProfileScreen());
      expect(find.text(l10n.settingsNoFamilyTitle), findsOneWidget);
    });
  });

  group('LanguageScreen', () {
    testWidgets('lists every language and switches instantly', (tester) async {
      h = await SettingsHarness.create(
        handlers: {
          'PATCH /me': (call) =>
              meResponse(user: {'locale': call.json['locale']}),
        },
      );
      await pumpSettingsScreen(tester, h, const LanguageScreen());

      expect(find.text(l10n.settingsLanguageDevice), findsOneWidget);
      expect(find.text('தமிழ்'), findsOneWidget);
      expect(find.text('Tamil'), findsOneWidget);
      // "Phone language" is selected by default.
      expect(
        tester
            .widget<ListTile>(
              find.widgetWithText(ListTile, l10n.settingsLanguageDevice),
            )
            .selected,
        isTrue,
      );

      await tester.tap(find.text('हिन्दी'));
      await tester.pumpAndSettle();

      expect(h.container.read(settingsControllerProvider).localeCode, 'hi');
      expect(h.api.callsTo('PATCH /me').single.json, {'locale': 'hi'});
      expect(
        tester
            .widget<ListTile>(find.widgetWithText(ListTile, 'हिन्दी'))
            .selected,
        isTrue,
      );
    });
  });

  group('AppearanceScreen', () {
    testWidgets('theme mode and large text apply immediately', (tester) async {
      h = await SettingsHarness.create();
      await pumpSettingsScreen(tester, h, const AppearanceScreen());

      final semantics = tester.ensureSemantics();
      await tester.tap(find.text(l10n.settingsThemeDark));
      await tester.pumpAndSettle();
      expect(
        h.container.read(settingsControllerProvider).themeMode,
        ThemeMode.dark,
      );
      // The theme cards behave like radio buttons for screen readers.
      expect(
        tester.getSemantics(find.text(l10n.settingsThemeDark)),
        containsSemantics(isChecked: true, isInMutuallyExclusiveGroup: true),
      );
      expect(
        tester.getSemantics(find.text(l10n.settingsThemeLight)),
        containsSemantics(isChecked: false, isInMutuallyExclusiveGroup: true),
      );
      semantics.dispose();

      double previewScale() =>
          MediaQuery.textScalerOf(
            tester.element(find.text(l10n.settingsAppearancePreviewBody)),
          ).scale(10) /
          10;

      expect(previewScale(), lessThan(AppTextScale.largeTextMin));
      await tester.tap(find.text(l10n.settingsAppearanceLargeText));
      await tester.pumpAndSettle();
      expect(h.container.read(settingsControllerProvider).largeText, isTrue);
      expect(previewScale(), greaterThanOrEqualTo(AppTextScale.largeTextMin));
    });
  });

  group('LocationSharingScreen', () {
    Map<String, ApiHandler> handlers() => {
      'PATCH /me': (call) =>
          meResponse(member: {'locationSharing': call.json['locationSharing']}),
      'PUT /me/location': (_) => {'recordedAt': '2026-09-26T10:00:00.000Z'},
    };

    testWidgets('"Always share" with permission shows the indicator', (
      tester,
    ) async {
      h = await SettingsHarness.create(
        location: FakeLocationService(fix: testFix()),
        handlers: handlers(),
      );
      await pumpSettingsScreen(tester, h, const LocationSharingScreen());
      expect(find.text(l10n.settingsLocationSharedNow), findsNothing);

      await tester.tap(find.text(l10n.locationSharingAlways));
      await tester.pumpAndSettle();

      expect(h.session.member!.locationSharing, LocationSharingMode.always);
      expect(h.api.callsTo('PUT /me/location'), hasLength(1));
      expect(find.text(l10n.settingsLocationSharedNow), findsOneWidget);
      expect(find.text(l10n.settingsLocationSaved), findsOneWidget);
    });

    testWidgets('denied permission explains and offers the settings', (
      tester,
    ) async {
      final location = FakeLocationService(
        permission: LocationPermissionState.deniedForever,
      );
      h = await SettingsHarness.create(
        location: location,
        handlers: handlers(),
      );
      await pumpSettingsScreen(tester, h, const LocationSharingScreen());

      await tester.tap(find.text(l10n.locationSharingAlways));
      await tester.pumpAndSettle();

      expect(h.api.calls, isEmpty);
      expect(h.session.member!.locationSharing, LocationSharingMode.never);
      expect(find.text(l10n.servicesLocationDeniedForever), findsOneWidget);

      await tester.tap(find.text(l10n.servicesOpenSettings));
      await tester.pumpAndSettle();
      expect(location.settingsOpened, 1);
    });

    testWidgets('returning from the phone settings with permission finishes', (
      tester,
    ) async {
      final location = FakeLocationService(
        permission: LocationPermissionState.deniedForever,
      );
      h = await SettingsHarness.create(
        location: location,
        handlers: handlers(),
      );
      await pumpSettingsScreen(tester, h, const LocationSharingScreen());
      await tester.tap(find.text(l10n.locationSharingAlways));
      await tester.pumpAndSettle();
      expect(find.text(l10n.servicesLocationDeniedForever), findsOneWidget);

      // The member allows location in the phone settings and comes back.
      location
        ..permission = LocationPermissionState.granted
        ..fix = testFix();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.text(l10n.servicesLocationDeniedForever), findsNothing);
      expect(h.session.member!.locationSharing, LocationSharingMode.always);
      expect(find.text(l10n.settingsLocationSharedNow), findsOneWidget);
    });

    testWidgets('switching to "Only during SOS" saves without permission', (
      tester,
    ) async {
      final location = FakeLocationService();
      h = await SettingsHarness.create(
        session: sessionWith(member: {'locationSharing': 'always'}),
        location: location,
        handlers: handlers(),
      );
      await pumpSettingsScreen(tester, h, const LocationSharingScreen());
      expect(find.text(l10n.settingsLocationSharedNow), findsOneWidget);

      await tester.tap(find.text(l10n.locationSharingSosOnly));
      await tester.pumpAndSettle();

      expect(location.requests, 0);
      expect(h.api.callsTo('PATCH /me').single.json, {
        'locationSharing': 'sos_only',
      });
      expect(find.text(l10n.settingsLocationSharedNow), findsNothing);
    });
  });

  group('ChangePasswordScreen', () {
    Future<void> fill(WidgetTester tester, String current, String next) async {
      await tester.enterText(
        find.widgetWithText(TextFormField, l10n.settingsPasswordCurrent),
        current,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, l10n.settingsPasswordNew),
        next,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, l10n.settingsPasswordConfirm),
        next,
      );
      await tester.tap(
        find.widgetWithText(FilledButton, l10n.settingsChangePassword),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('validates locally', (tester) async {
      h = await SettingsHarness.create();
      await pumpSettingsScreen(tester, h, const ChangePasswordScreen());

      await fill(tester, 'same1234', 'same1234');
      expect(find.text(l10n.settingsPasswordSameAsCurrent), findsOneWidget);

      await fill(tester, 'old12345', 'short');
      expect(find.text(l10n.validationPasswordLength), findsOneWidget);
      expect(h.api.calls, isEmpty);
    });

    testWidgets('wrong current password is shown on that field', (
      tester,
    ) async {
      h = await SettingsHarness.create(
        handlers: {
          'POST /auth/change-password': (_) => throw const ApiException(
            code: ApiErrorCode.invalidCredentials,
            statusCode: 401,
          ),
        },
      );
      await pumpSettingsScreen(tester, h, const ChangePasswordScreen());

      await fill(tester, 'wrong123', 'new12345');
      expect(find.text(l10n.settingsPasswordWrongCurrent), findsOneWidget);
    });

    testWidgets('success closes the screen', (tester) async {
      h = await SettingsHarness.create(
        handlers: {
          'POST /auth/change-password': (_) => {'changed': true},
        },
      );
      await pumpSettingsScreen(tester, h, const ChangePasswordScreen());

      await fill(tester, 'old12345', 'new12345');
      expect(h.api.callsTo('POST /auth/change-password'), hasLength(1));
      expect(find.text('route:${AppRoutes.more}'), findsOneWidget);
    });
  });

  group('PrivacyScreen', () {
    testWidgets('leaving as the last admin explains the rule', (tester) async {
      h = await SettingsHarness.create(
        handlers: {
          'POST /me/leave-family': (_) => throw const ApiException(
            code: ApiErrorCode.lastAdmin,
            statusCode: 409,
          ),
        },
      );
      await pumpSettingsScreen(tester, h, const PrivacyScreen());

      await tester.tap(find.text(l10n.settingsLeaveFamily));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(l10n.settingsLeaveFamily),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.settingsLastAdminTitle), findsOneWidget);
      await tester.tap(find.text(l10n.settingsLastAdminOpenMembers));
      await tester.pumpAndSettle();
      expect(find.text('route:${AppRoutes.members}'), findsOneWidget);
      expect(h.session.family, isNotNull);
    });

    testWidgets('delete account: wrong password stays in the dialog', (
      tester,
    ) async {
      var attempts = 0;
      h = await SettingsHarness.create(
        handlers: {
          'DELETE /me': (call) {
            attempts++;
            if (call.json['password'] != 'demo1234') {
              throw const ApiException(
                code: ApiErrorCode.invalidCredentials,
                statusCode: 401,
              );
            }
            return null;
          },
        },
      );
      await pumpSettingsScreen(tester, h, const PrivacyScreen());

      await tester.tap(find.text(l10n.settingsDeleteAccount));
      await tester.pumpAndSettle();
      expect(find.text(l10n.settingsDeleteAccountTitle), findsOneWidget);

      final password = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextFormField),
      );
      final confirm = find.text(l10n.settingsDeleteAccountConfirm);

      // Empty password → required.
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(find.text(l10n.validationRequired), findsOneWidget);
      expect(attempts, 0);

      await tester.enterText(password, 'wrong');
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(
        find.text(l10n.settingsDeleteAccountWrongPassword),
        findsOneWidget,
      );
      expect(h.session.isSignedIn, isTrue);

      await tester.enterText(password, 'demo1234');
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(h.session.isSignedIn, isFalse);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('delete account as the last admin explains the rule', (
      tester,
    ) async {
      h = await SettingsHarness.create(
        handlers: {
          'DELETE /me': (_) => throw const ApiException(
            code: ApiErrorCode.lastAdmin,
            statusCode: 409,
          ),
        },
      );
      await pumpSettingsScreen(tester, h, const PrivacyScreen());

      await tester.tap(find.text(l10n.settingsDeleteAccount));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextFormField),
        ),
        'demo1234',
      );
      await tester.tap(find.text(l10n.settingsDeleteAccountConfirm));
      await tester.pumpAndSettle();

      expect(find.text(l10n.settingsLastAdminDeleteMessage), findsOneWidget);
      expect(h.session.isSignedIn, isTrue);
    });

    testWidgets('export opens the data screen with summary and JSON', (
      tester,
    ) async {
      h = await SettingsHarness.create(
        handlers: {
          'GET /me/export': (_) => {
            'user': userJson(),
            'tasks': [
              {'id': 't1', 'title': 'Maths'},
            ],
          },
        },
      );
      await pumpSettingsScreen(tester, h, const PrivacyScreen());

      await tester.tap(find.text(l10n.settingsExportData));
      await tester.pumpAndSettle();

      expect(find.byType(DataExportScreen), findsOneWidget);
      expect(find.text(l10n.settingsExportSectionTasks), findsOneWidget);
      expect(find.text(l10n.settingsExportItemCount(1)), findsOneWidget);
      expect(find.textContaining('"title": "Maths"'), findsOneWidget);
    });

    testWidgets('export errors can be retried', (tester) async {
      var fail = true;
      h = await SettingsHarness.create(
        handlers: {
          'GET /me/export': (_) {
            if (fail) throw const ApiException.network();
            return {'user': userJson()};
          },
        },
      );
      await pumpSettingsScreen(tester, h, const PrivacyScreen());
      await tester.tap(find.text(l10n.settingsExportData));
      await tester.pumpAndSettle();

      expect(find.text(l10n.errorNetwork), findsOneWidget);
      fail = false;
      await tester.tap(find.text(l10n.commonRetry));
      await tester.pumpAndSettle();
      expect(find.text(l10n.settingsExportSectionUser), findsOneWidget);
    });
  });

  group('AboutScreen', () {
    testWidgets('shows the disclaimers with the country emergency number', (
      tester,
    ) async {
      h = await SettingsHarness.create();
      await pumpSettingsScreen(tester, h, const AboutScreen());

      expect(find.text(l10n.settingsAboutMission), findsOneWidget);
      expect(find.text(l10n.settingsAboutSosDisclaimer('112')), findsOneWidget);
      expect(find.text(l10n.settingsAboutCallEmergency('112')), findsOneWidget);
      expect(find.text(l10n.settingsAboutMedicalDisclaimer), findsOneWidget);
      expect(find.text(l10n.settingsAboutLedgerNote), findsOneWidget);
      expect(find.text(l10n.settingsAboutLicenses), findsOneWidget);
    });
  });

  // ── Edge cases (f-settings-harden) ────────────────────────────────────────

  group('edge cases', () {
    Finder field(String label) => find.widgetWithText(TextFormField, label);
    Finder save() => find.widgetWithText(FilledButton, l10n.commonSave);

    testWidgets('profile: a phone the server rejects is shown on the field '
        'and clears when edited', (tester) async {
      h = await SettingsHarness.create(
        handlers: {
          'PATCH /me': (_) => throw const ApiException(
            code: ApiErrorCode.validation,
            statusCode: 422,
            details: {'phone': 'Invalid phone number'},
          ),
        },
      );
      await pumpSettingsScreen(tester, h, const ProfileScreen());

      await tester.enterText(field(l10n.settingsProfilePhone), '+9112345678');
      await tester.pump();
      await tester.tap(save());
      await tester.pumpAndSettle();

      expect(find.text(l10n.validationPhone), findsOneWidget);
      expect(find.byType(ProfileScreen), findsOneWidget, reason: 'stays open');

      await tester.enterText(field(l10n.settingsProfilePhone), '+9112345679');
      await tester.pump();
      expect(find.text(l10n.validationPhone), findsNothing);
    });

    testWidgets('profile: GUARDIAN_CONSENT_REQUIRED lands on the birth date', (
      tester,
    ) async {
      h = await SettingsHarness.create(
        handlers: {
          'PATCH /me': (_) => throw const ApiException(
            code: ApiErrorCode.guardianConsentRequired,
            statusCode: 422,
            details: {'consentAge': 18},
          ),
        },
      );
      await pumpSettingsScreen(tester, h, const ProfileScreen());

      await tester.enterText(field(l10n.settingsProfileName), 'Amit K');
      await tester.pump();
      await tester.tap(save());
      await tester.pumpAndSettle();

      expect(
        find.text(l10n.settingsProfileGuardianConsentNeeded(18)),
        findsOneWidget,
      );
    });

    testWidgets('profile: network error keeps the edits and shows a snackbar', (
      tester,
    ) async {
      h = await SettingsHarness.create(
        handlers: {'PATCH /me': (_) => throw const ApiException.network()},
      );
      await pumpSettingsScreen(tester, h, const ProfileScreen());

      await tester.enterText(field(l10n.settingsProfileName), 'Amit K');
      await tester.pump();
      await tester.tap(save());
      await tester.pumpAndSettle();

      expect(find.text(l10n.errorNetwork), findsOneWidget);
      expect(find.text('Amit K'), findsOneWidget);
      expect(h.session.member!.name, 'Amit');
    });

    testWidgets('profile: a very long name fits (large text + RTL)', (
      tester,
    ) async {
      final longName = 'Aarav ' * 10;
      h = await SettingsHarness.create(
        session: sessionWith(member: {'name': longName.trim()}),
      );
      await pumpSettingsScreen(
        tester,
        h,
        const ProfileScreen(),
        textScale: 1.4,
        textDirection: TextDirection.rtl,
        surfaceSize: const Size(360, 2400),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(ProfileScreen), findsOneWidget);
    });

    testWidgets('change password: the wrong-password error clears on edit', (
      tester,
    ) async {
      h = await SettingsHarness.create(
        handlers: {
          'POST /auth/change-password': (_) => throw const ApiException(
            code: ApiErrorCode.invalidCredentials,
            statusCode: 401,
          ),
        },
      );
      await pumpSettingsScreen(tester, h, const ChangePasswordScreen());
      await tester.enterText(field(l10n.settingsPasswordCurrent), 'wrong123');
      await tester.enterText(field(l10n.settingsPasswordNew), 'new12345');
      await tester.enterText(field(l10n.settingsPasswordConfirm), 'new12345');
      await tester.tap(
        find.widgetWithText(FilledButton, l10n.settingsChangePassword),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.settingsPasswordWrongCurrent), findsOneWidget);

      await tester.enterText(field(l10n.settingsPasswordCurrent), 'right123');
      await tester.pump();
      expect(find.text(l10n.settingsPasswordWrongCurrent), findsNothing);
    });

    testWidgets('delete dialog: the wrong-password error clears on edit', (
      tester,
    ) async {
      h = await SettingsHarness.create(
        handlers: {
          'DELETE /me': (_) => throw const ApiException(
            code: ApiErrorCode.invalidCredentials,
            statusCode: 401,
          ),
        },
      );
      await pumpSettingsScreen(tester, h, const PrivacyScreen());
      await tester.tap(find.text(l10n.settingsDeleteAccount));
      await tester.pumpAndSettle();
      final password = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(password, 'wrong');
      await tester.tap(find.text(l10n.settingsDeleteAccountConfirm));
      await tester.pumpAndSettle();
      expect(
        find.text(l10n.settingsDeleteAccountWrongPassword),
        findsOneWidget,
      );

      await tester.enterText(password, 'wrong2');
      await tester.pump();
      expect(find.text(l10n.settingsDeleteAccountWrongPassword), findsNothing);
    });

    testWidgets('location: "always" without permission is explained on open '
        'and shares once permission is back', (tester) async {
      final location = FakeLocationService(
        permission: LocationPermissionState.deniedForever,
      );
      h = await SettingsHarness.create(
        session: sessionWith(member: {'locationSharing': 'always'}),
        location: location,
        handlers: {
          'PUT /me/location': (_) => {'recordedAt': '2026-09-26T10:00:00.000Z'},
        },
      );
      await pumpSettingsScreen(tester, h, const LocationSharingScreen());

      expect(find.text(l10n.servicesLocationDeniedForever), findsOneWidget);
      expect(location.requests, 0, reason: 'checking never prompts');
      expect(h.api.calls, isEmpty);

      location
        ..permission = LocationPermissionState.granted
        ..fix = testFix();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.text(l10n.servicesLocationDeniedForever), findsNothing);
      expect(h.api.callsTo('PUT /me/location'), hasLength(1));
      expect(find.text(l10n.settingsLocationUpdated), findsOneWidget);
    });

    testWidgets('location: permission revoked while the screen is open', (
      tester,
    ) async {
      final location = FakeLocationService();
      h = await SettingsHarness.create(
        session: sessionWith(member: {'locationSharing': 'always'}),
        location: location,
      );
      await pumpSettingsScreen(tester, h, const LocationSharingScreen());
      expect(find.text(l10n.servicesLocationDenied), findsNothing);

      location.permission = LocationPermissionState.denied;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.text(l10n.servicesLocationDenied), findsOneWidget);
      expect(find.text(l10n.servicesLocationAllow), findsOneWidget);
    });

    testWidgets('location: rapid taps save only one mode', (tester) async {
      h = await SettingsHarness.create(
        handlers: {
          'PATCH /me': (call) => meResponse(
            member: {'locationSharing': call.json['locationSharing']},
          ),
        },
      );
      await pumpSettingsScreen(tester, h, const LocationSharingScreen());

      await tester.tap(find.text(l10n.locationSharingSosOnly));
      await tester.pump();
      await tester.tap(find.text(l10n.locationSharingSosOnly));
      await tester.tap(find.text(l10n.locationSharingNever));
      await tester.pumpAndSettle();

      expect(h.api.callsTo('PATCH /me'), hasLength(1));
      expect(h.session.member!.locationSharing, LocationSharingMode.sosOnly);
    });

    testWidgets('privacy: the only member is warned that the family goes', (
      tester,
    ) async {
      h = await SettingsHarness.create(
        session: sessionWith(family: {'memberCount': 1}),
      );
      await pumpSettingsScreen(tester, h, const PrivacyScreen());

      await tester.tap(find.text(l10n.settingsLeaveFamily));
      await tester.pumpAndSettle();

      expect(
        find.text(l10n.settingsLeaveFamilyOnlyMemberMessage),
        findsOneWidget,
      );
      await tester.tap(find.text(l10n.commonCancel));
      await tester.pumpAndSettle();
      expect(h.api.calls, isEmpty);
    });

    testWidgets('privacy: leaving twice quickly sends one request', (
      tester,
    ) async {
      final noFamily = userJson({
        'familyId': null,
        'memberId': null,
        'role': null,
      });
      h = await SettingsHarness.create(
        handlers: {
          'POST /me/leave-family': (_) => {'user': noFamily},
          'GET /auth/me': (_) => {
            'user': noFamily,
            'member': null,
            'family': null,
          },
        },
      );
      await pumpSettingsScreen(tester, h, const PrivacyScreen());
      await tester.tap(find.text(l10n.settingsLeaveFamily));
      await tester.pumpAndSettle();
      final confirm = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(l10n.settingsLeaveFamily),
      );
      await tester.tap(confirm);
      await tester.pump();
      // The busy row ignores further taps.
      await tester.tap(
        find.text(l10n.settingsLeaveFamily).first,
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(h.api.callsTo('POST /me/leave-family'), hasLength(1));
      expect(h.session.needsFamily, isTrue);
    });

    testWidgets('export: a very large export is rendered lazily', (
      tester,
    ) async {
      h = await SettingsHarness.create(
        handlers: {
          'GET /me/export': (_) => {
            'user': userJson(),
            'tasks': [
              for (var i = 0; i < 3000; i++) {'id': 't$i', 'title': 'Task $i'},
            ],
          },
        },
      );
      await pumpSettingsScreen(tester, h, const PrivacyScreen());
      await tester.tap(find.text(l10n.settingsExportData));
      await tester.pumpAndSettle();

      expect(find.text(l10n.settingsExportItemCount(3000)), findsOneWidget);
      expect(find.textContaining('"id": "t0"'), findsOneWidget);
      expect(
        find.textContaining('"id": "t2999"'),
        findsNothing,
        reason: 'lines far below the fold are not built',
      );

      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
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
      await tester.tap(find.byTooltip(l10n.settingsExportCopy));
      await tester.pumpAndSettle();
      expect(find.text(l10n.commonCopied), findsOneWidget);
      expect(copied, contains('"id": "t2999"'), reason: 'copies everything');
    });
  });
}
