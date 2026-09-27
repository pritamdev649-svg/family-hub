import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/utils/formatters.dart';
import 'package:family_hub/core/utils/url_actions.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/family/application/family_providers.dart';
import 'package:family_hub/features/family/application/family_session_sync.dart';
import 'package:family_hub/features/family/application/member_removal_controller.dart';
import 'package:family_hub/features/family/domain/member_designation.dart';
import 'package:family_hub/features/family/presentation/family_labels.dart';
import 'package:family_hub/features/family/presentation/family_navigation.dart';
import 'package:family_hub/features/family/presentation/family_style.dart';
import 'package:family_hub/features/family/presentation/widgets/family_action_grid.dart';
import 'package:family_hub/features/family/presentation/widgets/family_glass.dart';
import 'package:family_hub/features/family/presentation/widgets/family_info_row.dart';
import 'package:family_hub/features/family/presentation/widgets/member_avatar_ring.dart';
import 'package:family_hub/features/family/presentation/widgets/member_gone_view.dart';
import 'package:family_hub/shared/l10n/shared_labels.dart';
import 'package:family_hub/shared/models/member.dart';
import 'package:family_hub/shared/session/session_controller.dart';

/// One member: a blue gradient header behind the transparent status bar
/// (big avatar, name, designation, role / age glass pills), colourful action
/// tiles (call, email, emergency card, assign task), details / contact /
/// location cards with colourful icon rows, then edit and remove.
///
/// While there is no member to show (first load, error, or a member that no
/// longer exists — removed, also while this screen is open, or an old /
/// malformed link) a plain canvas app bar with the state view is shown;
/// a missing member shows [MemberGoneView] instead of an error.
class MemberDetailScreen extends ConsumerWidget {
  const MemberDetailScreen({super.key, required this.memberId});

  final String memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final member = memberOrGone(ref.watch(memberByIdProvider(memberId)));
    ref.syncFamilySession();

    void retry() {
      ref.invalidate(membersProvider);
      ref.invalidate(memberByIdProvider(memberId));
    }

    Future<void> refresh() => ref.refresh(membersProvider.future);

    // Latest member, also while refreshing or after a failed refresh.
    final current = member.value;
    if (current == null) {
      return Scaffold(
        appBar: AppBar(),
        body: ResponsiveCenter(
          child: AppRefreshIndicator(
            onRefresh: refresh,
            child: AsyncValueView<Member?>(
              value: member,
              onRetry: retry,
              isEmpty: (m) => m == null,
              empty: const MemberGoneView(),
              data: (_) => const MemberGoneView(),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: GradientHeaderScrollView(
        gradient: FamilyStyle.header,
        onRefresh: refresh,
        header: _Header(member: current),
        children: [
          // Keeps the refresh progress / "couldn't refresh" notice.
          AsyncValueView<Member?>(
            value: member,
            onRetry: retry,
            data: (m) => _MemberDetailBody(member: m ?? current),
          ),
        ],
      ),
    );
  }
}

class _MemberDetailBody extends ConsumerWidget {
  const _MemberDetailBody({required this.member});

  final Member member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final isAdmin = ref.watch(isAdminProvider);
    final isMe =
        ref.watch(currentMemberProvider.select((m) => m?.id)) == member.id;
    final removing = ref.watch(
      memberRemovalControllerProvider.select((s) => s.isLoading),
    );
    final canManage = isAdmin || isMe;
    final phone = member.phone;
    final email = member.email;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          label: l10n.familyActionsSection,
          child: FamilyActionGrid(
            children: [
              if (phone != null)
                ActionTile(
                  icon: AppIcons.phone,
                  label: l10n.commonCall,
                  accent: AppAccent.emerald,
                  onTap: () => _call(context, phone),
                ),
              if (email != null)
                ActionTile(
                  icon: AppIcons.email,
                  label: l10n.familyEmailAction,
                  accent: AppAccent.sky,
                  onTap: () => _email(context, email),
                ),
              ActionTile(
                icon: AppIcons.emergencyCard,
                label: l10n.familyEmergencyCard,
                accent: AppAccents.emergency,
                onTap: () =>
                    context.pushIfTop(AppRoutes.emergencyCard(member.id)),
              ),
              if (canManage)
                ActionTile(
                  icon: AppIcons.task,
                  label: l10n.familyAssignTask,
                  accent: AppAccents.tasks,
                  onTap: () => context.pushIfTop(
                    AppRoutes.taskNew(assigneeId: member.id),
                  ),
                ),
            ],
          ),
        ),
        AppGap.xl,
        SectionHeader(
          title: l10n.familyDetailsSection,
          icon: AppIcons.memberOutlined,
          accent: FamilyStyle.accent,
        ),
        AppCard(child: _DetailRows(member: member)),
        if (phone != null || email != null) ...[
          AppGap.xl,
          SectionHeader(
            title: l10n.familyContactSection,
            icon: AppIcons.phone,
            accent: AppAccent.emerald,
          ),
          AppCard(
            child: Column(
              children: [
                if (phone != null)
                  FamilyInfoRow(
                    icon: AppIcons.phone,
                    accent: AppAccent.emerald,
                    label: l10n.familyInfoPhone,
                    value: phone,
                  ),
                if (email != null)
                  FamilyInfoRow(
                    icon: AppIcons.email,
                    accent: AppAccent.sky,
                    label: l10n.familyInfoEmail,
                    value: email,
                  ),
              ],
            ),
          ),
        ],
        AppGap.xl,
        SectionHeader(
          title: l10n.familyLocationSection,
          icon: AppIcons.location,
          accent: AppAccent.teal,
        ),
        AppCard(
          child: _LocationRows(member: member, isMe: isMe),
        ),
        if (canManage) ...[
          AppGap.xl,
          AppButton(
            label: l10n.familyEditDetails,
            icon: AppIcons.edit,
            variant: AppButtonVariant.tonal,
            onPressed: removing
                ? null
                : () => context.pushIfTop(AppRoutes.memberEdit(member.id)),
          ),
        ],
        // Admins leave the family from Settings → Privacy, not from here.
        if (isAdmin && !isMe) ...[
          AppGap.md,
          AppButton(
            label: l10n.familyRemoveMember,
            icon: AppIcons.delete,
            variant: AppButtonVariant.danger,
            isLoading: removing,
            onPressed: () => _confirmRemove(context, ref),
          ),
        ],
      ],
    );
  }

  static Future<void> _call(BuildContext context, String phone) async {
    final message = context.l10n.familyCannotOpenPhone;
    final ok = await UrlActions.call(phone);
    if (!ok && context.mounted) context.showInfo(message);
  }

  static Future<void> _email(BuildContext context, String email) async {
    final message = context.l10n.familyCannotOpenEmail;
    final ok = await UrlActions.email(email);
    if (!ok && context.mounted) context.showInfo(message);
  }

  Future<void> _confirmRemove(BuildContext context, WidgetRef ref) async {
    // A second tap while the dialog opens must not open another one.
    if (!context.isTopRoute) return;
    final l10n = context.l10n;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.familyRemoveConfirmTitle(member.name),
      message: l10n.familyRemoveConfirmMessage(member.name),
      confirmLabel: l10n.commonRemove,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    try {
      final outcome = await ref
          .read(memberRemovalControllerProvider.notifier)
          .remove(member);
      if (!context.mounted) return;
      switch (outcome) {
        case MemberRemovalOutcome.busy:
          return;
        case MemberRemovalOutcome.removed:
          context.showSuccess(l10n.familyMemberRemoved(member.name));
        case MemberRemovalOutcome.alreadyRemoved:
          context.showInfo(l10n.familyMemberAlreadyRemoved(member.name));
      }
      context.popOrGo(AppRoutes.members);
    } catch (e) {
      // LAST_ADMIN, FORBIDDEN, offline … → localised message.
      if (context.mounted) context.showError(e);
    }
  }
}

/// Header content on the blue gradient: back, big avatar, name,
/// designation and glass pills ("You", role, age, account).
class _Header extends ConsumerWidget {
  const _Header({required this.member});

  final Member member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final isMe =
        ref.watch(currentMemberProvider.select((m) => m?.id)) == member.id;
    final designation = member.designation;
    final ageLabel = member.ageGroupLabel(l10n);
    final status = member.accountStatus;
    final accountBadge = status.badge(l10n);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FamilyHeaderBar(),
        AppGap.sm,
        Center(child: MemberAvatarRing.onGradient(member: member)),
        AppGap.md,
        Semantics(
          header: true,
          child: Text(
            member.name,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(color: Colors.white),
          ),
        ),
        if (designation != null) ...[
          AppGap.xs,
          Text(
            designation,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: FamilyStyle.mutedOnGradient,
            ),
          ),
        ],
        AppGap.md,
        Wrap(
          alignment: WrapAlignment.center,
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            if (isMe)
              FamilyGlassPill(
                label: l10n.familyYouBadge,
                icon: AppIcons.sparkle,
              ),
            FamilyGlassPill(
              label: member.role.label(l10n),
              icon: member.role.icon,
            ),
            if (ageLabel != null)
              FamilyGlassPill(label: ageLabel, icon: AppIcons.birthday),
            if (accountBadge != null)
              FamilyGlassPill(label: accountBadge, icon: status.icon),
          ],
        ),
      ],
    );
  }
}

/// Age, date of birth, gender, role, account and guardian consent.
class _DetailRows extends ConsumerWidget {
  const _DetailRows({required this.member});

  final Member member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final fmt = ref.watch(fmtProvider);
    final country = ref.watch(currentCountryProvider);
    final birthDate = member.birthDate;
    final notSet = l10n.commonNotSet;
    final status = member.accountStatus;
    final ageGroup = member.ageGroup;

    return Column(
      children: [
        FamilyInfoRow(
          icon: AppIcons.birthday,
          accent: ageGroup?.accent ?? AppAccent.orange,
          label: l10n.familyInfoAge,
          value: member.ageGroupLabel(l10n) ?? notSet,
        ),
        FamilyInfoRow(
          icon: AppIcons.calendar,
          accent: AppAccent.pink,
          label: l10n.familyInfoDateOfBirth,
          value: birthDate == null ? notSet : fmt.date(birthDate),
        ),
        FamilyInfoRow(
          icon: AppIcons.gender,
          accent: AppAccent.violet,
          label: l10n.familyInfoGender,
          value: member.gender.labelOrUnspecified(l10n),
        ),
        FamilyInfoRow(
          icon: member.role.icon,
          accent: member.role.accent,
          label: l10n.familyInfoRole,
          value: member.role.label(l10n),
          detail: member.role.description(l10n),
        ),
        FamilyInfoRow(
          icon: status.icon,
          accent: AppAccent.indigo,
          label: l10n.familyInfoAccount,
          value: status.label(l10n),
        ),
        if (member.isMinorIn(country))
          FamilyInfoRow(
            icon: AppIcons.guardian,
            accent: member.guardianConsent
                ? AppAccents.success
                : AppAccents.warning,
            label: l10n.familyInfoGuardianConsent,
            value: member.guardianConsent
                ? l10n.familyGuardianConsentGiven
                : l10n.familyGuardianConsentMissing,
            valueColor: member.guardianConsent
                ? null
                : context.semanticColors.warning,
          ),
      ],
    );
  }
}

/// Location sharing (with "Change" for the member themselves) and the last
/// known location (with "Open map").
class _LocationRows extends ConsumerWidget {
  const _LocationRows({required this.member, required this.isMe});

  final Member member;
  final bool isMe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final fmt = ref.watch(fmtProvider);
    final location = member.lastLocation;
    final recordedAt = location?.recordedAt;

    return Column(
      children: [
        FamilyInfoRow(
          icon: member.locationSharing.icon,
          accent: AppAccent.teal,
          label: l10n.familyInfoLocationSharing,
          value: member.locationSharing.label(l10n),
          detail: isMe ? member.locationSharing.description(l10n) : null,
          // Only the member themselves controls location sharing.
          trailing: isMe
              ? FamilyRowAction(
                  label: l10n.familyChangeAction,
                  accent: AppAccent.teal,
                  onPressed: () =>
                      context.pushIfTop(AppRoutes.settingsLocation),
                )
              : null,
        ),
        if (location != null)
          FamilyInfoRow(
            icon: AppIcons.location,
            accent: AppAccent.blue,
            label: l10n.familyInfoLastLocation,
            value: recordedAt == null
                ? l10n.commonUnknown
                : l10n.familyLastLocationUpdated(
                    fmt.relative(recordedAt, l10n),
                  ),
            trailing: FamilyRowAction(
              label: l10n.familyOpenMap,
              accent: AppAccent.blue,
              onPressed: () async {
                final message = l10n.familyCannotOpenMap;
                final ok = await UrlActions.openMap(
                  location.lat,
                  location.lng,
                  label: member.name,
                );
                if (!ok && context.mounted) context.showInfo(message);
              },
            ),
          ),
      ],
    );
  }
}
