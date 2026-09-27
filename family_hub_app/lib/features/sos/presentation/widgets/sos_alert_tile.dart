import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/utils/formatters.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/sos/domain/sos_alert.dart';
import 'package:family_hub/features/sos/presentation/sos_labels.dart';
import 'package:family_hub/features/sos/presentation/sos_navigation.dart';
import 'package:family_hub/features/sos/presentation/widgets/sos_ticker.dart';

/// One SOS alert in a list (public API, docs/05-FLUTTER_GUIDE.md §10): used
/// by the SOS tab, the SOS history and the dashboard.
///
/// Active alerts are highlighted in the SOS colours ("Priya needs help",
/// started time, whether a live location is shared); ended alerts show the
/// outcome and when they ended. Tapping opens `/sos/alert/:id` unless
/// [onTap] is given.
class SosAlertTile extends ConsumerWidget {
  const SosAlertTile(this.alert, {super.key, this.onTap});

  final SosAlert alert;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final sos = context.semanticColors;
    final fmt = ref.watch(fmtProvider);
    final name = alert.displayName(l10n);

    // Relative times and the active highlight stay fresh while the tile is
    // on screen (an alert that expires turns into an ended one).
    return SosTicker(
      interval: AppDurations.pollActiveSos,
      enabled: alert.status == SosStatus.active,
      builder: (context, now) {
        final status = alert.effectiveStatusAt(now);
        final active = status == SosStatus.active;
        final endedAt = alert.endedAtAsOf(now);
        final titleColor = active ? sos.onSosContainer : null;
        final subtitleColor = active
            ? sos.onSosContainer
            : theme.colorScheme.onSurfaceVariant;
        final subtitleStyle = theme.textTheme.bodySmall?.copyWith(
          color: subtitleColor,
        );

        return AppCard(
          color: active ? sos.sosContainer : null,
          onTap: onTap ?? () => openSosAlert(context, alert.id),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MemberAvatar(
                name: alert.memberName,
                avatarUrl: alert.memberAvatarUrl,
              ),
              AppGap.hMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      active ? l10n.sosNeedsHelp(name) : name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: titleColor,
                      ),
                    ),
                    AppGap.xs,
                    StatusChip(
                      label: alert.statusLabel(l10n, now),
                      icon: alert.statusIcon(now),
                      color: status.color(context),
                    ),
                    AppGap.xs,
                    Text(
                      l10n.sosStarted(
                        fmt.relative(alert.startedAt, l10n, now: now),
                      ),
                      style: subtitleStyle,
                    ),
                    if (endedAt != null)
                      Text(
                        l10n.sosEnded(fmt.dateTime(endedAt)),
                        style: subtitleStyle,
                      )
                    else
                      Text(
                        alert.locationShared
                            ? l10n.sosLiveLocation
                            : l10n.sosNoLocation,
                        style: subtitleStyle,
                      ),
                  ],
                ),
              ),
              AppGap.hSm,
              Icon(AppIcons.chevron, color: subtitleColor),
            ],
          ),
        );
      },
    );
  }
}
