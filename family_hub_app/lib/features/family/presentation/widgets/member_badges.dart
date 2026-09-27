import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/family/domain/member_designation.dart';
import 'package:family_hub/features/family/presentation/family_labels.dart';
import 'package:family_hub/features/family/presentation/family_style.dart';
import 'package:family_hub/shared/l10n/shared_labels.dart';
import 'package:family_hub/shared/models/member.dart';

/// Role, age group, account and "You" pills of a member, each in its own
/// accent with a thin icon (colour is never the only cue). Wraps onto
/// several lines with large text / long translations.
class MemberBadges extends StatelessWidget {
  const MemberBadges({
    super.key,
    required this.member,
    this.isMe = false,
    this.showAgeGroup = true,
    this.alignment = WrapAlignment.start,
  });

  final Member member;

  /// Adds the "You" badge (the signed-in member).
  final bool isMe;

  final bool showAgeGroup;
  final WrapAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final ageGroup = showAgeGroup ? member.ageGroup : null;
    final ageLabel = showAgeGroup ? member.ageGroupLabel(l10n) : null;
    final status = member.accountStatus;
    final accountBadge = status.badge(l10n);
    Color fg(AppAccent accent) => context.accent(accent).foreground;

    return Wrap(
      alignment: alignment,
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        if (isMe)
          StatusChip(
            label: l10n.familyYouBadge,
            icon: AppIcons.sparkle,
            color: fg(AppAccents.brand),
          ),
        StatusChip(
          label: member.role.label(l10n),
          icon: member.role.icon,
          color: fg(member.role.accent),
        ),
        if (ageGroup != null && ageLabel != null)
          StatusChip(
            label: ageLabel,
            icon: AppIcons.birthday,
            color: fg(ageGroup.accent),
          ),
        if (accountBadge != null)
          StatusChip(
            label: accountBadge,
            icon: status.icon,
            color: status == MemberAccountStatus.invited
                ? fg(AppAccent.sky)
                : muted,
          ),
      ],
    );
  }
}
