import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/utils/formatters.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/ledger/domain/ledger_summary.dart';
import 'package:family_hub/features/ledger/presentation/ledger_labels.dart';
import 'package:family_hub/features/ledger/presentation/widgets/month_summary_card.dart';
import 'package:family_hub/features/ledger/presentation/widgets/month_switcher.dart';
import 'package:family_hub/features/ledger/presentation/widgets/on_gradient.dart';

/// Content of the Money tab's emerald gradient header (rendered inside
/// `GradientHeaderScrollView`, white on colour):
///
/// ```
/// ‹  📅 September 2026 ⌄  ›                  [≡]
/// Balance  (Family)
/// ₹1,46,170.00
/// [↙ Income ₹2,05,000]  [↗ Expenses ₹58,830]
/// ▰▰▰▱▱▱▱▱▱▱▱
/// 29% of income spent                 (✓ On track)
/// ```
///
/// The month switcher always works; while the month's [summary] loads the
/// figures are placeholders, and on an error (shown with a retry by the
/// card below the header) they stay empty.
class MoneyHeader extends ConsumerWidget {
  const MoneyHeader({
    super.key,
    required this.month,
    required this.summary,
    required this.onMonthChanged,
    required this.onOpenEntries,
  });

  final DateTime month;
  final AsyncValue<LedgerSummary> summary;
  final ValueChanged<DateTime?> onMonthChanged;
  final VoidCallback onOpenEntries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final data = summary.value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: MonthSwitcher(
                month: month,
                onGradient: true,
                onChanged: onMonthChanged,
              ),
            ),
            AppGap.hSm,
            GlassIconButton(
              icon: AppIcons.ledger,
              tooltip: l10n.ledgerEntriesTitle,
              onPressed: onOpenEntries,
            ),
          ],
        ),
        AppGap.lg,
        if (data != null)
          _Figures(summary: data)
        else if (summary.hasError)
          const _Unavailable()
        else
          const _FiguresPlaceholder(),
      ],
    );
  }
}

class _Figures extends ConsumerWidget {
  const _Figures({required this.summary});

  final LedgerSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final fmt = ref.watch(fmtProvider);
    final theme = Theme.of(context);
    final spent = spentShareOf(summary);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              l10n.ledgerSummaryNet,
              style: theme.textTheme.labelLarge?.copyWith(
                color: onGradientMuted,
              ),
            ),
            Tooltip(
              message: summary.scope.description(l10n),
              child: GlassChip(
                label: summary.scope.label(l10n),
                icon: summary.scope.icon,
              ),
            ),
          ],
        ),
        AppGap.xs,
        Semantics(
          header: true,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: MoneyText(
              summary.net,
              style: theme.textTheme.displaySmall?.copyWith(
                color: Colors.white,
                fontWeight: AppTypography.extraBold,
              ),
            ),
          ),
        ),
        AppGap.lg,
        Row(
          children: [
            Expanded(
              child: GlassStat(
                icon: AppIcons.income,
                label: l10n.ledgerSummaryIncome,
                value: fmt.money(summary.income),
              ),
            ),
            AppGap.hSm,
            Expanded(
              child: GlassStat(
                icon: AppIcons.expense,
                label: l10n.ledgerSummaryExpense,
                value: fmt.money(summary.expense),
              ),
            ),
          ],
        ),
        if (spent != null) ...[
          AppGap.lg,
          OnGradientProgressBar(value: spent.share),
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
                  color: onGradientMuted,
                ),
              ),
              if (!spent.noIncome)
                GlassChip(
                  label: spent.over
                      ? l10n.ledgerHeaderOverBudget
                      : l10n.ledgerHeaderOnTrack,
                  icon: spent.over ? AppIcons.warning : AppIcons.success,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Soft white blocks where the balance and the two totals will appear.
class _FiguresPlaceholder extends StatelessWidget {
  const _FiguresPlaceholder();

  @override
  Widget build(BuildContext context) {
    Widget block({required double height, double? widthFactor}) =>
        FractionallySizedBox(
          alignment: AlignmentDirectional.centerStart,
          widthFactor: widthFactor,
          child: Container(
            height: height,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: _placeholderOpacity),
              borderRadius: AppRadius.brMd,
            ),
          ),
        );

    return Semantics(
      label: context.l10n.commonLoading,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            block(height: AppSpacing.lg, widthFactor: 0.3),
            AppGap.sm,
            block(height: AppSpacing.xxxl - AppSpacing.sm, widthFactor: 0.6),
            AppGap.lg,
            block(height: AppSpacing.xxxl + AppSpacing.sm),
          ],
        ),
      ),
    );
  }
}

/// The month's totals could not be loaded: the header keeps its shape and
/// the card below the header says what went wrong and offers a retry.
class _Unavailable extends StatelessWidget {
  const _Unavailable();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.ledgerSummaryNet,
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(color: onGradientMuted),
        ),
        AppGap.sm,
        const ExcludeSemantics(
          child: GlassIcon(icon: AppIcons.offline, size: AppSizes.badgeMd),
        ),
      ],
    );
  }
}

/// Opacity of the loading placeholder blocks.
const double _placeholderOpacity = 0.18;
