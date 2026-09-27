import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/sos/presentation/sos_navigation.dart';
import 'package:family_hub/shared/l10n/shared_labels.dart';
import 'package:family_hub/shared/models/member.dart';
import 'package:family_hub/shared/providers/shared_providers.dart';

/// "Alerts your family only": SOS never contacts emergency services
/// (docs/08-COMPLIANCE.md row 17).
class SosDisclaimerCard extends StatelessWidget {
  const SosDisclaimerCard({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AppCard(
      color: scheme.surfaceContainerHighest,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(AppIcons.info, color: scheme.onSurfaceVariant),
          AppGap.hMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    l10n.sosDisclaimerTitle,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                AppGap.xs,
                Text(
                  l10n.sosDisclaimer,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The member's current location sharing mode; opens the location
/// settings (`/settings/location`).
class SosLocationModeRow extends ConsumerWidget {
  const SosLocationModeRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final mode =
        ref.watch(currentMemberProvider.select((m) => m?.locationSharing)) ??
        LocationSharingMode.never;
    return AppCard(
      padding: EdgeInsets.zero,
      onTap: () => openSosRoute(context, AppRoutes.settingsLocation),
      child: ListTile(
        leading: Icon(mode.icon, color: theme.colorScheme.primary),
        title: Text(l10n.sosLocationModeTitle),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              mode.label(l10n),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: AppTypography.semiBold,
              ),
            ),
            Text(mode.description(l10n)),
          ],
        ),
        trailing: const Icon(AppIcons.chevron),
      ),
    );
  }
}

/// A tappable row inside a card (e.g. "Past alerts").
class SosLinkRow extends StatelessWidget {
  const SosLinkRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(label),
        trailing: const Icon(AppIcons.chevron),
      ),
    );
  }
}

/// A short, non-scrolling note inside a list section (e.g. "No one needs
/// help right now").
class SosSectionNote extends StatelessWidget {
  const SosSectionNote({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Icon(icon, size: AppSizes.iconSm, color: color),
          AppGap.hSm,
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
