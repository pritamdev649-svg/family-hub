import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/shared/l10n/shared_labels.dart';
import 'package:family_hub/shared/models/models.dart';

/// Content of the full-bleed brand gradient header of the More tab (rendered
/// inside [GradientHeaderScrollView], so text and icons are white): a small
/// "More" label, then the member's avatar in a white ring, their name,
/// designation (or role), family name and a frosted "Edit profile" pill.
///
/// The whole profile block is one tap target that opens the profile editor
/// ([onTap]); without a family profile ([onTap] `null`) it is plain text and
/// shows the account [email] instead.
class ProfileHeader extends StatelessWidget {
  const ProfileHeader({
    super.key,
    required this.name,
    this.member,
    this.family,
    this.email,
    this.onTap,
  });

  /// Display name (member name, else account name).
  final String name;
  final Member? member;
  final Family? family;

  /// Account email, shown when there is no family profile.
  final String? email;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final onGradient = Colors.white.withValues(alpha: 0.85);
    final title = member?.titleOrRole(l10n);
    final familyName = family?.name.trim();
    final accountEmail = member == null ? email?.trim() : null;

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.headlineSmall?.copyWith(color: Colors.white),
        ),
        if (title != null && title.isNotEmpty) ...[
          AppGap.xxs,
          Text(
            title,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: Colors.white,
              fontWeight: AppTypography.semiBold,
            ),
          ),
        ],
        if (familyName != null && familyName.isNotEmpty) ...[
          AppGap.xs,
          Row(
            children: [
              Icon(AppIcons.family, size: AppSizes.iconXs, color: onGradient),
              AppGap.hXs,
              Flexible(
                child: Text(
                  familyName,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: onGradient,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (accountEmail != null && accountEmail.isNotEmpty) ...[
          AppGap.xs,
          Text(
            accountEmail,
            style: theme.textTheme.bodyMedium?.copyWith(color: onGradient),
          ),
        ],
        if (onTap != null) ...[
          AppGap.md,
          _GlassPill(icon: AppIcons.edit, label: l10n.settingsEditProfile),
        ],
      ],
    );

    Widget profile = Row(
      children: [
        _RingedAvatar(name: name, avatarUrl: member?.avatarUrl),
        AppGap.hLg,
        Expanded(child: details),
      ],
    );

    if (onTap != null) {
      profile = MergeSemantics(
        child: Semantics(
          button: true,
          hint: l10n.settingsProfileHeaderHint,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              borderRadius: AppRadius.brLg,
              splashColor: Colors.white.withValues(alpha: 0.16),
              highlightColor: Colors.white.withValues(alpha: 0.08),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xs),
                child: profile,
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Row(
            children: [
              Icon(AppIcons.more, size: AppSizes.iconSm, color: onGradient),
              AppGap.hXs,
              Flexible(
                child: Text(
                  l10n.navMore,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: onGradient,
                  ),
                ),
              ),
            ],
          ),
        ),
        AppGap.md,
        profile,
      ],
    );
  }
}

/// Member avatar inside a frosted halo and a solid white ring, for use on
/// gradients (no border strokes — the ring is a white disc behind the
/// avatar).
class _RingedAvatar extends StatelessWidget {
  const _RingedAvatar({required this.name, required this.avatarUrl});

  final String name;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.2),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xxs),
              child: MemberAvatar(
                name: name,
                avatarUrl: avatarUrl,
                radius: AppSizes.avatarXl,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small frosted "button look" pill on the gradient. The surrounding
/// profile block handles the tap (one target, one screen-reader node).
class _GlassPill extends StatelessWidget {
  const _GlassPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: AppRadius.brPill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: AppSizes.iconXs, color: Colors.white),
          AppGap.hXs,
          Flexible(
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
