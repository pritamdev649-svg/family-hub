import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/utils/formatters.dart';

/// Direction of money for [MoneyText] colouring and sign.
enum LedgerFlow { income, expense, neutral }

/// Formats an amount in the family currency and locale (via [Fmt]).
///
/// * [LedgerFlow.income]  → `+₹1,250.50` in the semantic income colour.
/// * [LedgerFlow.expense] → `−₹1,250.50` in the semantic expense colour.
/// * `null` / [LedgerFlow.neutral] → the amount as-is (negative stays
///   negative), in the inherited / [style] colour.
///
/// Digits are tabular so amounts line up in lists.
class MoneyText extends ConsumerWidget {
  const MoneyText(this.amount, {super.key, this.flow, this.style});

  final num amount;
  final LedgerFlow? flow;
  final TextStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = ref.watch(fmtProvider);
    final semantic = context.semanticColors;
    final safe = amount.isFinite ? amount : 0;

    final (String text, Color? color) = switch (flow) {
      // A zero amount never gets a sign ("+₹0.00" / "−₹0.00" look odd).
      LedgerFlow.income when safe != 0 => (
        fmt.money(safe.abs(), signed: true),
        semantic.income,
      ),
      LedgerFlow.expense when safe != 0 => (
        fmt.money(-safe.abs(), signed: true),
        semantic.expense,
      ),
      _ => (fmt.money(safe), null),
    };

    final base = (style ?? const TextStyle()).merge(
      AppTypography.tabularFigures,
    );
    // No maxLines / ellipsis: an amount must never be silently truncated.
    // Callers that need to fit a narrow slot can wrap it in a `FittedBox`.
    return Text(
      text,
      style: color == null ? base : base.copyWith(color: color),
    );
  }
}
