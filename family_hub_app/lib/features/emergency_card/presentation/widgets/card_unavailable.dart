import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/emergency_card/presentation/emergency_card_style.dart';
import 'package:family_hub/features/emergency_card/presentation/widgets/emergency_section.dart';

/// Shown instead of a card the server answers with `404 NOT_FOUND`: the
/// member was removed from the family (while the screen was open, or before
/// an old link / notification was opened) or the id is wrong. A retry would
/// never help, so there is none: the button goes back, or — when there is
/// nothing to go back to — to the list of every card.
///
/// Below a gradient header it is a card in the content column; with
/// [centered] (plain screens such as the form) it sits mid-screen.
class EmergencyCardUnavailable extends StatelessWidget {
  const EmergencyCardUnavailable({super.key, this.centered = false});

  final bool centered;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final canPop = context.canPop();
    return EmergencyStateCard(
      icon: AppIcons.emergencyCardOutlined,
      accent: EmergencyCardAccents.module,
      title: l10n.emergencyCardNotFoundTitle,
      message: l10n.emergencyCardNotFoundMessage,
      centered: centered,
      action: AppButton(
        label: canPop ? l10n.commonBack : l10n.emergencyCardBackToList,
        icon: canPop ? AppIcons.back : AppIcons.emergencyCard,
        variant: AppButtonVariant.secondary,
        expand: false,
        onPressed: () =>
            canPop ? context.pop() : context.go(AppRoutes.emergencyCards),
      ),
    );
  }
}
