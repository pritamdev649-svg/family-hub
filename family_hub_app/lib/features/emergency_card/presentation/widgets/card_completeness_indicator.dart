import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/emergency_card/domain/emergency_card.dart';
import 'package:family_hub/features/emergency_card/presentation/emergency_card_labels.dart';
import 'package:family_hub/features/emergency_card/presentation/emergency_card_style.dart';

/// Progress bar + label telling how many key details of [card] are filled
/// in (blood group, callable contact, doctor, insurance), and which ones are
/// missing: emerald when complete, amber while details are missing, neutral
/// when the card was never filled in.
class CardCompletenessIndicator extends StatelessWidget {
  const CardCompletenessIndicator({super.key, required this.card});

  final EmergencyCard card;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final completeness = card.completeness;
    final progress = card.progress;

    final ({Color bar, Color text, IconData icon}) style = switch (progress) {
      EmergencyCardProgress.notStarted => (
        bar: scheme.onSurfaceVariant,
        text: scheme.onSurfaceVariant,
        icon: AppIcons.info,
      ),
      EmergencyCardProgress.complete => (
        bar: context.accent(EmergencyCardAccents.complete).base,
        text: context.accent(EmergencyCardAccents.complete).foreground,
        icon: AppIcons.success,
      ),
      EmergencyCardProgress.partial => (
        bar: context.accent(EmergencyCardAccents.incomplete).base,
        text: context.accent(EmergencyCardAccents.incomplete).foreground,
        icon: AppIcons.warning,
      ),
    };

    final missing = progress == EmergencyCardProgress.partial
        ? l10n.emergencyCardMissing(
            completeness.missing
                .map((s) => s.label(l10n))
                .join(l10n.emergencyCardListSeparator),
          )
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppProgressBar(
          value: progress == EmergencyCardProgress.notStarted
              ? 0
              : completeness.ratio,
          color: style.bar,
        ),
        AppGap.sm,
        Row(
          children: [
            Icon(style.icon, size: AppSizes.iconXs, color: style.text),
            AppGap.hXs,
            Expanded(
              child: Text(
                card.progressLabel(l10n),
                style: theme.textTheme.labelMedium?.copyWith(color: style.text),
              ),
            ),
          ],
        ),
        if (missing != null) ...[
          AppGap.xxs,
          Text(
            missing,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
