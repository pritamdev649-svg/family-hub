import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/utils/date_x.dart';
import 'package:family_hub/core/utils/formatters.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/ledger/domain/ledger_entry.dart';
import 'package:family_hub/features/ledger/domain/ledger_summary.dart';
import 'package:family_hub/features/ledger/presentation/ledger_labels.dart';

/// Income, expenses and balance of one month with its scope
/// (Family / Personal): a borderless card with the balance, solid emerald /
/// rose [IconBadge]s for income and expenses and a "spent vs income" bar.
/// Public: also used by the dashboard with `GET /dashboard`'s
/// `monthSummary`.
///
/// ```dart
/// MonthSummaryCard(LedgerSummary.fromJson(json), onTap: () => context.go(AppRoutes.money))
/// ```
class MonthSummaryCard extends ConsumerWidget {
  const MonthSummaryCard(
    this.summary, {
    super.key,
    this.onTap,
    this.showMonth = true,
  });

  final LedgerSummary summary;
  final VoidCallback? onTap;

  /// Shows the month name as the card title (hide it when a month switcher
  /// right above already names the month).
  final bool showMonth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final fmt = ref.watch(fmtProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic = context.semanticColors;
    final money = context.accent(AppAccents.money);
    final month = parseMonthKey(summary.month);
    final monthLabel = month == null ? summary.month : fmt.monthYear(month);
    final net = summary.net;
    final spent = spentShareOf(summary);

    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showMonth && monthLabel.isNotEmpty) ...[
                      Semantics(
                        header: true,
                        child: Text(
                          monthLabel,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      AppGap.xxs,
                    ],
                    MergeSemantics(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.ledgerSummaryNet,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.centerStart,
                            child: MoneyText(
                              net,
                              style: theme.textTheme.headlineMedium?.copyWith(
                                color: net < 0
                                    ? semantic.expense
                                    : scheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              AppGap.hSm,
              // At most 40 % of the row; long scope labels ellipsise.
              Flexible(
                flex: 2,
                child: Align(
                  alignment: AlignmentDirectional.topEnd,
                  child: Tooltip(
                    message: summary.scope.description(l10n),
                    child: StatusChip(
                      label: summary.scope.label(l10n),
                      icon: summary.scope.icon,
                      color: money.foreground,
                    ),
                  ),
                ),
              ),
            ],
          ),
          AppGap.lg,
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Figure(
                  type: LedgerType.income,
                  label: l10n.ledgerSummaryIncome,
                  amount: summary.income,
                ),
              ),
              AppGap.hMd,
              Expanded(
                child: _Figure(
                  type: LedgerType.expense,
                  label: l10n.ledgerSummaryExpense,
                  amount: summary.expense,
                ),
              ),
            ],
          ),
          if (summary.isEmpty && monthLabel.isNotEmpty) ...[
            AppGap.md,
            Text(
              l10n.ledgerSummaryEmpty(monthLabel),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ] else if (spent != null) ...[
            AppGap.lg,
            AppProgressBar(
              value: spent.share,
              color: spent.over ? AppAccents.expense.base : money.base,
            ),
            AppGap.sm,
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  spent.label(l10n, fmt),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (!spent.noIncome)
                  StatusChip(
                    label: spent.over
                        ? l10n.ledgerHeaderOverBudget
                        : l10n.ledgerHeaderOnTrack,
                    icon: spent.over ? AppIcons.warning : AppIcons.success,
                    color: context
                        .accent(
                          spent.over ? AppAccents.expense : AppAccents.income,
                        )
                        .foreground,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Solid emerald / rose badge, label and amount.
class _Figure extends StatelessWidget {
  const _Figure({
    required this.type,
    required this.label,
    required this.amount,
  });

  final LedgerType type;
  final String label;
  final double amount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MergeSemantics(
      child: Row(
        children: [
          ExcludeSemantics(
            child: IconBadge(
              icon: type.icon,
              accent: type.accent,
              size: AppSizes.badgeSm,
            ),
          ),
          AppGap.hSm,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: MoneyText(
                    amount,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: context.accent(type.accent).foreground,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// How much of a month's income was spent, for the "spent vs income" bars
/// (Money header, [MonthSummaryCard]).
@immutable
class SpentShare {
  const SpentShare({
    required this.share,
    required this.over,
    this.noIncome = false,
  });

  /// Expenses ÷ income (may exceed 1; bars clamp it). 1 when there was
  /// spending but no income.
  final double share;

  /// More was spent than came in.
  final bool over;

  /// Money was spent but no income is recorded for the month.
  final bool noIncome;

  /// "29% of income spent" / "No income recorded yet".
  String label(AppLocalizations l10n, Fmt fmt) => noIncome
      ? l10n.ledgerHeaderNoIncome
      : l10n.ledgerHeaderSpentShare(fmt.percent(share));
}

/// Null for a month without income and expenses (nothing to compare).
SpentShare? spentShareOf(LedgerSummary summary) {
  final income = summary.income;
  final expense = summary.expense;
  if (income <= 0 && expense <= 0) return null;
  if (income <= 0) {
    return const SpentShare(share: 1, over: true, noIncome: true);
  }
  return SpentShare(share: expense / income, over: expense > income);
}
