import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/settings/settings_controller.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/settings/application/settings_actions.dart';
import 'package:family_hub/features/settings/application/settings_providers.dart';
import 'package:family_hub/features/settings/data/system_settings.dart';
import 'package:family_hub/features/settings/domain/app_info.dart';
import 'package:family_hub/features/settings/presentation/settings_labels.dart';
import 'package:family_hub/features/settings/presentation/widgets/profile_header.dart';
import 'package:family_hub/features/settings/presentation/widgets/settings_section.dart';
import 'package:family_hub/features/settings/presentation/widgets/settings_shortcuts.dart';
import 'package:family_hub/shared/l10n/shared_labels.dart';
import 'package:family_hub/shared/session/session_controller.dart';

/// The "More" tab (docs/12 §3 "Settings / More"): a full-bleed brand
/// gradient header behind the transparent status bar with the member's
/// profile, colourful family shortcuts overlapping its bottom edge, then
/// grouped settings rows led by solid icon badges, log out and the version.
class MoreScreen extends ConsumerStatefulWidget {
  const MoreScreen({super.key});

  @override
  ConsumerState<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends ConsumerState<MoreScreen> {
  late final AppLifecycleListener _lifecycle;
  bool _loggingOut = false;

  @override
  void initState() {
    super.initState();
    // Coming back from the phone settings may have changed notifications.
    _lifecycle = AppLifecycleListener(
      onResume: () {
        if (mounted) ref.invalidate(notificationStatusProvider);
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(notificationStatusProvider);
    try {
      await ref.read(sessionControllerProvider.notifier).refreshMe();
    } catch (e) {
      if (mounted) context.showError(e);
    }
  }

  Future<void> _openSystemSettings() async {
    final opened = await ref.read(systemSettingsProvider).openAppSettings();
    if (!opened && mounted) {
      context.showInfo(context.l10n.settingsOpenSettingsFailed);
    }
  }

  Future<void> _logout() async {
    if (_loggingOut) return;
    final l10n = context.l10n;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.settingsLogoutConfirmTitle,
      message: l10n.settingsLogoutConfirmMessage,
      confirmLabel: l10n.settingsLogout,
    );
    if (!confirmed || !mounted) return;
    setState(() => _loggingOut = true);
    try {
      // Never throws; the router then shows the welcome screen.
      await ref.read(settingsActionsProvider).logout();
    } finally {
      if (mounted) setState(() => _loggingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final user = ref.watch(currentUserProvider);
    final member = ref.watch(currentMemberProvider);
    final family = ref.watch(currentFamilyProvider);
    final isAdmin = ref.watch(isAdminProvider);
    final settings = ref.watch(settingsControllerProvider);
    final locale = ref.watch(resolvedLocaleProvider);
    final notifications = ref.watch(notificationStatusProvider);

    final name = member?.name.trim().isNotEmpty == true
        ? member!.name.trim()
        : (user?.name.trim() ?? '');
    final languageName = languageNativeName(locale.languageCode);
    final notificationStatus = notifications.value;
    final canOpenNotificationSettings =
        notificationStatus?.canOpenSettings == true;
    final hasFamily = family != null;

    return Scaffold(
      // The full-bleed gradient header replaces the app bar; keep a
      // screen-reader title for the tab.
      body: Semantics(
        label: l10n.navMore,
        explicitChildNodes: true,
        child: GradientHeaderScrollView(
          gradient: AppGradients.brandHeader,
          onRefresh: _refresh,
          // The shortcut tiles overlap the header's rounded edge; without
          // a family the first thing below is a section title, which must
          // not sit on the gradient.
          overlap: hasFamily ? AppSpacing.xxl : 0,
          header: ProfileHeader(
            name: name,
            member: member,
            family: family,
            email: user?.email,
            onTap: member == null
                ? null
                : () => context.push(AppRoutes.settingsProfile),
          ),
          children: [
            if (hasFamily) const SettingsShortcuts() else AppGap.sm,
            if (family != null && isAdmin) ...[
              AppGap.xl,
              SettingsSection(
                title: l10n.settingsSectionFamily,
                icon: AppIcons.family,
                accent: AppAccents.family,
                children: [
                  SettingsTile(
                    icon: AppIcons.family,
                    accent: AppAccents.family,
                    title: l10n.settingsFamilySettings,
                    onTap: () => context.push(AppRoutes.familySettings),
                  ),
                ],
              ),
            ],
            AppGap.xl,
            SettingsSection(
              title: l10n.settingsSectionPreferences,
              icon: AppIcons.settings,
              accent: AppAccents.settings,
              children: [
                SettingsTile(
                  icon: AppIcons.language,
                  accent: AppAccent.sky,
                  title: l10n.settingsLanguage,
                  value: settings.followsSystemLocale
                      ? l10n.settingsLanguageDeviceCurrent(languageName)
                      : languageName,
                  onTap: () => context.push(AppRoutes.settingsLanguage),
                ),
                SettingsTile(
                  icon: AppIcons.appearance,
                  accent: AppAccent.violet,
                  title: l10n.settingsAppearance,
                  value: settings.themeMode.label(l10n),
                  onTap: () => context.push(AppRoutes.settingsAppearance),
                ),
                if (member != null)
                  SettingsTile(
                    icon: member.locationSharing.icon,
                    accent: AppAccent.teal,
                    title: l10n.settingsLocationSharing,
                    value: member.locationSharing.label(l10n),
                    onTap: () => context.push(AppRoutes.settingsLocation),
                  ),
                SettingsTile(
                  icon: AppIcons.notifications,
                  accent: AppAccent.amber,
                  title: l10n.settingsNotifications,
                  // Sentences (e.g. "Off. Turn them on…") read better
                  // below the title than squeezed at the end.
                  subtitle:
                      notificationStatus?.label(l10n) ??
                      (notifications.isLoading
                          ? l10n.commonLoading
                          : l10n.commonUnknown),
                  busy: notifications.isLoading && notificationStatus == null,
                  trailing: canOpenNotificationSettings
                      ? Icon(
                          AppIcons.openExternal,
                          semanticLabel: l10n.settingsNotificationsOpenSettings,
                        )
                      : null,
                  onTap: canOpenNotificationSettings
                      ? _openSystemSettings
                      : null,
                ),
              ],
            ),
            AppGap.xl,
            SettingsSection(
              title: l10n.settingsSectionAccount,
              icon: AppIcons.profile,
              accent: AppAccents.brand,
              children: [
                SettingsTile(
                  icon: AppIcons.password,
                  accent: AppAccent.indigo,
                  title: l10n.settingsChangePassword,
                  onTap: () => context.push(AppRoutes.settingsPassword),
                ),
                SettingsTile(
                  icon: AppIcons.privacy,
                  accent: AppAccent.emerald,
                  title: l10n.settingsPrivacy,
                  onTap: () => context.push(AppRoutes.settingsPrivacy),
                ),
                SettingsTile(
                  icon: AppIcons.about,
                  accent: AppAccent.blue,
                  title: l10n.settingsAbout,
                  onTap: () => context.push(AppRoutes.settingsAbout),
                ),
              ],
            ),
            AppGap.lg,
            SettingsSection(
              tint: AppAccents.sos,
              children: [
                SettingsTile(
                  icon: AppIcons.logout,
                  title: l10n.settingsLogout,
                  destructive: true,
                  showChevron: false,
                  busy: _loggingOut,
                  onTap: _logout,
                ),
              ],
            ),
            AppGap.xl,
            Text(
              l10n.settingsVersion(AppInfo.displayVersion),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
