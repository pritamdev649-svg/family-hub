import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/ledger/domain/ledger_entry.dart';
import 'package:family_hub/features/ledger/presentation/ledger_labels.dart';
import 'package:family_hub/features/ledger/presentation/ledger_open_guard.dart';

/// "Add entry" floating button: asks for income or expense, then opens the
/// entry form (`/money/entries/new?type=`). A double tap opens one sheet.
class AddEntryFab extends StatefulWidget {
  const AddEntryFab({super.key, this.heroTag});

  /// Distinct tag when two screens with a FAB can be on the stack.
  final Object? heroTag;

  @override
  State<AddEntryFab> createState() => _AddEntryFabState();
}

class _AddEntryFabState extends State<AddEntryFab> with LedgerOpenGuard {
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Solid money accent (white on emerald) so the button belongs to the
    // Money screens rather than the brand-indigo default.
    return FloatingActionButton.extended(
      heroTag: widget.heroTag,
      onPressed: () => guardedOpen(() => openAddLedgerEntry(context)),
      backgroundColor: AppAccents.money.dark,
      foregroundColor: Colors.white,
      icon: const Icon(AppIcons.add),
      label: Text(l10n.ledgerAddEntry),
    );
  }
}

/// Shows the income / expense choice and opens the form for the picked type.
Future<void> openAddLedgerEntry(BuildContext context) async {
  final type = await showModalBottomSheet<LedgerType>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final l10n = sheetContext.l10n;
      final theme = Theme.of(sheetContext);
      Widget option(LedgerType type, String hint) => Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xs,
        ),
        child: AppCard(
          accent: type.accent,
          padding: const EdgeInsets.all(AppSpacing.md),
          onTap: () => Navigator.of(sheetContext).pop(type),
          child: Row(
            children: [
              ExcludeSemantics(
                child: IconBadge(icon: type.icon, accent: type.accent),
              ),
              AppGap.hMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      type.addLabel(l10n),
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: sheetContext.accent(type.accent).onContainer,
                      ),
                    ),
                    AppGap.xxs,
                    Text(
                      hint,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              AppGap.hSm,
              Icon(
                AppIcons.chevron,
                size: AppSizes.iconSm,
                color: sheetContext.accent(type.accent).foreground,
              ),
            ],
          ),
        ),
      );
      return SingleChildScrollView(
        padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Semantics(
                header: true,
                child: Text(
                  l10n.ledgerAddEntryChooseType,
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ),
            AppGap.md,
            option(LedgerType.income, l10n.ledgerAddIncomeHint),
            option(LedgerType.expense, l10n.ledgerAddExpenseHint),
          ],
        ),
      );
    },
  );
  if (type == null || !context.mounted) return;
  await context.push<bool>(AppRoutes.ledgerEntryNew(type: type.wireName));
}
