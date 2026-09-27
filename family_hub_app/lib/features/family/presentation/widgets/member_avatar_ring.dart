import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/family/presentation/family_style.dart';
import 'package:family_hub/shared/models/member.dart';

/// [MemberAvatar] inside a colourful ring: by default a gradient in the
/// member's own stable accent ([FamilyStyle.accentFor]) with a thin gap in
/// the card colour; [MemberAvatarRing.onGradient] draws a frosted white
/// ring for the blue header instead.
class MemberAvatarRing extends StatelessWidget {
  const MemberAvatarRing({
    super.key,
    required this.member,
    this.radius = AppSizes.avatarLg,
  }) : _onGradient = false;

  /// White ring without a gap, for use on a gradient.
  const MemberAvatarRing.onGradient({
    super.key,
    required this.member,
    this.radius = AppSizes.avatarXl,
  }) : _onGradient = true;

  final Member member;
  final double radius;
  final bool _onGradient;

  @override
  Widget build(BuildContext context) {
    final avatar = MemberAvatar(
      name: member.name,
      avatarUrl: member.avatarUrl,
      radius: radius,
    );
    if (_onGradient) {
      return DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: FamilyStyle.glassRing),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: avatar,
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppGradients.of(FamilyStyle.accentFor(member.id)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxs),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: context.semanticColors.card,
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxs),
            child: avatar,
          ),
        ),
      ),
    );
  }
}
