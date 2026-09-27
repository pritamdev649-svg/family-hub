import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/utils/formatters.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/family/application/family_session_sync.dart';
import 'package:family_hub/features/family/presentation/family_navigation.dart';
import 'package:family_hub/features/family/presentation/family_style.dart';
import 'package:family_hub/features/family/presentation/widgets/family_glass.dart';
import 'package:family_hub/features/family/presentation/widgets/member_tile.dart';
import 'package:family_hub/shared/models/member.dart';
import 'package:family_hub/shared/session/session_controller.dart';

/// Everyone in the family (admins first, then oldest → youngest), with an
/// "Add member" button for admins and a shortcut to the family settings.
///
/// Layout: a full-bleed blue gradient header behind the transparent status
/// bar (back, settings, title, member count and glass statistics), then the
/// borderless member cards sliding over its rounded bottom edge.
///
/// The list also keeps the session in step (see [FamilySessionSync]): a
/// role change made on another phone updates the admin-only actions here,
/// and `NO_FAMILY` (removed from the family) resyncs the session.
class MembersScreen extends ConsumerWidget {
  const MembersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final members = ref.watch(membersProvider);
    final isAdmin = ref.watch(isAdminProvider);
    final myId = ref.watch(currentMemberProvider.select((m) => m?.id));
    final familyName = ref.watch(currentFamilyProvider.select((f) => f?.name));
    ref.syncFamilySession();

    void addMember() => context.pushIfTop(AppRoutes.memberNew);

    return Scaffold(
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              onPressed: addMember,
              backgroundColor: FamilyStyle.solid(FamilyStyle.accent),
              foregroundColor: Colors.white,
              icon: const Icon(AppIcons.addMember),
              label: Text(l10n.familyAddMember),
            )
          : null,
      body: GradientHeaderScrollView(
        gradient: FamilyStyle.header,
        onRefresh: () => ref.refresh(membersProvider.future),
        header: _MembersHeader(familyName: familyName, members: members.value),
        children: [
          AsyncValueView<List<Member>>(
            value: members,
            onRetry: () => ref.invalidate(membersProvider),
            isEmpty: (list) => list.isEmpty,
            empty: EmptyState(
              icon: AppIcons.members,
              title: l10n.familyMembersEmptyTitle,
              message: l10n.familyMembersEmptyMessage,
              action: isAdmin
                  ? AppButton(
                      label: l10n.familyAddMember,
                      icon: AppIcons.addMember,
                      expand: false,
                      onPressed: addMember,
                    )
                  : null,
            ),
            data: (list) => _MemberList(members: list, myId: myId),
          ),
          // Room below the last card for the "Add member" button.
          if (isAdmin) SizedBox(height: AppSpacing.screenWithFab.bottom),
        ],
      ),
    );
  }
}

/// Header content: back / settings, the family's name, the title, how many
/// members there are and three glass statistics (admins, members with their
/// own account, kids & teens) once the list has loaded.
class _MembersHeader extends ConsumerWidget {
  const _MembersHeader({required this.familyName, required this.members});

  final String? familyName;

  /// `null` until the list has loaded.
  final List<Member>? members;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final fmt = ref.watch(fmtProvider);
    final muted = FamilyStyle.mutedOnGradient;
    final name = familyName?.trim() ?? '';
    final list = members;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FamilyHeaderBar(
          actions: [
            FamilyGlassIconButton(
              icon: AppIcons.settings,
              tooltip: l10n.familySettingsTooltip,
              onPressed: () => context.pushIfTop(AppRoutes.familySettings),
            ),
          ],
        ),
        AppGap.md,
        if (name.isNotEmpty) ...[
          Row(
            children: [
              Icon(AppIcons.family, size: AppSizes.iconSm, color: muted),
              AppGap.hXs,
              Flexible(
                child: Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(color: muted),
                ),
              ),
            ],
          ),
          AppGap.sm,
        ],
        Semantics(
          header: true,
          child: Text(
            l10n.familyMembersTitle,
            style: theme.textTheme.headlineSmall?.copyWith(color: Colors.white),
          ),
        ),
        if (list != null) ...[
          AppGap.xs,
          Text(
            l10n.familyMembersCount(list.length),
            style: theme.textTheme.bodyMedium?.copyWith(color: muted),
          ),
        ],
        if (list != null && list.isNotEmpty) ...[
          AppGap.xl,
          Row(
            children: [
              Expanded(
                child: FamilyGlassStat(
                  icon: AppIcons.roleAdmin,
                  value: fmt.number(list.where((m) => m.isAdmin).length),
                  label: l10n.familyStatAdmins,
                ),
              ),
              AppGap.hSm,
              Expanded(
                child: FamilyGlassStat(
                  icon: AppIcons.phone,
                  value: fmt.number(list.where((m) => m.hasAccount).length),
                  label: l10n.familyStatAppUsers,
                ),
              ),
              AppGap.hSm,
              Expanded(
                child: FamilyGlassStat(
                  icon: AppIcons.birthday,
                  value: fmt.number(list.where(_isKid).length),
                  label: l10n.familyStatKids,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  static bool _isKid(Member m) =>
      m.ageGroup == AgeGroup.child || m.ageGroup == AgeGroup.teen;
}

class _MemberList extends StatelessWidget {
  const _MemberList({required this.members, required this.myId});

  final List<Member> members;
  final String? myId;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < members.length; i++) ...[
          if (i > 0) AppGap.sm,
          MemberTile(
            key: ValueKey<String>('member-${members[i].id}'),
            member: members[i],
            isMe: members[i].id == myId,
            onTap: () =>
                context.pushIfTop(AppRoutes.memberDetail(members[i].id)),
          ),
        ],
      ],
    );
  }
}
