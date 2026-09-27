import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/config/app_config.dart';
import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/sos/application/sos_controller.dart';
import 'package:family_hub/features/sos/application/sos_providers.dart';
import 'package:family_hub/features/sos/presentation/sos_feedback.dart';
import 'package:family_hub/features/sos/presentation/sos_navigation.dart';
import 'package:family_hub/features/sos/presentation/widgets/sos_active_panel.dart';
import 'package:family_hub/features/sos/presentation/widgets/sos_alert_tile.dart';
import 'package:family_hub/features/sos/presentation/widgets/sos_button.dart';
import 'package:family_hub/features/sos/presentation/widgets/sos_emergency_call_button.dart';
import 'package:family_hub/features/sos/presentation/widgets/sos_info_cards.dart';
import 'package:family_hub/features/sos/presentation/widgets/sos_location_choice_dialog.dart';
import 'package:family_hub/shared/providers/shared_providers.dart';

/// The SOS tab (`/sos`).
///
/// * Idle: the huge red SOS button. A tap starts a 3-second countdown that
///   can be cancelled, then alerts the family (see [SosController]).
/// * Own alert active: [SosActivePanel] (live location indicator, time
///   left, last sent, "I am okay" / "False alarm").
/// * Always: "Call emergency services `number`", the "alerts your family
///   only" disclaimer, the member's location sharing mode (→ settings),
///   other members' active alerts and a link to the history.
class SosScreen extends ConsumerWidget {
  const SosScreen({super.key});

  static Future<void> trigger(
    BuildContext context,
    WidgetRef ref, {
    bool skipCountdown = false,
  }) async {
    HapticFeedback.heavyImpact();
    final outcome = await ref
        .read(sosControllerProvider.notifier)
        .start(
          skipCountdown: skipCountdown,
          askLocationChoice: () async =>
              context.mounted ? showSosLocationChoiceDialog(context) : null,
        );
    if (context.mounted) showSosSendOutcome(context, outcome);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(sosControllerProvider);
    final others = ref.watch(otherActiveSosAlertsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.sosTitle),
        actions: [
          IconButton(
            tooltip: l10n.sosHistoryTooltip,
            icon: const Icon(AppIcons.history),
            onPressed: () => openSosRoute(context, AppRoutes.sosHistory),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ResponsiveCenter(
          child: AppRefreshIndicator(
            onRefresh: () => ref.refresh(activeSosAlertsProvider.future),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: AppSpacing.screen,
              children: [
                if (state.isActive)
                  SosActivePanel(state: state)
                else
                  _TriggerSection(state: state),
                if (state.isIdle && state.sendError != null) ...[
                  AppGap.lg,
                  _SendFailedCard(error: state.sendError!),
                ],
                AppGap.xl,
                const SosEmergencyCallButton(),
                AppGap.md,
                const SosDisclaimerCard(),
                AppGap.md,
                const SosLocationModeRow(),
                AppGap.lg,
                SectionHeader(title: l10n.sosOthersTitle),
                AsyncValueView<List<SosAlert>>(
                  value: others,
                  onRetry: () => ref.invalidate(activeSosAlertsProvider),
                  isEmpty: (alerts) => alerts.isEmpty,
                  empty: SosSectionNote(
                    icon: AppIcons.safe,
                    text: l10n.sosOthersEmpty,
                  ),
                  data: (alerts) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final alert in alerts) ...[
                        SosAlertTile(alert),
                        AppGap.sm,
                      ],
                    ],
                  ),
                ),
                AppGap.md,
                SosLinkRow(
                  icon: AppIcons.history,
                  label: l10n.sosHistoryLink,
                  onTap: () => openSosRoute(context, AppRoutes.sosHistory),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The SOS button with the hint / countdown text and the Cancel button.
class _TriggerSection extends ConsumerWidget {
  const _TriggerSection({required this.state});

  final SosState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final hasSession = ref.watch(currentMemberProvider) != null;
    final String caption;
    if (state.isCountingDown) {
      caption = l10n.sosSendingIn(state.secondsLeft);
    } else if (state.isSending) {
      caption = l10n.sosSending;
    } else {
      caption = l10n.sosButtonHint(AppConfig.sosCountdownSeconds);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppGap.lg,
        SosButton(
          state: state,
          onPressed: hasSession ? () => SosScreen.trigger(context, ref) : null,
        ),
        AppGap.lg,
        Text(
          caption,
          textAlign: TextAlign.center,
          style: state.isIdle
              ? theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                )
              : theme.textTheme.titleLarge?.copyWith(
                  color: context.semanticColors.sos,
                ),
        ),
        if (state.isCountingDown) ...[
          AppGap.lg,
          Center(
            child: AppButton(
              label: l10n.sosCancelAlert,
              icon: AppIcons.close,
              variant: AppButtonVariant.secondary,
              expand: false,
              onPressed: () =>
                  ref.read(sosControllerProvider.notifier).cancelCountdown(),
            ),
          ),
        ],
      ],
    );
  }
}

/// Shown after sending failed: why, "Send again" (no countdown) and the
/// emergency number.
class _SendFailedCard extends ConsumerWidget {
  const _SendFailedCard({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final number = ref.watch(
      currentCountryProvider.select((c) => c.emergencyNumber),
    );
    return Semantics(
      liveRegion: true,
      container: true,
      child: AppCard(
        color: scheme.errorContainer,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(AppIcons.error, color: scheme.onErrorContainer),
                AppGap.hSm,
                Expanded(
                  child: Text(
                    l10n.sosSendFailedTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: scheme.onErrorContainer,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: l10n.commonClose,
                  color: scheme.onErrorContainer,
                  icon: const Icon(AppIcons.close),
                  onPressed: () =>
                      ref.read(sosControllerProvider.notifier).clearSendError(),
                ),
              ],
            ),
            AppGap.xs,
            Text(
              l10n.sosSendFailedMessage(number),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onErrorContainer,
              ),
            ),
            AppGap.md,
            AppButton(
              label: l10n.sosTryAgain,
              icon: AppIcons.retry,
              onPressed: () =>
                  SosScreen.trigger(context, ref, skipCountdown: true),
            ),
          ],
        ),
      ),
    );
  }
}
