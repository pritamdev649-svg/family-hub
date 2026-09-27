import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/utils/formatters.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/emergency_card/application/emergency_card_providers.dart';
import 'package:family_hub/features/emergency_card/presentation/emergency_card_actions.dart';
import 'package:family_hub/features/emergency_card/presentation/emergency_card_style.dart';
import 'package:family_hub/features/emergency_card/presentation/widgets/blood_group_badge.dart';
import 'package:family_hub/features/emergency_card/presentation/widgets/card_completeness_indicator.dart';
import 'package:family_hub/features/emergency_card/presentation/widgets/emergency_chrome.dart';
import 'package:family_hub/features/emergency_card/presentation/widgets/emergency_header_scroll_view.dart';
import 'package:family_hub/features/emergency_card/presentation/widgets/emergency_section.dart';
import 'package:family_hub/shared/models/member.dart';
import 'package:family_hub/shared/providers/shared_providers.dart';

/// `/emergency-cards`: every family member with their blood group and how
/// complete their card is. Works offline from the last known member
/// directory and the offline card copies.
///
/// Layout (docs/12-DESIGN_LANGUAGE.md §3b): a full-bleed rose gradient
/// header behind the transparent status bar (title, intro and glass stat
/// pills), the country's emergency number as a solid red card overlapping
/// it, then one borderless row per member.
class EmergencyCardsScreen extends ConsumerWidget {
  const EmergencyCardsScreen({super.key});

  static Future<void> _refresh(WidgetRef ref) async {
    ref
      ..invalidate(membersProvider)
      ..invalidate(emergencyCardProvider);
    await ref.read(emergencyCardMembersProvider.future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final members = ref.watch(emergencyCardMembersProvider);

    return Scaffold(
      body: EmergencyHeaderScrollView(
        gradient: AppGradients.headerOf(EmergencyCardAccents.module),
        onRefresh: () => _refresh(ref),
        header: _ListHeader(members: members.value),
        children: [
          const EmergencyOfflineNotice(),
          const _EmergencyNumberCard(),
          AsyncValueView<List<Member>>(
            value: members,
            onRetry: () => ref.invalidate(membersProvider),
            isEmpty: (list) => list.isEmpty,
            empty: EmergencyStateCard(
              icon: AppIcons.members,
              accent: EmergencyCardAccents.module,
              title: l10n.commonNothingHere,
            ),
            data: (list) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < list.length; i++) ...[
                  if (i > 0) AppGap.sm,
                  EmergencyCardTile(
                    key: ValueKey('emergency-card-tile-${list[i].id}'),
                    member: list[i],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Header content: back, title, intro and two glass stats (members, cards
/// with every key detail).
class _ListHeader extends ConsumerWidget {
  const _ListHeader({required this.members});

  /// `null` while the member list is loading (or failed).
  final List<Member>? members;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final fmt = ref.watch(fmtProvider);
    final list = members ?? const <Member>[];
    // Cards load per member (the tiles below start the loads); count the
    // complete ones among those already known.
    var complete = 0;
    for (final m in list) {
      final card = ref.watch(emergencyCardProvider(m.id)).value;
      if (card != null && card.completeness.isComplete) complete++;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const EmergencyHeaderTopBar(),
        AppGap.md,
        Row(
          children: [
            const EmergencyGlassIcon(
              icon: AppIcons.emergencyCard,
              size: AppSizes.badgeMd,
            ),
            AppGap.hMd,
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  l10n.emergencyCardListTitle,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
        AppGap.md,
        Text(
          l10n.emergencyCardListIntro,
          style: theme.textTheme.bodyMedium?.copyWith(color: mutedOnGradient()),
        ),
        if (list.isNotEmpty) ...[
          AppGap.xl,
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: EmergencyGlassPill(
                  icon: AppIcons.members,
                  value: fmt.number(list.length),
                  label: l10n.emergencyCardStatMembers,
                ),
              ),
              AppGap.hSm,
              Expanded(
                child: EmergencyGlassPill(
                  icon: AppIcons.success,
                  value: fmt.number(complete),
                  label: l10n.emergencyCardStatComplete,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// "In danger? Call 112" as a solid emergency-red card (hidden when the
/// country has no emergency number configured).
class _EmergencyNumberCard extends ConsumerWidget {
  const _EmergencyNumberCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final number = ref.watch(currentCountryProvider).emergencyNumber.trim();
    if (number.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Semantics(
        button: true,
        child: GradientCard(
          gradient: AppGradients.sos,
          glowColor: context.semanticColors.sos,
          padding: const EdgeInsets.all(AppSpacing.lg),
          onTap: () => callFromEmergencyCard(context, number),
          child: Row(
            children: [
              const EmergencyGlassIcon(
                icon: AppIcons.calling,
                size: AppSizes.badgeMd,
              ),
              AppGap.hMd,
              Expanded(
                child: Text(
                  context.l10n.emergencyCardCallEmergencyNumber(number),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                  ),
                ),
              ),
              AppGap.hSm,
              const Icon(AppIcons.phone, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

/// One member in the cards list: avatar, name, completeness progress and a
/// solid rose blood group pill. Loads (and caches) that member's card; a
/// cached card older than [EmergencyCardNotifier.freshFor] (or an offline
/// copy) is refreshed in the background when the tile appears.
class EmergencyCardTile extends ConsumerStatefulWidget {
  const EmergencyCardTile({super.key, required this.member});

  final Member member;

  @override
  ConsumerState<EmergencyCardTile> createState() => _EmergencyCardTileState();
}

class _EmergencyCardTileState extends ConsumerState<EmergencyCardTile> {
  @override
  void initState() {
    super.initState();
    _refreshIfStale();
  }

  @override
  void didUpdateWidget(EmergencyCardTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.member.id != widget.member.id) _refreshIfStale();
  }

  /// After the frame: providers must not change while building.
  void _refreshIfStale() {
    final id = widget.member.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(emergencyCardProvider(id).notifier).refreshIfStale();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final member = widget.member;
    final card = ref.watch(emergencyCardProvider(member.id));
    final isMe = ref.watch(currentMemberProvider)?.id == member.id;
    final value = card.value;
    final designation = member.designation;

    final Widget status;
    if (value != null) {
      status = CardCompletenessIndicator(card: value);
    } else if (card.hasError && !card.isLoading) {
      status = Row(
        children: [
          Icon(AppIcons.error, size: AppSizes.iconXs, color: scheme.error),
          AppGap.hXs,
          Expanded(
            child: Text(
              l10n.emergencyCardLoadFailed,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
          ),
        ],
      );
    } else {
      status = Semantics(
        label: l10n.commonLoading,
        child: LinearProgressIndicator(
          minHeight: AppSizes.refreshBar,
          borderRadius: AppRadius.brPill,
          color: context.accent(EmergencyCardAccents.module).base,
          backgroundColor: scheme.surfaceContainerHighest,
        ),
      );
    }

    return AppCard(
      onTap: () =>
          pushFromEmergencyCard(context, AppRoutes.emergencyCard(member.id)),
      child: Row(
        children: [
          MemberAvatar(
            name: member.name,
            avatarUrl: member.avatarUrl,
            radius: AppSizes.avatarLg,
          ),
          AppGap.hMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(member.name, style: theme.textTheme.titleSmall),
                    if (isMe)
                      StatusChip(
                        label: l10n.commonMe,
                        color: context.accent(AppAccents.brand).foreground,
                      ),
                    if (value?.isOfflineCopy ?? false)
                      StatusChip(
                        label: l10n.emergencyCardOfflineCopyShort,
                        icon: AppIcons.offline,
                        color: context.accent(AppAccents.warning).foreground,
                      ),
                  ],
                ),
                if (designation != null)
                  Text(
                    designation,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                AppGap.sm,
                status,
              ],
            ),
          ),
          AppGap.hMd,
          BloodGroupBadge(group: value?.bloodGroup ?? BloodGroup.unknown),
          AppGap.hXs,
          Icon(
            AppIcons.chevron,
            size: AppSizes.iconSm,
            color: scheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}
