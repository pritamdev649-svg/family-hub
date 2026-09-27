import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/config/app_config.dart';
import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/settings/domain/app_info.dart';
import 'package:family_hub/features/settings/presentation/settings_navigation.dart';
import 'package:family_hub/features/settings/presentation/widgets/settings_page.dart';
import 'package:family_hub/features/settings/presentation/widgets/settings_section.dart';
import 'package:family_hub/shared/session/session_controller.dart';

/// App name, version and mission on a brand gradient headline, the product
/// disclaimers (SOS alerts the family only, not medical advice, ledger-only
/// money) and the legal / contact links.
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final emergencyNumber = ref.watch(currentCountryProvider).emergencyNumber;

    return SettingsPage(
      title: l10n.settingsAbout,
      child: SettingsListView(
        children: [
          const _AboutHero(),
          AppGap.xl,
          SectionHeader(
            title: l10n.settingsAboutGoodToKnow,
            icon: AppIcons.info,
            accent: AppAccents.settings,
          ),
          _Disclaimer(
            icon: AppIcons.sosAlert,
            accent: AppAccents.sos,
            title: l10n.settingsAboutSosTitle,
            body: l10n.settingsAboutSosDisclaimer(emergencyNumber),
            action: emergencyNumber.trim().isEmpty
                ? null
                : AppButton(
                    label: l10n.settingsAboutCallEmergency(emergencyNumber),
                    icon: AppIcons.phone,
                    variant: AppButtonVariant.danger,
                    expand: false,
                    onPressed: () => callFromSettings(context, emergencyNumber),
                  ),
          ),
          AppGap.sm,
          _Disclaimer(
            icon: AppIcons.emergencyCard,
            accent: AppAccents.emergency,
            title: l10n.settingsAboutMedicalTitle,
            body: l10n.settingsAboutMedicalDisclaimer,
          ),
          AppGap.sm,
          _Disclaimer(
            icon: AppIcons.ledger,
            accent: AppAccents.money,
            title: l10n.settingsAboutLedgerTitle,
            body: l10n.settingsAboutLedgerNote,
          ),
          AppGap.xl,
          SettingsSection(
            title: l10n.settingsAboutLegal,
            icon: AppIcons.notes,
            accent: AppAccents.family,
            children: [
              SettingsTile(
                icon: AppIcons.privacy,
                accent: AppAccent.emerald,
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
              SettingsTile(
                icon: AppIcons.email,
                accent: AppAccent.sky,
                title: l10n.settingsAboutPrivacyContact,
                subtitle: AppInfo.privacyContactEmail,
                onTap: () =>
                    openSettingsEmail(context, AppInfo.privacyContactEmail),
              ),
              SettingsTile(
                icon: AppIcons.about,
                accent: AppAccent.indigo,
                title: l10n.settingsAboutLicenses,
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: l10n.appName,
                  applicationVersion: AppInfo.displayVersion,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Brand gradient headline: app mark, name, version and the mission line.
class _AboutHero extends StatelessWidget {
  const _AboutHero();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final onGradient = Colors.white.withValues(alpha: 0.85);

    return GradientCard(
      gradient: AppGradients.brand,
      glowColor: AppAccents.brand.base,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ExcludeSemantics(
                child: Container(
                  width: AppSizes.badgeLg,
                  height: AppSizes.badgeLg,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: AppRadius.brLg,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    AppIcons.family,
                    size: AppSizes.iconLg,
                    color: Colors.white,
                  ),
                ),
              ),
              AppGap.hLg,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        l10n.appName,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ),
                    AppGap.xxs,
                    Text(
                      l10n.settingsVersion(AppInfo.displayVersion),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: onGradient,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          AppGap.lg,
          Text(
            l10n.settingsAboutMission,
            style: theme.textTheme.bodyMedium?.copyWith(color: onGradient),
          ),
        ],
      ),
    );
  }
}

/// A product disclaimer card: solid icon badge in [accent], title, body and
/// an optional action.
class _Disclaimer extends StatelessWidget {
  const _Disclaimer({
    required this.icon,
    required this.accent,
    required this.title,
    required this.body,
    this.action,
  });

  final IconData icon;
  final AppAccent accent;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(icon: icon, accent: accent, size: AppSizes.badgeSm),
          AppGap.hMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(title, style: theme.textTheme.titleSmall),
                ),
                AppGap.xs,
                Text(
                  body,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (action != null) ...[AppGap.md, action!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
