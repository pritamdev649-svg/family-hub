import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/utils/formatters.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/ledger/domain/ledger_entry.dart';
import 'package:family_hub/features/ledger/presentation/ledger_labels.dart';

/// One ledger row in the "transaction list" style: solid category
/// [IconBadge], note (or category) in bold, category · date · member below
/// and the signed amount at the end (income emerald `+`, expense rose `−`).
/// Tapping opens [onTap] (usually the entry details sheet).
class LedgerEntryTile extends ConsumerWidget {
  /// Largest share of the row width the amount may take.
  static const _maxAmountShare = 0.45;

  const LedgerEntryTile(
    this.entry, {
    super.key,
    this.onTap,
    this.showMember = true,
  });

  final LedgerEntry entry;
  final VoidCallback? onTap;

  /// Hide the member (e.g. when every row belongs to the same person).
  final bool showMember;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final fmt = ref.watch(fmtProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final categoryLabel = entry.category.label(l10n);
    final title = entry.note ?? categoryLabel;
    final date = fmt.weekdayDate(entry.date);
    final member = entry.memberName.isEmpty ? null : entry.memberName;
    final subtitle = showMember && member != null
        ? l10n.ledgerEntryTileSubtitle(date, member)
        : date;

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSizes.minTapTarget),
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            children: [
              ExcludeSemantics(
                child: IconBadge(
                  icon: entry.category.icon,
                  accent: entry.category.accent,
                ),
              ),
              AppGap.hMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    AppGap.xxs,
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xxs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (entry.note != null)
                          Text(
                            categoryLabel,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: context
                                  .accent(entry.category.accent)
                                  .foreground,
                            ),
                          ),
                        Text(
                          subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        if (entry.isGoalLinked)
                          StatusChip(
                            label: l10n.ledgerEntryGoalBadge,
                            icon: AppIcons.goal,
                            color: context.accent(AppAccents.goals).foreground,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              AppGap.hMd,
              // The amount keeps its natural size unless it would take more
              // than [_maxAmountShare] of the row (large text, narrow phone,
              // huge amounts); then it scales down instead of overflowing.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth:
                      constraints.maxWidth * LedgerEntryTile._maxAmountShare,
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerEnd,
                  child: MoneyText(
                    entry.amount,
                    flow: entry.type.flow,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: AppTypography.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
