import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/error_messages.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/network/api_exception.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/utils/formatters.dart';
import 'package:family_hub/core/utils/url_actions.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/emergency_card/application/emergency_card_providers.dart';
import 'package:family_hub/features/emergency_card/presentation/widgets/emergency_card_view.dart';
import 'package:family_hub/features/sos/application/sos_controller.dart';
import 'package:family_hub/features/sos/application/sos_providers.dart';
import 'package:family_hub/features/sos/presentation/sos_feedback.dart';
import 'package:family_hub/features/sos/presentation/sos_labels.dart';
import 'package:family_hub/features/sos/presentation/widgets/sos_active_panel.dart';
import 'package:family_hub/features/sos/presentation/widgets/sos_emergency_call_button.dart';
import 'package:family_hub/features/sos/presentation/widgets/sos_pulsing_dot.dart';
import 'package:family_hub/features/sos/presentation/widgets/sos_ticker.dart';
import 'package:family_hub/shared/providers/shared_providers.dart';

/// `/sos/alert/:id` — one alert, also opened from the `sos` push.
///
/// Polls `GET /sos/:id` every 5 s while visible and active
/// ([sosAlertProvider]): who needs help, since when, time left, the last
/// location with its accuracy and age, recent points, "Open in Maps",
/// calling the member and the emergency number, resolving (owner: "I am
/// okay" / "False alarm"; admins: "Mark as helped") and the member's
/// emergency card. A missing alert (`404`, malformed link) shows a
/// "not available" state.
class SosAlertScreen extends ConsumerWidget {
  const SosAlertScreen({super.key, required this.alertId});

  final String alertId;

  static bool _isGone(Object? error) {
    if (error == null) return false;
    final e = unwrapProviderError(error);
    return e is ApiException &&
        (e.isNotFound || e.code == ApiErrorCode.badRequest);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final provider = sosAlertProvider(alertId);
    final async = ref.watch(provider);
    final gone = !async.isLoading && _isGone(async.error);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.sosAlertTitle)),
      body: SafeArea(
        top: false,
        child: ResponsiveCenter(
          child: gone
              ? EmptyState(
                  icon: AppIcons.sosAlert,
                  title: l10n.sosAlertGoneTitle,
                  message: l10n.sosAlertGoneMessage,
                  action: AppButton(
                    label: l10n.sosBackToSos,
                    icon: AppIcons.sos,
                    expand: false,
                    onPressed: () => context.go(AppRoutes.sos),
                  ),
                )
              : AsyncValueView<SosAlert>(
                  value: async,
                  onRetry: () => ref.invalidate(provider),
                  data: (alert) => AppRefreshIndicator(
                    onRefresh: () => ref.refresh(provider.future),
                    child: _AlertBody(alert: alert),
                  ),
                ),
        ),
      ),
    );
  }
}

class _AlertBody extends ConsumerWidget {
  const _AlertBody({required this.alert});

  final SosAlert alert;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final me = ref.watch(currentMemberProvider);
    final isAdmin = ref.watch(isAdminProvider);
    final isOwn = alert.isOwnedBy(me?.id);
    final phone = alert.memberPhone;
    final name = alert.displayName(l10n);

    void applyResolved(SosAlert resolved) =>
        ref.read(sosAlertProvider(alert.id).notifier).apply(resolved);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: AppSpacing.screen,
      children: [
        _HeaderCard(alert: alert, isOwn: isOwn),
        if (alert.message != null) ...[
          AppGap.md,
          _MessageCard(message: alert.message!),
        ],
        AppGap.md,
        _LocationCard(alert: alert),
        if (alert.trail.length > 1) ...[AppGap.md, _TrailCard(alert: alert)],
        AppGap.lg,
        if (!isOwn && phone != null) ...[
          AppButton(
            label: l10n.sosCallMember(name),
            icon: AppIcons.phone,
            onPressed: () => sosDial(context, phone),
          ),
          AppGap.sm,
        ],
        const SosEmergencyCallButton(),
        if (alert.status == SosStatus.active && (isOwn || isAdmin))
          // Hidden the moment the live window ends, like the header's
          // status (the next poll confirms it).
          SosTicker(
            builder: (context, now) {
              if (!alert.isActiveAt(now)) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsetsDirectional.only(top: AppSpacing.lg),
                child: isOwn
                    ? SosOwnResolveButtons(
                        alertId: alert.id,
                        onResolved: applyResolved,
                      )
                    : _MarkHelpedButton(
                        alert: alert,
                        onResolved: applyResolved,
                      ),
              );
            },
          ),
        if (alert.memberName != null) ...[
          AppGap.lg,
          SectionHeader(title: l10n.sosEmergencyCardTitle),
          _EmergencyCardSection(memberId: alert.memberId),
        ],
      ],
    );
  }
}

class _HeaderCard extends ConsumerWidget {
  const _HeaderCard({required this.alert, required this.isOwn});

  final SosAlert alert;
  final bool isOwn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final sos = context.semanticColors;
    final fmt = ref.watch(fmtProvider);
    final name = alert.displayName(l10n);
    final members = ref.watch(membersProvider).value;
    String? resolverName;
    for (final m in members ?? const []) {
      if (m.id == alert.resolvedById) resolverName = m.name;
    }

    return SosTicker(
      builder: (context, now) {
        final status = alert.effectiveStatusAt(now);
        final active = status == SosStatus.active;
        final foreground = active ? sos.onSosContainer : null;
        final secondary = active
            ? sos.onSosContainer
            : theme.colorScheme.onSurfaceVariant;
        final endedAt = alert.endedAtAsOf(now);
        final resolution = alert.resolution;

        return AppCard(
          color: active ? sos.sosContainer : null,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MemberAvatar(
                name: alert.memberName,
                avatarUrl: alert.memberAvatarUrl,
                radius: AppSizes.avatarLg,
              ),
              AppGap.hLg,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      liveRegion: true,
                      child: Text(
                        isOwn
                            ? l10n.sosYourAlert
                            : active
                            ? l10n.sosNeedsHelp(name)
                            : name,
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: foreground,
                        ),
                      ),
                    ),
                    AppGap.xs,
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (active) SosPulsingDot(color: sos.sos),
                        StatusChip(
                          label: alert.statusLabel(l10n, now),
                          icon: alert.statusIcon(now),
                          color: status.color(context),
                        ),
                      ],
                    ),
                    AppGap.sm,
                    Text(
                      l10n.sosStarted(fmt.dateTime(alert.startedAt)),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: secondary,
                      ),
                    ),
                    if (active)
                      Text(
                        l10n.sosTimeRemaining(
                          sosFormatRemaining(alert.remainingAt(now)),
                        ),
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: foreground,
                        ),
                      )
                    else if (endedAt != null)
                      Text(
                        l10n.sosEnded(fmt.dateTime(endedAt)),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: secondary,
                        ),
                      ),
                    if (!active && resolution != null && resolverName != null)
                      Text(
                        l10n.sosResolvedBy(
                          resolution.label(l10n),
                          resolverName,
                        ),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: secondary,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.l10n.sosMessageLabel, style: theme.textTheme.labelLarge),
          AppGap.xs,
          Text(message, style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}

class _LocationCard extends ConsumerWidget {
  const _LocationCard({required this.alert});

  final SosAlert alert;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fmt = ref.watch(fmtProvider);
    final point = alert.lastLocation;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    final Widget content;
    if (!alert.locationShared) {
      content = _IconLine(
        icon: AppIcons.locationOff,
        text: l10n.sosNoLocationShared(alert.displayName(l10n)),
      );
    } else if (point == null) {
      content = _IconLine(
        icon: AppIcons.myLocation,
        text: l10n.sosWaitingForMemberLocation,
      );
    } else {
      final accuracy = point.accuracy;
      final recordedAt = point.recordedAt;
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.sosCoordinates(
              sosFormatCoordinate(point.lat),
              sosFormatCoordinate(point.lng),
            ),
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.start,
            style: theme.textTheme.titleMedium?.merge(
              AppTypography.tabularFigures,
            ),
          ),
          if (accuracy != null) ...[
            AppGap.xxs,
            Text(
              l10n.sosAccuracy(sosFormatMeters(accuracy, fmt)),
              style: muted,
            ),
          ],
          if (recordedAt != null)
            SosTicker(
              builder: (context, now) => Text(
                l10n.sosUpdated(sosAgo(recordedAt, now, fmt, l10n)),
                style: muted,
              ),
            ),
          AppGap.md,
          AppButton(
            label: l10n.sosOpenInMaps,
            icon: AppIcons.map,
            variant: AppButtonVariant.secondary,
            onPressed: () => _openMap(context, point.lat, point.lng),
          ),
        ],
      );
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(AppIcons.location, color: scheme.primary),
              AppGap.hSm,
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    l10n.sosLastLocationTitle,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ),
            ],
          ),
          AppGap.md,
          content,
        ],
      ),
    );
  }
}

Future<void> _openMap(BuildContext context, double lat, double lng) async {
  final opened = await UrlActions.openMap(lat, lng);
  if (!opened && context.mounted) {
    context.showInfo(context.l10n.sosMapsFailed);
  }
}

/// The newest few trail points (newest first); each opens the map.
class _TrailCard extends ConsumerWidget {
  const _TrailCard({required this.alert});

  final SosAlert alert;

  /// How many recent points are listed.
  static const int maxShown = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final fmt = ref.watch(fmtProvider);
    final points = alert.trail.reversed.take(maxShown).toList();

    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: SectionHeader(title: l10n.sosTrailTitle),
          ),
          for (final p in points)
            ListTile(
              leading: const Icon(AppIcons.location),
              title: Text(
                p.recordedAt == null
                    ? l10n.sosCoordinates(
                        sosFormatCoordinate(p.lat),
                        sosFormatCoordinate(p.lng),
                      )
                    : fmt.time(p.recordedAt!),
              ),
              subtitle: p.accuracy == null
                  ? null
                  : Text(l10n.sosAccuracy(sosFormatMeters(p.accuracy!, fmt))),
              trailing: Icon(
                AppIcons.openExternal,
                semanticLabel: l10n.sosOpenInMaps,
              ),
              onTap: () => _openMap(context, p.lat, p.lng),
            ),
        ],
      ),
    );
  }
}

class _IconLine extends StatelessWidget {
  const _IconLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
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
    );
  }
}

/// Admin action on someone else's active alert: confirm, then resolve as
/// "helped".
class _MarkHelpedButton extends ConsumerWidget {
  const _MarkHelpedButton({required this.alert, required this.onResolved});

  final SosAlert alert;
  final ValueChanged<SosAlert> onResolved;

  Future<void> _markHelped(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final name = alert.displayName(l10n);
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.sosMarkHelpedConfirmTitle,
      message: l10n.sosMarkHelpedConfirmMessage(name),
      confirmLabel: l10n.sosMarkHelped,
    );
    if (!confirmed || !context.mounted) return;
    try {
      final resolved = await ref
          .read(sosAlertActionsProvider.notifier)
          .resolve(alert.id, SosResolution.helped);
      if (resolved == null || !context.mounted) return;
      showSosResolved(context, SosResolution.helped, result: resolved);
      onResolved(resolved);
    } catch (e) {
      if (context.mounted) context.showError(e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolving = ref.watch(sosResolvingProvider(alert.id));
    return AppButton(
      label: context.l10n.sosMarkHelped,
      icon: AppIcons.helped,
      isLoading: resolving != null,
      onPressed: resolving != null ? null : () => _markHelped(context, ref),
    );
  }
}

/// The alert owner's emergency card (blood group, allergies, contacts …).
class _EmergencyCardSection extends ConsumerWidget {
  const _EmergencyCardSection({required this.memberId});

  final String memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = emergencyCardProvider(memberId);
    final member = ref.watch(memberByIdProvider(memberId)).value;
    return AsyncValueView<EmergencyCard>(
      value: ref.watch(provider),
      onRetry: () => ref.invalidate(provider),
      data: (card) => EmergencyCardView(card: card, member: member),
    );
  }
}
