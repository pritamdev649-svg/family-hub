import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/emergency_card/application/emergency_card_providers.dart';
import 'package:family_hub/features/emergency_card/presentation/emergency_card_actions.dart';
import 'package:family_hub/features/emergency_card/presentation/emergency_card_labels.dart';
import 'package:family_hub/features/emergency_card/presentation/emergency_card_style.dart';
import 'package:family_hub/features/emergency_card/presentation/screens/emergency_card_responder_screen.dart';
import 'package:family_hub/features/emergency_card/presentation/widgets/blood_group_badge.dart';
import 'package:family_hub/features/emergency_card/presentation/widgets/card_unavailable.dart';
import 'package:family_hub/features/emergency_card/presentation/widgets/emergency_card_view.dart';
import 'package:family_hub/features/emergency_card/presentation/widgets/emergency_chrome.dart';
import 'package:family_hub/features/emergency_card/presentation/widgets/emergency_header_scroll_view.dart';
import 'package:family_hub/shared/models/member.dart';

/// `/emergency-cards/:memberId`: one member's card, with "Show to
/// responder" and — for the member themselves or an admin — Edit.
///
/// Layout (docs/12-DESIGN_LANGUAGE.md §3b): a full-bleed rose gradient
/// header behind the transparent status bar with the member's name and a
/// huge white blood group badge; "Show to responder" as a solid red card
/// overlapping it; then the card's sections.
///
/// A card already in memory is shown at once and refreshed in the
/// background when it is older than [EmergencyCardNotifier.freshFor] (or an
/// offline copy), so edits made on another phone show up. `NOT_FOUND`
/// (member removed, stale link) shows [EmergencyCardUnavailable].
class EmergencyCardScreen extends ConsumerStatefulWidget {
  const EmergencyCardScreen({super.key, required this.memberId});

  final String memberId;

  @override
  ConsumerState<EmergencyCardScreen> createState() =>
      _EmergencyCardScreenState();
}

class _EmergencyCardScreenState extends ConsumerState<EmergencyCardScreen> {
  String get _memberId => widget.memberId;

  @override
  void initState() {
    super.initState();
    // After the first frame: providers must not change while building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(emergencyCardProvider(_memberId).notifier).refreshIfStale();
    });
  }

  void _edit() =>
      pushFromEmergencyCard(context, AppRoutes.emergencyCardEdit(_memberId));

  Future<void> _refresh() async {
    ref.invalidate(emergencyCardProvider(_memberId));
    await ref.read(emergencyCardProvider(_memberId).future);
  }

  @override
  Widget build(BuildContext context) {
    final card = ref.watch(emergencyCardProvider(_memberId));
    final member = ref.watch(emergencyCardMemberProvider(_memberId)).value;
    final canEdit = ref.watch(canEditEmergencyCardProvider(_memberId));
    // Also after a refresh: a removed member's card is gone on the server.
    final unavailable = !card.isLoading && isEmergencyCardNotFound(card.error);

    return Scaffold(
      body: EmergencyHeaderScrollView(
        gradient: AppGradients.headerOf(EmergencyCardAccents.module),
        onRefresh: unavailable ? null : _refresh,
        header: _CardHeader(
          member: member,
          card: unavailable ? null : card.value,
          onEdit: canEdit && card.hasValue && !unavailable ? _edit : null,
        ),
        children: [
          const EmergencyOfflineNotice(),
          if (unavailable)
            const EmergencyCardUnavailable()
          else
            AsyncValueView<EmergencyCard>(
              value: card,
              onRetry: () => ref.invalidate(emergencyCardProvider(_memberId)),
              loading: const AppCard(child: LoadingView()),
              data: (data) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!data.isEmpty) ...[
                    _ResponderCard(
                      onTap: () => EmergencyCardResponderScreen.open(
                        context,
                        card: data,
                        member: member,
                      ),
                    ),
                    AppGap.lg,
                  ],
                  EmergencyCardView(
                    card: data,
                    member: member,
                    onEdit: canEdit ? _edit : null,
                    showHeader: false,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Header content: back / edit, "Emergency card" caption, the member's name
/// and designation, the huge blood group badge and a glass completeness
/// pill. [card] is `null` while loading or when the card is unavailable.
class _CardHeader extends StatelessWidget {
  const _CardHeader({
    required this.member,
    required this.card,
    required this.onEdit,
  });

  final Member? member;
  final EmergencyCard? card;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final muted = mutedOnGradient();
    final m = member;
    final c = card;
    final designation = m?.designation;
    final edit = onEdit;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EmergencyHeaderTopBar(
          actions: [
            if (edit != null)
              EmergencyGlassIconButton(
                icon: AppIcons.edit,
                tooltip: l10n.emergencyCardEditAction,
                onPressed: edit,
              ),
          ],
        ),
        AppGap.md,
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (m != null) ...[
                    Row(
                      children: [
                        Icon(
                          AppIcons.emergencyCard,
                          size: AppSizes.iconSm,
                          color: muted,
                        ),
                        AppGap.hXs,
                        Flexible(
                          child: Text(
                            l10n.emergencyCardTitle,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                    AppGap.sm,
                  ],
                  Semantics(
                    header: true,
                    child: Text(
                      m?.name ?? l10n.emergencyCardTitle,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ),
                  if (designation != null) ...[
                    AppGap.xs,
                    Text(
                      designation,
                      style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                    ),
                  ],
                ],
              ),
            ),
            if (c != null) ...[
              AppGap.hMd,
              BloodGroupBadge(
                group: c.bloodGroup,
                size: BloodGroupBadgeSize.header,
              ),
            ],
          ],
        ),
        if (c != null && !c.isEmpty) ...[
          AppGap.lg,
          EmergencyGlassPill(
            icon: switch (c.progress) {
              EmergencyCardProgress.complete => AppIcons.success,
              EmergencyCardProgress.partial => AppIcons.warning,
              EmergencyCardProgress.notStarted => AppIcons.info,
            },
            label: c.progressLabel(l10n),
          ),
        ],
      ],
    );
  }
}

/// "Show to responder" as a solid emergency-red card: the main action of
/// the screen, right below the header.
class _ResponderCard extends StatelessWidget {
  const _ResponderCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      child: GradientCard(
        gradient: AppGradients.sos,
        glowColor: context.semanticColors.sos,
        padding: const EdgeInsets.all(AppSpacing.lg),
        onTap: onTap,
        child: Row(
          children: [
            const EmergencyGlassIcon(
              icon: AppIcons.emergencyCard,
              size: AppSizes.badgeMd,
            ),
            AppGap.hMd,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.emergencyCardShowToResponder,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                    ),
                  ),
                  AppGap.xxs,
                  Text(
                    l10n.emergencyCardResponderHint,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: mutedOnGradient(),
                    ),
                  ),
                ],
              ),
            ),
            AppGap.hSm,
            const Icon(AppIcons.chevron, color: Colors.white),
          ],
        ),
      ),
    );
  }
}
