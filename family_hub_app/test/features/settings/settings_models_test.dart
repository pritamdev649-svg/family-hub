import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/services/location_service.dart';
import 'package:family_hub/features/settings/application/location_upload_clock.dart';
import 'package:family_hub/features/settings/data/system_settings.dart';
import 'package:family_hub/features/settings/domain/app_info.dart';
import 'package:family_hub/features/settings/domain/data_export.dart';
import 'package:family_hub/features/settings/domain/notification_status.dart';
import 'package:family_hub/features/settings/presentation/settings_labels.dart';

import 'settings_test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DataExport.fromJson', () {
    test('summarises the known sections in contract order', () {
      final export = DataExport.fromJson({
        'sosAlerts': [
          {'id': 's1'},
        ],
        'user': {'id': 'u1', 'email': 'a@b.c'},
        'member': {'id': 'm1'},
        'tasks': [
          {'id': 't1'},
          {'id': 't2'},
        ],
        'ledgerEntries': <Object?>[],
        'notices': [
          {'id': 'n1'},
        ],
        'emergencyCard': null,
        'exportedAt': '2026-09-26T10:15:00.000Z',
      });

      expect(export.sections.map((s) => s.section), [
        DataExportSection.user,
        DataExportSection.member,
        DataExportSection.tasks,
        DataExportSection.ledgerEntries,
        DataExportSection.notices,
        DataExportSection.emergencyCard,
        DataExportSection.sosAlerts,
      ]);
      DataExportSectionSummary of(DataExportSection s) =>
          export.sections.firstWhere((e) => e.section == s);
      expect(of(DataExportSection.tasks).count, 2);
      expect(of(DataExportSection.tasks).isList, isTrue);
      expect(of(DataExportSection.ledgerEntries).isEmpty, isTrue);
      expect(of(DataExportSection.user).isList, isFalse);
      expect(of(DataExportSection.user).count, 1);
      expect(of(DataExportSection.emergencyCard).count, 0);
      expect(export.exportedAt, DateTime.utc(2026, 9, 26, 10, 15));
      expect(export.isEmpty, isFalse);
    });

    test('missing sections are skipped, unknown ones kept in the JSON', () {
      final received = DateTime.utc(2026, 9, 27);
      final export = DataExport.fromJson({
        'user': {'id': 'u1'},
        'formatVersion': 1,
        'futureSection': [
          {'x': 1},
        ],
      }, receivedAt: received);

      expect(export.sections.map((s) => s.section), [DataExportSection.user]);
      expect(export.exportedAt, received, reason: 'falls back to receipt time');
      expect(export.data['futureSection'], isNotNull);
      expect(export.prettyJson, contains('"futureSection"'));
    });

    test('backend extras: family, devices and sessions are summarised', () {
      final export = DataExport.fromJson({
        'user': {'id': 'u1'},
        'family': {'id': 'f1', 'name': 'Sharma Family'},
        'currency': 'INR',
        'devices': [
          {'platform': 'android', 'tokenSuffix': 'abc123'},
        ],
        'sessions': [
          {'active': true},
          {'active': false},
        ],
      });
      expect(export.sections.map((s) => (s.section, s.count)), [
        (DataExportSection.user, 1),
        (DataExportSection.family, 1),
        (DataExportSection.devices, 1),
        (DataExportSection.sessions, 2),
      ]);
    });

    test('prettyJsonLines splits the JSON for lazy rendering', () {
      final export = DataExport.fromJson({
        'tasks': [
          for (var i = 0; i < 500; i++) {'id': 't$i', 'title': 'Line\nbreak'},
        ],
      });
      final lines = export.prettyJsonLines;
      expect(lines.join('\n'), export.prettyJson);
      // Escaped newlines inside values never split a line.
      expect(lines.where((l) => l.contains(r'Line\nbreak')), hasLength(500));
      expect(() => lines.add('x'), throwsUnsupportedError);
    });

    test('prettyJson is valid, 2-space indented JSON of the whole export', () {
      final source = {
        'user': {'id': 'u1', 'name': 'अमित'},
        'tasks': [
          {'id': 't1'},
        ],
      };
      final export = DataExport.fromJson(source);
      expect(jsonDecode(export.prettyJson), source);
      expect(export.prettyJson, contains('\n  "user": {\n    "id": "u1"'));
    });

    test('empty export', () {
      final export = DataExport.fromJson(const {});
      expect(export.isEmpty, isTrue);
      expect(export.sections, isEmpty);
      expect(export.exportedAt, isNull);
    });

    test('data is unmodifiable', () {
      final export = DataExport.fromJson({'user': <String, dynamic>{}});
      expect(() => export.data['x'] = 1, throwsUnsupportedError);
    });
  });

  group('labels', () {
    late final l10nFuture = englishL10n();

    test('count labels for list and single-record sections', () async {
      final l10n = await l10nFuture;
      const list = DataExportSectionSummary(
        section: DataExportSection.tasks,
        isList: true,
        count: 3,
      );
      const record = DataExportSectionSummary(
        section: DataExportSection.member,
        isList: false,
        count: 1,
      );
      const none = DataExportSectionSummary(
        section: DataExportSection.emergencyCard,
        isList: false,
        count: 0,
      );
      expect(list.countLabel(l10n), '3 items');
      expect(record.countLabel(l10n), l10n.settingsExportIncluded);
      expect(none.countLabel(l10n), 'None');
    });

    test('every enum value has a label', () async {
      final l10n = await l10nFuture;
      for (final mode in ThemeMode.values) {
        expect(mode.label(l10n), isNotEmpty);
      }
      for (final status in NotificationStatus.values) {
        expect(status.label(l10n), isNotEmpty);
      }
      for (final section in DataExportSection.values) {
        expect(section.label(l10n), isNotEmpty);
      }
      expect(
        LocationPermissionState.deniedForever.message(l10n),
        l10n.servicesLocationDeniedForever,
      );
      expect(
        LocationPermissionState.serviceDisabled.message(l10n),
        l10n.servicesLocationServiceDisabled,
      );
    });

    test('languageNativeName', () {
      expect(languageNativeName('hi'), 'हिन्दी');
      expect(languageNativeName('ar'), 'العربية');
      expect(languageNativeName('xx'), 'xx');
    });
  });

  group('AppInfo', () {
    test('formatVersion', () {
      expect(AppInfo.formatVersion('1.2.0', '7'), '1.2.0 (7)');
      expect(AppInfo.formatVersion('1.2.0', ''), '1.2.0');
      expect(AppInfo.formatVersion(' 1.2.0 ', ' '), '1.2.0');
      expect(AppInfo.formatVersion('', '7'), '7');
    });

    test('defaults mirror the pubspec version', () {
      expect(AppInfo.displayVersion, '1.0.0 (1)');
    });
  });

  group('NotificationStatus', () {
    test('maps every FCM authorization status', () {
      expect(
        DeviceSystemSettings.mapAuthorizationStatus(
          AuthorizationStatus.authorized,
        ),
        NotificationStatus.enabled,
      );
      expect(
        DeviceSystemSettings.mapAuthorizationStatus(
          AuthorizationStatus.provisional,
        ),
        NotificationStatus.enabled,
      );
      expect(
        DeviceSystemSettings.mapAuthorizationStatus(AuthorizationStatus.denied),
        NotificationStatus.disabled,
      );
      expect(
        DeviceSystemSettings.mapAuthorizationStatus(
          AuthorizationStatus.notDetermined,
        ),
        NotificationStatus.notDetermined,
      );
      expect(NotificationStatus.unavailable.canOpenSettings, isFalse);
      expect(NotificationStatus.disabled.canOpenSettings, isTrue);
    });

    test(
      'push not configured → unavailable without touching Firebase',
      () async {
        final status = await DeviceSystemSettings(
          FakePushService(),
        ).notificationStatus();
        expect(status, NotificationStatus.unavailable);
      },
    );
  });

  group('LocationUploadClock', () {
    test('is due without uploads, then throttles by interval', () async {
      final h = await SettingsHarness.create();
      addTearDown(h.dispose);
      final clock = h.container.read(locationUploadClockProvider.notifier);
      const interval = Duration(minutes: 10);

      expect(clock.isDue(interval), isTrue);
      clock.record();
      expect(h.container.read(locationUploadClockProvider), h.clock.now);
      h.clock.advance(const Duration(minutes: 9));
      expect(clock.isDue(interval), isFalse);
      h.clock.advance(const Duration(minutes: 1));
      expect(clock.isDue(interval), isTrue);

      // A clock that jumps backwards never blocks uploads forever.
      clock.record();
      h.clock.advance(const Duration(hours: -1));
      expect(clock.isDue(interval), isTrue);
    });

    test('isShareableFix: fresh fixes always, cached ones only if recent', () {
      final now = DateTime.utc(2026, 9, 26, 12);
      GeoFix fix(Duration age, {bool lastKnown = true}) =>
          GeoFix(lat: 1, lng: 2, at: now.subtract(age), isLastKnown: lastKnown);

      expect(
        isShareableFix(fix(const Duration(hours: 5), lastKnown: false), now),
        isTrue,
      );
      expect(isShareableFix(fix(maxLastKnownFixAge), now), isTrue);
      expect(
        isShareableFix(
          fix(maxLastKnownFixAge + const Duration(seconds: 1)),
          now,
        ),
        isFalse,
        reason: 'an old cached position is not "where I am now"',
      );
      expect(isShareableFix(fix(const Duration(minutes: -2)), now), isTrue);
      expect(isShareableFix(fix(const Duration(hours: -3)), now), isFalse);
      // Local-time "now" compares correctly with a UTC fix time.
      expect(
        isShareableFix(fix(const Duration(minutes: 1)), now.toLocal()),
        isTrue,
      );
    });
  });
}
