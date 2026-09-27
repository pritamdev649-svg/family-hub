import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/services/location_service.dart';
import 'package:family_hub/core/services/services_l10n.dart';
import 'package:family_hub/core/utils/formatters.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/sos/application/sos_controller.dart';
import 'package:family_hub/features/sos/presentation/sos_feedback.dart';
import 'package:family_hub/features/sos/presentation/sos_labels.dart';
import 'package:family_hub/features/sos/presentation/sos_navigation.dart';
import 'package:family_hub/features/sos/presentation/widgets/sos_pulsing_dot.dart';
import 'package:family_hub/features/sos/presentation/widgets/sos_ticker.dart';

/// The member's own active SOS on the SOS tab: pulsing "sharing your live
/// location" indicator (or why the location is not shared, with a fix),
/// time remaining, when the location was last sent, and the
/// "I am okay" / "False alarm" buttons.
class SosActivePanel extends ConsumerWidget {
  const SosActivePanel({super.key, required this.state});

  final SosState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alert = state.alert;
    if (alert == null) return const SizedBox.shrink();
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final sos = context.semanticColors;
    final fmt = ref.watch(fmtProvider);
    final onContainer = sos.onSosContainer;
    final bodyStyle = theme.textTheme.bodyMedium?.copyWith(color: onContainer);

    return AppCard(
      color: sos.sosContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SosPulsingDot(color: sos.sos, size: AppSizes.iconSm),
              AppGap.hSm,
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    l10n.sosActiveTitle,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: onContainer,
                    ),
                  ),
                ),
              ),
            ],
          ),
          AppGap.md,
          SosSharingStatus(state: state, color: onContainer),
          AppGap.sm,
          SosTicker(
            builder: (context, now) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.sosTimeRemaining(
                    sosFormatRemaining(alert.remainingAt(now)),
                  ),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: onContainer,
                  ),
                ),
                if (state.sharing != SosSharing.off) ...[
                  AppGap.xxs,
                  Text(
                    state.lastSentAt == null
                        ? l10n.sosWaitingForLocation
                        : l10n.sosLastSent(
                            sosAgo(state.lastSentAt!, now, fmt, l10n),
                          ),
                    style: bodyStyle,
                  ),
                ],
              ],
            ),
          ),
          AppGap.lg,
          SosOwnResolveButtons(alertId: alert.id),
          AppGap.sm,
          AppButton(
            label: l10n.sosViewAlert,
            icon: AppIcons.forward,
            variant: AppButtonVariant.text,
            onPressed: () => openSosAlert(context, alert.id),
          ),
        ],
      ),
    );
  }
}

/// Whether the member's own SOS shares the live location; when not, why
/// and a button that fixes it (allow permission / open settings / change
/// the sharing mode).
class SosSharingStatus extends ConsumerWidget {
  const SosSharingStatus({super.key, required this.state, this.color});

  final SosState state;
  final Color? color;

  Future<void> _fixPermission(
    BuildContext context,
    WidgetRef ref,
    LocationPermissionState permission,
  ) async {
    if (permission.needsSettings) {
      await ref.read(locationServiceProvider).openSettings();
      return;
    }
    final result = await ref
        .read(sosControllerProvider.notifier)
        .retryLocation();
    if (!context.mounted || result == null || result.isGranted) return;
    context.showInfo(result.message(context.l10n));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final foreground = color ?? theme.colorScheme.onSurface;
    final strong = theme.textTheme.bodyLarge?.copyWith(
      color: foreground,
      fontWeight: AppTypography.semiBold,
    );
    final body = theme.textTheme.bodyMedium?.copyWith(color: foreground);

    Widget line(IconData icon, String text) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: AppSizes.iconSm, color: foreground),
        AppGap.hSm,
        Expanded(child: Text(text, style: strong)),
      ],
    );

    Widget action(String label, VoidCallback onPressed) => Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton(
        style: TextButton.styleFrom(foregroundColor: foreground),
        onPressed: onPressed,
        child: Text(label),
      ),
    );

    switch (state.sharing) {
      case SosSharing.live:
        return Semantics(
          liveRegion: true,
          child: line(AppIcons.liveLocation, l10n.sosSharingLive),
        );
      case SosSharing.off:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            line(AppIcons.locationOff, l10n.sosNotSharingLocation),
            AppGap.xs,
            Text(l10n.sosLocationOffHint, style: body),
            action(
              l10n.sosChangeSharing,
              () => openSosRoute(context, AppRoutes.settingsLocation),
            ),
          ],
        );
      case SosSharing.unavailable:
        final permission = state.permission ?? LocationPermissionState.denied;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            line(AppIcons.locationOff, l10n.sosNotSharingLocation),
            AppGap.xs,
            Text(permission.message(l10n), style: body),
            action(
              permission.actionLabel(l10n),
              () => _fixPermission(context, ref, permission),
            ),
          ],
        );
    }
  }
}

/// "I am okay" / "False alarm" for the member's own alert [alertId]. Both
/// buttons are disabled while either resolve runs; errors are shown as a
/// snackbar. [onResolved] receives the resolved alert.
class SosOwnResolveButtons extends ConsumerWidget {
  const SosOwnResolveButtons({
    super.key,
    required this.alertId,
    this.onResolved,
  });

  final String alertId;
  final ValueChanged<SosAlert>? onResolved;

  Future<void> _resolve(
    BuildContext context,
    WidgetRef ref,
    SosResolution resolution,
  ) async {
    try {
      final resolved = await ref
          .read(sosAlertActionsProvider.notifier)
          .resolve(alertId, resolution);
      if (resolved == null || !context.mounted) return;
      showSosResolved(context, resolution, result: resolved);
      onResolved?.call(resolved);
    } catch (e) {
      if (context.mounted) context.showError(e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final resolving = ref.watch(sosResolvingProvider(alertId));
    final disabled = resolving != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppButton(
          label: l10n.sosImOkay,
          icon: AppIcons.safe,
          isLoading: resolving == SosResolution.safe,
          onPressed: disabled
              ? null
              : () => _resolve(context, ref, SosResolution.safe),
        ),
        AppGap.sm,
        AppButton(
          label: l10n.sosFalseAlarm,
          icon: AppIcons.falseAlarm,
          variant: AppButtonVariant.secondary,
          isLoading: resolving == SosResolution.falseAlarm,
          onPressed: disabled
              ? null
              : () => _resolve(context, ref, SosResolution.falseAlarm),
        ),
      ],
    );
  }
}
