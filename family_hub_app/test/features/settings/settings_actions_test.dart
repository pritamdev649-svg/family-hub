import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/network/api_exception.dart';
import 'package:family_hub/core/services/location_service.dart';
import 'package:family_hub/core/settings/settings_controller.dart';
import 'package:family_hub/features/settings/application/location_upload_clock.dart';
import 'package:family_hub/features/settings/application/settings_actions.dart';
import 'package:family_hub/features/settings/application/settings_providers.dart';
import 'package:family_hub/features/settings/domain/data_export.dart';
import 'package:family_hub/shared/models/models.dart';
import 'package:family_hub/shared/session/session_controller.dart';

import 'settings_test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SettingsHarness h;
  SettingsActions actions() => h.container.read(settingsActionsProvider);
  int membersVersion() =>
      h.container.read(dataRefreshProvider)[DataScope.members]!;

  tearDown(() => h.dispose());

  group('saveProfile', () {
    test(
      'sends only the changed fields, applies the session, marks members',
      () async {
        h = await SettingsHarness.create(
          handlers: {
            'PATCH /me': (call) => meResponse(
              user: {'name': 'Amit Kumar'},
              member: {'name': 'Amit Kumar', 'phone': null, 'gender': 'other'},
            ),
          },
        );
        final before = h.session.member!;
        final after = before.copyWith(
          name: 'Amit Kumar',
          phone: () => null,
          gender: () => Gender.other,
        );
        final version = membersVersion();

        final changed = await actions().saveProfile(before, after);

        expect(changed, isTrue);
        final calls = h.api.callsTo('PATCH /me');
        expect(calls, hasLength(1));
        expect(calls.single.json, {
          'name': 'Amit Kumar',
          'phone': null,
          'gender': 'other',
        });
        expect(h.session.member!.name, 'Amit Kumar');
        expect(h.session.member!.phone, isNull);
        expect(h.session.user!.name, 'Amit Kumar');
        expect(membersVersion(), greaterThan(version));
      },
    );

    test('nothing changed → no request', () async {
      h = await SettingsHarness.create();
      final member = h.session.member!;
      expect(await actions().saveProfile(member, member), isFalse);
      expect(h.api.calls, isEmpty);
    });

    test('server errors propagate and keep the session', () async {
      h = await SettingsHarness.create(
        handlers: {
          'PATCH /me': (_) => throw const ApiException(
            code: ApiErrorCode.validation,
            statusCode: 422,
          ),
        },
      );
      final before = h.session.member!;
      final error = await errorOf(
        actions().saveProfile(before, before.copyWith(name: 'X')),
      );
      expect((error as ApiException).code, ApiErrorCode.validation);
      expect(h.session.member, before);
    });
  });

  group('setLanguage', () {
    test('sets the device language and stores it on the account', () async {
      h = await SettingsHarness.create(
        handlers: {
          'PATCH /me': (call) =>
              meResponse(user: {'locale': call.json['locale']}),
        },
      );

      await actions().setLanguage('hi');

      expect(h.container.read(settingsControllerProvider).localeCode, 'hi');
      expect(h.api.callsTo('PATCH /me').single.json, {'locale': 'hi'});
      expect(h.session.user!.locale, 'hi');
    });

    test('account update is best effort (errors are swallowed)', () async {
      h = await SettingsHarness.create(
        handlers: {'PATCH /me': (_) => throw const ApiException.network()},
      );

      await actions().setLanguage('ta');

      expect(h.container.read(settingsControllerProvider).localeCode, 'ta');
      expect(h.session.user!.locale, 'en');
    });

    test('no request when the account already uses that language', () async {
      h = await SettingsHarness.create(
        session: sessionWith(user: {'locale': 'de'}),
      );
      await actions().setLanguage('de');
      expect(h.api.calls, isEmpty);
    });

    test(
      'quick successive changes: the last language wins, in order',
      () async {
        h = await SettingsHarness.create(
          handlers: {
            'PATCH /me': (call) =>
                meResponse(user: {'locale': call.json['locale']}),
          },
        );

        final first = actions().setLanguage('hi');
        final second = actions().setLanguage('bn');
        await Future.wait([first, second]);

        final sent = [
          for (final c in h.api.callsTo('PATCH /me')) c.json['locale'],
        ];
        expect(sent.last, 'bn');
        expect(h.session.user!.locale, 'bn');
        expect(h.container.read(settingsControllerProvider).localeCode, 'bn');
      },
    );

    test('"phone language" sends the effective language', () async {
      h = await SettingsHarness.create(
        prefs: {SettingsKeys.localeCode: 'hi'},
        session: sessionWith(user: {'locale': 'hi'}),
        handlers: {
          'PATCH /me': (call) =>
              meResponse(user: {'locale': call.json['locale']}),
        },
      );

      await actions().setLanguage(null);

      final effective = h.container.read(resolvedLocaleProvider).languageCode;
      expect(h.container.read(settingsControllerProvider).localeCode, isNull);
      if (effective == 'hi') {
        expect(h.api.calls, isEmpty);
      } else {
        expect(h.api.callsTo('PATCH /me').single.json, {'locale': effective});
      }
    });
  });

  group('setLocationSharing', () {
    Map<String, ApiHandler> sharingHandlers() => {
      'PATCH /me': (call) =>
          meResponse(member: {'locationSharing': call.json['locationSharing']}),
      'PUT /me/location': (_) => {'recordedAt': '2026-09-26T10:00:05.000Z'},
    };

    test('"always" without permission changes nothing', () async {
      final location = FakeLocationService(
        permission: LocationPermissionState.deniedForever,
      );
      h = await SettingsHarness.create(
        location: location,
        handlers: sharingHandlers(),
      );

      final result = await actions().setLocationSharing(
        LocationSharingMode.always,
      );

      expect(result.outcome, LocationSharingOutcome.permissionDenied);
      expect(result.permission, LocationPermissionState.deniedForever);
      expect(h.api.calls, isEmpty);
      expect(h.session.member!.locationSharing, LocationSharingMode.never);
    });

    test('"always" saves the mode and uploads a first fix', () async {
      final location = FakeLocationService(fix: testFix());
      h = await SettingsHarness.create(
        location: location,
        handlers: sharingHandlers(),
      );

      final result = await actions().setLocationSharing(
        LocationSharingMode.always,
      );

      expect(result.outcome, LocationSharingOutcome.shared);
      expect(result.sharedAt, DateTime.utc(2026, 9, 26, 10, 0, 5));
      expect(h.api.callsTo('PATCH /me').single.json, {
        'locationSharing': 'always',
      });
      expect(h.api.callsTo('PUT /me/location').single.json, {
        'lat': 28.61,
        'lng': 77.2,
        'accuracy': 12.0,
      });
      final member = h.session.member!;
      expect(member.locationSharing, LocationSharingMode.always);
      expect(member.lastLocation?.recordedAt, result.sharedAt);
      expect(h.container.read(locationUploadClockProvider), h.clock.now);
      expect(location.requests, greaterThanOrEqualTo(1));
    });

    test('"always" without a GPS fix is saved and reports noFix', () async {
      h = await SettingsHarness.create(
        location: FakeLocationService(),
        handlers: sharingHandlers(),
      );

      final result = await actions().setLocationSharing(
        LocationSharingMode.always,
      );

      expect(result.outcome, LocationSharingOutcome.noFix);
      expect(h.session.member!.locationSharing, LocationSharingMode.always);
      expect(h.api.callsTo('PUT /me/location'), isEmpty);
    });

    test('a failing first upload still keeps the saved mode', () async {
      h = await SettingsHarness.create(
        location: FakeLocationService(fix: testFix()),
        handlers: {
          ...sharingHandlers(),
          'PUT /me/location': (_) => throw const ApiException.network(),
        },
      );

      final result = await actions().setLocationSharing(
        LocationSharingMode.always,
      );

      expect(result.outcome, LocationSharingOutcome.noFix);
      expect(h.session.member!.locationSharing, LocationSharingMode.always);
      expect(h.container.read(locationUploadClockProvider), isNull);
    });

    test('other modes never touch location permission', () async {
      final location = FakeLocationService();
      h = await SettingsHarness.create(
        session: sessionWith(member: {'locationSharing': 'always'}),
        location: location,
        handlers: sharingHandlers(),
      );

      final result = await actions().setLocationSharing(
        LocationSharingMode.sosOnly,
      );

      expect(result.outcome, LocationSharingOutcome.saved);
      expect(location.requests, 0);
      expect(h.session.member!.locationSharing, LocationSharingMode.sosOnly);
    });

    test('same mode again → no PATCH', () async {
      h = await SettingsHarness.create(handlers: sharingHandlers());
      final result = await actions().setLocationSharing(
        LocationSharingMode.never,
      );
      expect(result.outcome, LocationSharingOutcome.saved);
      expect(h.api.calls, isEmpty);
    });

    test('without a family → NO_FAMILY', () async {
      h = await SettingsHarness.create(session: sessionWith(withFamily: false));
      final error = await errorOf(
        actions().setLocationSharing(LocationSharingMode.sosOnly),
      );
      expect((error as ApiException).code, ApiErrorCode.noFamily);
    });
  });

  group('shareLocationNow', () {
    test('LOCATION_SHARING_DISABLED propagates', () async {
      h = await SettingsHarness.create(
        session: sessionWith(member: {'locationSharing': 'always'}),
        location: FakeLocationService(fix: testFix()),
        handlers: {
          'PUT /me/location': (_) => throw const ApiException(
            code: ApiErrorCode.locationSharingDisabled,
            statusCode: 403,
          ),
        },
      );
      final error = await errorOf(actions().shareLocationNow());
      expect(
        (error as ApiException).code,
        ApiErrorCode.locationSharingDisabled,
      );
    });
  });

  group('account', () {
    test('changePassword posts both passwords', () async {
      h = await SettingsHarness.create(
        handlers: {
          'POST /auth/change-password': (_) => {'changed': true},
        },
      );
      await actions().changePassword(
        currentPassword: 'old12345',
        newPassword: 'new12345',
      );
      expect(h.api.callsTo('POST /auth/change-password').single.json, {
        'currentPassword': 'old12345',
        'newPassword': 'new12345',
      });
    });

    test('leaveFamily → session without family', () async {
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

      await actions().leaveFamily();
      await settle();

      expect(h.session.isSignedIn, isTrue);
      expect(h.session.member, isNull);
      expect(h.session.family, isNull);
      expect(h.session.needsFamily, isTrue);
    });

    test('leaveFamily LAST_ADMIN propagates and keeps the family', () async {
      h = await SettingsHarness.create(
        handlers: {
          'POST /me/leave-family': (_) => throw const ApiException(
            code: ApiErrorCode.lastAdmin,
            statusCode: 409,
          ),
        },
      );
      final error = await errorOf(actions().leaveFamily());
      expect((error as ApiException).code, ApiErrorCode.lastAdmin);
      expect(h.session.family, isNotNull);
    });

    test('deleteAccount sends the password and signs out', () async {
      h = await SettingsHarness.create(handlers: {'DELETE /me': (_) => null});

      await actions().deleteAccount('demo1234');

      expect(h.api.callsTo('DELETE /me').single.json, {'password': 'demo1234'});
      expect(h.session.isSignedIn, isFalse);
      expect(h.tokens.tokens, isNull);
    });

    test('deleteAccount with a wrong password keeps the session', () async {
      h = await SettingsHarness.create(
        handlers: {
          'DELETE /me': (_) => throw const ApiException(
            code: ApiErrorCode.invalidCredentials,
            statusCode: 401,
          ),
        },
      );
      final error = await errorOf(actions().deleteAccount('nope'));
      expect((error as ApiException).code, ApiErrorCode.invalidCredentials);
      expect(h.session.isSignedIn, isTrue);
      expect(h.tokens.tokens, isNotNull);
    });

    test('logout clears the session', () async {
      h = await SettingsHarness.create(
        handlers: {'POST /auth/logout': (_) => null},
      );
      await actions().logout();
      expect(h.session.isSignedIn, isFalse);
      expect(h.push.unregistrations, 1);
    });
  });

  group('dataExportProvider', () {
    test('parses GET /me/export', () async {
      h = await SettingsHarness.create(
        handlers: {
          'GET /me/export': (_) => {
            'user': userJson(),
            'tasks': [
              {'id': 't1'},
            ],
          },
        },
      );
      final sub = h.container.listen(dataExportProvider, (_, _) {});
      addTearDown(sub.close);
      final export = await h.container.read(dataExportProvider.future);
      expect(export.sections.map((s) => s.section), [
        DataExportSection.user,
        DataExportSection.tasks,
      ]);
      expect(export.exportedAt, h.clock.now);
    });
  });

  // ── Edge cases (f-settings-harden) ────────────────────────────────────────

  /// `GET /auth/me` payload: in the family (with [member] overrides) or not.
  Map<String, dynamic> authMe({
    Map<String, dynamic> member = const {},
    bool withFamily = true,
  }) => withFamily
      ? {
          'user': userJson(),
          'member': memberJson(member),
          'family': familyJson(),
        }
      : {
          'user': userJson({'familyId': null, 'memberId': null, 'role': null}),
          'member': null,
          'family': null,
        };

  const noFamilyError = ApiException(
    code: ApiErrorCode.noFamily,
    statusCode: 403,
  );

  group('stale session', () {
    test('NO_FAMILY on save re-reads the session (router → setup)', () async {
      h = await SettingsHarness.create(
        handlers: {
          'PATCH /me': (_) => throw noFamilyError,
          'GET /auth/me': (_) => authMe(withFamily: false),
        },
      );
      final before = h.session.member!;
      final error = await errorOf(
        actions().saveProfile(before, before.copyWith(name: 'New name')),
      );
      expect((error as ApiException).code, ApiErrorCode.noFamily);
      await settle();
      expect(h.api.callsTo('GET /auth/me'), hasLength(1));
      expect(h.session.needsFamily, isTrue);
    });

    test('mode changed on another phone: share now resyncs the mode', () async {
      h = await SettingsHarness.create(
        session: sessionWith(member: {'locationSharing': 'always'}),
        location: FakeLocationService(fix: testFix()),
        handlers: {
          'PUT /me/location': (_) => throw const ApiException(
            code: ApiErrorCode.locationSharingDisabled,
            statusCode: 403,
          ),
          'GET /auth/me': (_) => authMe(member: {'locationSharing': 'never'}),
        },
      );
      await errorOf(actions().shareLocationNow());
      await settle();
      expect(h.session.member!.locationSharing, LocationSharingMode.never);
    });

    test('other errors never trigger a session refresh', () async {
      h = await SettingsHarness.create(
        handlers: {'PATCH /me': (_) => throw const ApiException.network()},
      );
      final before = h.session.member!;
      await errorOf(
        actions().saveProfile(before, before.copyWith(name: 'New name')),
      );
      await settle();
      expect(h.api.callsTo('GET /auth/me'), isEmpty);
    });

    test('leaving when already out of the family counts as done', () async {
      h = await SettingsHarness.create(
        handlers: {
          'POST /me/leave-family': (_) => throw noFamilyError,
          'GET /auth/me': (_) => authMe(withFamily: false),
        },
      );
      await actions().leaveFamily();
      expect(h.session.needsFamily, isTrue);
    });

    test('NO_FAMILY on leave with a failing refresh is reported', () async {
      h = await SettingsHarness.create(
        handlers: {
          'POST /me/leave-family': (_) => throw noFamilyError,
          'GET /auth/me': (_) => throw const ApiException.network(),
        },
      );
      final error = await errorOf(actions().leaveFamily());
      expect((error as ApiException).code, ApiErrorCode.noFamily);
      expect(h.session.family, isNotNull);
    });
  });

  group('location fix quality', () {
    GeoFix cachedFix(Duration age, DateTime now) => GeoFix(
      lat: 28.61,
      lng: 77.2,
      at: now.toUtc().subtract(age),
      isLastKnown: true,
    );

    test('an old cached position is never shared as current', () async {
      final location = FakeLocationService();
      h = await SettingsHarness.create(
        session: sessionWith(member: {'locationSharing': 'always'}),
        location: location,
        handlers: {
          'PUT /me/location': (_) => {'recordedAt': '2026-09-26T10:00:00.000Z'},
        },
      );
      location.fix = cachedFix(const Duration(hours: 3), h.clock.now);

      final result = await actions().shareLocationNow();

      expect(result.outcome, LocationSharingOutcome.noFix);
      expect(h.api.callsTo('PUT /me/location'), isEmpty);
      expect(h.container.read(locationUploadClockProvider), isNull);
    });

    test('a recent cached position is shared', () async {
      final location = FakeLocationService();
      h = await SettingsHarness.create(
        session: sessionWith(member: {'locationSharing': 'always'}),
        location: location,
        handlers: {
          'PUT /me/location': (_) => {'recordedAt': '2026-09-26T10:00:00.000Z'},
        },
      );
      location.fix = cachedFix(const Duration(minutes: 3), h.clock.now);

      final result = await actions().shareLocationNow();

      expect(result.outcome, LocationSharingOutcome.shared);
      expect(h.api.callsTo('PUT /me/location'), hasLength(1));
    });

    test('"always" + unexpected upload error: mode kept, noFix', () async {
      h = await SettingsHarness.create(
        location: FakeLocationService(fix: testFix()),
        handlers: {
          'PATCH /me': (call) => meResponse(
            member: {'locationSharing': call.json['locationSharing']},
          ),
          'PUT /me/location': (_) => throw StateError('boom'),
        },
      );
      final result = await actions().setLocationSharing(
        LocationSharingMode.always,
      );
      expect(result.outcome, LocationSharingOutcome.noFix);
      expect(h.session.member!.locationSharing, LocationSharingMode.always);
    });
  });
}
