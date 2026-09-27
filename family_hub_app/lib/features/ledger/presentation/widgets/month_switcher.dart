import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/utils/date_x.dart';
import 'package:family_hub/core/utils/formatters.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/ledger/application/ledger_providers.dart';
import 'package:family_hub/features/ledger/presentation/widgets/on_gradient.dart';

/// `‹  September 2026 ⌄  ›` — steps through months, never past the current
/// month. Tapping the label opens [showLedgerMonthPicker].
///
/// [month] null means "all months" (only when [allowAllMonths]); the arrows
/// then start from the current month.
///
/// With [onGradient] the arrows are frosted white buttons and the label is
/// white (the Money tab's gradient header); otherwise the switcher sits on a
/// borderless card-coloured pill.
class MonthSwitcher extends ConsumerWidget {
  const MonthSwitcher({
    super.key,
    required this.month,
    required this.onChanged,
    this.allowAllMonths = false,
    this.onGradient = false,
  });

  final DateTime? month;
  final ValueChanged<DateTime?> onChanged;
  final bool allowAllMonths;
  final bool onGradient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final fmt = ref.watch(fmtProvider);
    final theme = Theme.of(context);
    final current = month;
    final label = current == null
        ? l10n.ledgerAllMonths
        : fmt.monthYear(current);
    final base = current ?? currentLedgerMonth();
    final canNext = current != null && canGoToNextMonth(current);

    Future<void> pick() async {
      final picked = await showLedgerMonthPicker(
        context,
        selected: current,
        allowAllMonths: allowAllMonths,
      );
      if (picked == null) return;
      onChanged(picked.month);
    }

    void previous() => onChanged(current == null ? base : base.addMonths(-1));
    final VoidCallback? next = canNext
        ? () => onChanged(base.addMonths(1))
        : null;

    final textColor = onGradient ? Colors.white : theme.colorScheme.onSurface;
    final mutedColor = onGradient
        ? onGradientMuted
        : theme.colorScheme.onSurfaceVariant;

    Widget arrow(IconData icon, String tooltip, VoidCallback? onPressed) =>
        onGradient
        ? GlassIconButton(icon: icon, tooltip: tooltip, onPressed: onPressed)
        : IconButton(
            tooltip: tooltip,
            icon: Icon(icon, size: AppSizes.iconSm),
            color: context.accent(AppAccents.money).foreground,
            onPressed: onPressed,
          );

    final row = Row(
      children: [
        arrow(AppIcons.chevronLeft, l10n.ledgerMonthPrevious, previous),
        AppGap.hXs,
        Expanded(
          child: Semantics(
            button: true,
            hint: l10n.ledgerMonthPick,
            child: InkWell(
              borderRadius: AppRadius.brPill,
              onTap: pick,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: AppSizes.minTapTarget,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: textColor,
                          ),
                        ),
                      ),
                      AppGap.hXs,
                      Icon(
                        AppIcons.expand,
                        size: AppSizes.iconXs,
                        color: mutedColor,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        AppGap.hXs,
        arrow(AppIcons.chevron, l10n.ledgerMonthNext, next),
      ],
    );

    if (onGradient) return row;
    return Material(
      color: context.semanticColors.card,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
        child: row,
      ),
    );
  }
}

/// Result of [showLedgerMonthPicker]: a month, or "all months" (null).
class LedgerMonthChoice {
  const LedgerMonthChoice(this.month);

  final DateTime? month;
}

/// The month picker sheet never covers more than this share of the screen.
const _pickerMaxHeightFactor = 0.7;

/// How many months back the picker lists (older months stay reachable with
/// the switcher's back arrow).
const ledgerMonthPickerSpan = 36;

/// Bottom sheet listing the current month and the [ledgerMonthPickerSpan]
/// months before it (plus [selected] if it is older), newest first.
/// Returns null when dismissed.
Future<LedgerMonthChoice?> showLedgerMonthPicker(
  BuildContext context, {
  DateTime? selected,
  bool allowAllMonths = false,
}) {
  return showModalBottomSheet<LedgerMonthChoice>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) =>
        _MonthPickerSheet(selected: selected, allowAllMonths: allowAllMonths),
  );
}

class _MonthPickerSheet extends ConsumerWidget {
  const _MonthPickerSheet({
    required this.selected,
    required this.allowAllMonths,
  });

  final DateTime? selected;
  final bool allowAllMonths;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final fmt = ref.watch(fmtProvider);
    final theme = Theme.of(context);
    final current = currentLedgerMonth();
    final sel = selected == null
        ? null
        : DateTime(selected!.year, selected!.month);

    var span = ledgerMonthPickerSpan;
    if (sel != null) {
      final back = (current.year - sel.year) * 12 + current.month - sel.month;
      if (back > span) span = back;
    }
    final months = [for (var i = 0; i <= span; i++) current.addMonths(-i)];

    final money = context.accent(AppAccents.money);
    Widget tile({
      required String label,
      required bool isSelected,
      required LedgerMonthChoice choice,
      String? subtitle,
    }) => Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      child: ListTile(
        leading: IconBadge(
          icon: AppIcons.calendar,
          accent: AppAccents.money,
          size: AppSizes.badgeSm,
          soft: !isSelected,
        ),
        title: Text(label),
        subtitle: subtitle == null ? null : Text(subtitle),
        selected: isSelected,
        selectedColor: money.onContainer,
        selectedTileColor: money.container,
        trailing: isSelected ? const Icon(AppIcons.check) : null,
        onTap: () => Navigator.of(context).pop(choice),
      ),
    );

    final height = MediaQuery.sizeOf(context).height;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: height * _pickerMaxHeightFactor),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Semantics(
              header: true,
              child: Text(
                l10n.ledgerMonthPick,
                style: theme.textTheme.titleMedium,
              ),
            ),
          ),
          AppGap.sm,
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: months.length + (allowAllMonths ? 1 : 0),
              itemBuilder: (context, index) {
                if (allowAllMonths && index == 0) {
                  return tile(
                    label: l10n.ledgerAllMonths,
                    isSelected: sel == null,
                    choice: const LedgerMonthChoice(null),
                  );
                }
                final m = months[index - (allowAllMonths ? 1 : 0)];
                return tile(
                  label: fmt.monthYear(m),
                  subtitle: m == current ? l10n.ledgerThisMonth : null,
                  isSelected: sel != null && m.isSameDay(sel),
                  choice: LedgerMonthChoice(m),
                );
              },
            ),
          ),
          AppGap.lg,
        ],
      ),
    );
  }
}
