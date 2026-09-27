import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/family/presentation/widgets/member_avatar_ring.dart';
import 'package:family_hub/features/family/presentation/widgets/member_badges.dart';
import 'package:family_hub/shared/models/member.dart';

/// A member card: avatar in the member's colour ring, name, designation and
/// badges (role, age group, "no account"). Borderless; grows with large
/// text instead of clipping.
class MemberTile extends StatelessWidget {
  const MemberTile({
    super.key,
    required this.member,
    this.isMe = false,
    this.onTap,
  });

  final Member member;
  final bool isMe;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final designation = member.designation;

    return Semantics(
      button: onTap != null,
      onTapHint: onTap == null ? null : context.l10n.familyOpenMemberHint,
      child: AppCard(
        onTap: onTap,
        child: Row(
          children: [
            MemberAvatarRing(member: member),
            AppGap.hMd,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.name,
                    style: theme.textTheme.titleSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (designation != null) ...[
                    AppGap.xxs,
                    Text(
                      designation,
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  AppGap.sm,
                  MemberBadges(member: member, isMe: isMe),
                ],
              ),
            ),
            if (onTap != null) ...[
              AppGap.hSm,
              Icon(AppIcons.chevron, size: AppSizes.iconSm, color: muted),
            ],
          ],
        ),
      ),
    );
  }
}
