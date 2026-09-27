import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/utils/formatters.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/ledger/domain/ledger_entry.dart';
import 'package:family_hub/features/ledger/domain/ledger_summary.dart';
import 'package:family_hub/features/ledger/presentation/ledger_labels.dart';
import 'package:family_hub/features/ledger/presentation/widgets/type_toggle.dart';

/// The biggest categories of a month (top [maxCategories] + "Other"), each
/// with its solid colour badge and a bar in the same colour; switchable
/// between expenses and income.
class CategoryBreakdownCard extends StatefulWidget {
  const CategoryBreakdownCard(
    this.summary, {
    super.key,
    this.maxCategories = 6,
  });

  final LedgerSummary summary;
  final int maxCategories;

  @override
  State<CategoryBreakdownCard> createState() => _CategoryBreakdownCardState();
}

class _CategoryBreakdownCardState extends State<CategoryBreakdownCard> {
  /// The person's choice; null = automatic (see [_type]).
  LedgerType? _chosen;

  /// Expenses by default, income when the month has income but no expenses
  /// (instead of an empty "No expenses" card).
  LedgerType get _type {
    final chosen = _chosen;
    if (chosen != null) return chosen;
    final summary = widget.summary;
    final onlyIncome =
        summary.categoriesOf(LedgerType.expense).isEmpty &&
        summary.categoriesOf(LedgerType.income).isNotEmpty;
    return onlyIncome ? LedgerType.income : LedgerType.expense;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final type = _type;
    final breakdown = widget.summary.breakdown(
      type,
      maxItems: widget.maxCategories,
    );

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    AppIcons.summary,
                    size: AppSizes.iconSm,
                    color: context.accent(AppAccents.money).foreground,
                  ),
                  AppGap.hSm,
                  Flexible(
                    child: Semantics(
                      header: true,
                      child: Text(
                        l10n.ledgerBreakdownTitle,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                  ),
                ],
              ),
              LedgerTypeToggle(
                dense: true,
                types: const [LedgerType.expense, LedgerType.income],
                selected: type,
                onChanged: (t) => setState(() => _chosen = t),
              ),
            ],
          ),
          AppGap.lg,
          if (breakdown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Text(
                type.isIncome
                    ? l10n.ledgerBreakdownEmptyIncome
                    : l10n.ledgerBreakdownEmptyExpense,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else ...[
            for (var i = 0; i < breakdown.items.length; i++) ...[
              if (i > 0) AppGap.lg,
              _CategoryBar(
                icon: breakdown.items[i].category.icon,
                accent: breakdown.items[i].category.accent,
                label: breakdown.items[i].category.label(l10n),
                amount: breakdown.items[i].amount,
                share: breakdown.shareOf(breakdown.items[i].amount),
              ),
            ],
            if (breakdown.rest > 0) ...[
              AppGap.lg,
              _CategoryBar(
                icon: AppIcons.category,
                accent: AppAccents.brand,
                soft: true,
                label: l10n.ledgerBreakdownOther,
                amount: breakdown.rest,
                share: breakdown.shareOf(breakdown.rest),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// One category: solid [IconBadge] in the category's colour, name, amount,
/// share and a bar in the same colour.
class _CategoryBar extends ConsumerWidget {
  const _CategoryBar({
    required this.icon,
    required this.accent,
    required this.label,
    required this.amount,
    required this.share,
    this.soft = false,
  });

  final IconData icon;
  final AppAccent accent;
  final String label;
  final double amount;
  final double share;

  /// Pale badge for the catch-all "Other" row.
  final bool soft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = ref.watch(fmtProvider);
    final theme = Theme.of(context);
    final percent = fmt.percent(share);

    return Semantics(
      container: true,
      label: context.l10n.ledgerBreakdownItemSemantics(
        label,
        fmt.money(amount),
        percent,
      ),
      child: ExcludeSemantics(
        child: Row(
          children: [
            IconBadge(
              icon: icon,
              accent: accent,
              size: AppSizes.badgeSm,
              soft: soft,
            ),
            AppGap.hMd,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Label and figures share a line when they fit and wrap
                  // (figures below the label) with large text / narrow
                  // screens.
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xxs,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(label, style: theme.textTheme.titleSmall),
                      Wrap(
                        spacing: AppSpacing.sm,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          MoneyText(amount, style: theme.textTheme.labelLarge),
                          Text(
                            percent,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: context.accent(accent).foreground,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  AppGap.xs,
                  AppProgressBar(
                    value: share,
                    color: accent.base,
                    height: AppSizes.progressBar - AppSpacing.xxs,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
