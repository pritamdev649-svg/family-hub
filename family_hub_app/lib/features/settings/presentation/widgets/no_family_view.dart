import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/widgets/widgets.dart';

/// Empty state of member-only settings screens (profile, location) when the
/// signed-in user has no family (e.g. right after leaving it).
class NoFamilyView extends StatelessWidget {
  const NoFamilyView({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return EmptyState(
      icon: AppIcons.family,
      title: l10n.settingsNoFamilyTitle,
      message: l10n.settingsNoFamilyMessage,
    );
  }
}
