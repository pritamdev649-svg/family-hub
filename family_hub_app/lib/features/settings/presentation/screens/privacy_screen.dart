import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/config/app_config.dart';
import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/settings/application/settings_actions.dart';
import 'package:family_hub/features/settings/presentation/screens/data_export_screen.dart';
import 'package:family_hub/features/settings/presentation/settings_navigation.dart';
import 'package:family_hub/features/settings/presentation/widgets/delete_account_dialog.dart';
import 'package:family_hub/features/settings/presentation/widgets/last_admin_dialog.dart';
import 'package:family_hub/features/settings/presentation/widgets/settings_page.dart';
import 'package:family_hub/features/settings/presentation/widgets/settings_section.dart';
import 'package:family_hub/shared/models/family.dart';
import 'package:family_hub/shared/session/session_controller.dart';

/// Privacy & data: consent documents, data export (right of access), leave
/// the family and delete the account (right to erasure). Irreversible
/// actions sit on soft red cards at the end.
class PrivacyScreen extends ConsumerStatefulWidget {
  const PrivacyScreen({super.key});

  /// Accent of this screen (matches its row on the More tab).
  static const AppAccent accent = AppAccent.emerald;

  @override
  ConsumerState<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends ConsumerState<PrivacyScreen> {
  bool _leaving = false;

  Future<void> _leaveFamily(Family family) async {
    if (_leaving) return;
    final l10n = context.l10n;
    // The last member leaving deletes the family (contract §5): say so.
    final onlyMember = family.memberCount == 1;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.settingsLeaveFamilyConfirmTitle(family.name),
      message: onlyMember
          ? l10n.settingsLeaveFamilyOnlyMemberMessage
          : l10n.settingsLeaveFamilyConfirmMessage,
      confirmLabel: l10n.settingsLeaveFamily,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    // Stays mounted when the router moves on to family setup.
    final rootContext = Navigator.of(context, rootNavigator: true).context;
    setState(() => _leaving = true);
    Object? error;
    try {
      await ref.read(settingsActionsProvider).leaveFamily();
      if (rootContext.mounted) {
        rootContext.showSuccess(l10n.settingsLeaveFamilyDone);
      }
    } catch (e) {
      error = e;
    }
    if (!mounted) return;
    setState(() => _leaving = false);
    if (error == null) return;
    if (isLastAdminError(error)) {
      await showLastAdminDialog(context, action: LastAdminAction.leave);
    } else {
      context.showError(error);
    }
  }

  Future<void> _deleteAccount() async {
    if (_leaving) return;
    final outcome = await showDeleteAccountDialog(context);
    if (outcome == DeleteAccountOutcome.lastAdmin && mounted) {
      await showLastAdminDialog(context, action: LastAdminAction.delete);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final family = ref.watch(currentFamilyProvider);
    const accent = PrivacyScreen.accent;

    return SettingsPage(
      title: l10n.settingsPrivacy,
      child: SettingsListView(
        children: [
          AppCard(
            accent: accent,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const IconBadge(
                  icon: AppIcons.privacy,
                  accent: accent,
                  size: AppSizes.badgeSm,
                ),
                AppGap.hMd,
                Expanded(
                  child: Text(
                    l10n.settingsPrivacyConsent,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: context.accent(accent).onContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
          AppGap.md,
          SettingsSection(
            children: [
              SettingsTile(
                icon: AppIcons.privacy,
                accent: accent,
                title: l10n.settingsPrivacyPolicy,
                trailing: const Icon(AppIcons.openExternal),
                onTap: () =>
                    openSettingsLink(context, AppConfig.privacyPolicyUrl),
              ),
              SettingsTile(
                icon: AppIcons.notes,
                accent: AppAccent.blue,
                title: l10n.settingsTerms,
                trailing: const Icon(AppIcons.openExternal),
                onTap: () => openSettingsLink(context, AppConfig.termsUrl),
              ),
            ],
          ),
          AppGap.xl,
          SettingsSection(
            title: l10n.settingsPrivacyYourData,
            icon: AppIcons.export,
            accent: AppAccents.settings,
            children: [
              SettingsTile(
                icon: AppIcons.export,
                accent: AppAccents.settings,
                title: l10n.settingsExportData,
                subtitle: l10n.settingsExportDataDescription,
                onTap: () => DataExportScreen.open(context),
              ),
            ],
          ),
          if (family != null) ...[
            AppGap.xl,
            SettingsSection(
              title: l10n.settingsPrivacyMembership,
              icon: AppIcons.family,
              accent: AppAccents.family,
              tint: AppAccents.sos,
              children: [
                SettingsTile(
                  icon: AppIcons.logout,
                  title: l10n.settingsLeaveFamily,
                  subtitle: l10n.settingsLeaveFamilyDescription(family.name),
                  destructive: true,
                  busy: _leaving,
                  onTap: () => _leaveFamily(family),
                ),
              ],
            ),
          ],
          AppGap.xl,
          SettingsSection(
            title: l10n.settingsSectionAccount,
            icon: AppIcons.profile,
            accent: AppAccents.brand,
            tint: AppAccents.sos,
            children: [
              SettingsTile(
                icon: AppIcons.delete,
                title: l10n.settingsDeleteAccount,
                subtitle: l10n.settingsDeleteAccountDescription,
                destructive: true,
                enabled: !_leaving,
                onTap: _deleteAccount,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
