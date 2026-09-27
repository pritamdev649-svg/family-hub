import 'package:flutter/material.dart';

import 'package:family_hub/core/config/app_languages.dart';
import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/services/location_service.dart';
import 'package:family_hub/features/settings/domain/data_export.dart';
import 'package:family_hub/features/settings/domain/notification_status.dart';
import 'package:family_hub/l10n/app_localizations.dart';

// Localised labels for the settings feature's enums (docs/05 §6).

extension ThemeModeLabels on ThemeMode {
  String label(AppLocalizations l10n) => switch (this) {
    ThemeMode.system => l10n.settingsThemeSystem,
    ThemeMode.light => l10n.settingsThemeLight,
    ThemeMode.dark => l10n.settingsThemeDark,
  };

  IconData get icon => switch (this) {
    ThemeMode.system => AppIcons.appearance,
    ThemeMode.light => AppIcons.lightMode,
    ThemeMode.dark => AppIcons.darkMode,
  };
}

extension NotificationStatusLabels on NotificationStatus {
  String label(AppLocalizations l10n) => switch (this) {
    NotificationStatus.enabled => l10n.settingsNotificationsEnabled,
    NotificationStatus.disabled => l10n.settingsNotificationsDisabled,
    NotificationStatus.notDetermined => l10n.settingsNotificationsNotAsked,
    NotificationStatus.unavailable => l10n.settingsNotificationsUnavailable,
  };
}

extension DataExportSectionLabels on DataExportSection {
  String label(AppLocalizations l10n) => switch (this) {
    DataExportSection.user => l10n.settingsExportSectionUser,
    DataExportSection.member => l10n.settingsExportSectionMember,
    DataExportSection.family => l10n.settingsExportSectionFamily,
    DataExportSection.tasks => l10n.settingsExportSectionTasks,
    DataExportSection.ledgerEntries => l10n.settingsExportSectionLedger,
    DataExportSection.notices => l10n.settingsExportSectionNotices,
    DataExportSection.emergencyCard => l10n.settingsExportSectionEmergencyCard,
    DataExportSection.sosAlerts => l10n.settingsExportSectionSos,
    DataExportSection.devices => l10n.settingsExportSectionDevices,
    DataExportSection.sessions => l10n.settingsExportSectionSessions,
  };

  IconData get icon => switch (this) {
    DataExportSection.user => AppIcons.security,
    DataExportSection.member => AppIcons.profile,
    DataExportSection.family => AppIcons.family,
    DataExportSection.tasks => AppIcons.task,
    DataExportSection.ledgerEntries => AppIcons.ledger,
    DataExportSection.notices => AppIcons.notice,
    DataExportSection.emergencyCard => AppIcons.emergencyCard,
    DataExportSection.sosAlerts => AppIcons.sosAlert,
    DataExportSection.devices => AppIcons.notifications,
    DataExportSection.sessions => AppIcons.password,
  };

  /// Colour of the section's icon badge (the owning module's accent).
  AppAccent get accent => switch (this) {
    DataExportSection.user => AppAccents.settings,
    DataExportSection.member => AppAccents.family,
    DataExportSection.family => AppAccents.family,
    DataExportSection.tasks => AppAccents.tasks,
    DataExportSection.ledgerEntries => AppAccents.money,
    DataExportSection.notices => AppAccents.notices,
    DataExportSection.emergencyCard => AppAccents.emergency,
    DataExportSection.sosAlerts => AppAccents.sos,
    DataExportSection.devices => AppAccent.amber,
    DataExportSection.sessions => AppAccent.indigo,
  };
}

extension DataExportSectionSummaryLabels on DataExportSectionSummary {
  /// "3 items" / "None" for lists, "Included" / "None" for single records.
  String countLabel(AppLocalizations l10n) {
    if (isList) return l10n.settingsExportItemCount(count);
    return isEmpty
        ? l10n.settingsExportItemCount(0)
        : l10n.settingsExportIncluded;
  }
}

extension LocationPermissionStateLabels on LocationPermissionState {
  /// Why location cannot be shared (reuses the location service strings).
  String message(AppLocalizations l10n) => switch (this) {
    LocationPermissionState.granted ||
    LocationPermissionState.denied => l10n.servicesLocationDenied,
    LocationPermissionState.deniedForever => l10n.servicesLocationDeniedForever,
    LocationPermissionState.serviceDisabled =>
      l10n.servicesLocationServiceDisabled,
  };
}

/// Native name of the language with [code] (`हिन्दी`), or the code itself.
String languageNativeName(String code) =>
    AppLanguages.byCode(code)?.nativeName ?? code;
