import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/widgets/widgets.dart';

/// Shown instead of a member's details or edit form when the member no
/// longer exists: removed by an admin (also while the screen was open), or
/// an old / mistyped link (e.g. a notification about a removed member).
/// Offers "Back", or "View members" when there is nothing to go back to.
class MemberGoneView extends StatelessWidget {
  const MemberGoneView({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final canPop = context.canPop();
    return EmptyState(
      icon: AppIcons.members,
      title: l10n.familyMemberGoneTitle,
      message: l10n.familyMemberGoneMessage,
      action: AppButton(
        label: canPop ? l10n.commonBack : l10n.familyViewMembers,
        icon: canPop ? AppIcons.back : AppIcons.members,
        variant: AppButtonVariant.secondary,
        expand: false,
        onPressed: () => canPop ? context.pop() : context.go(AppRoutes.members),
      ),
    );
  }
}
