import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/utils/date_x.dart';
import 'package:family_hub/core/utils/formatters.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/ledger/application/ledger_providers.dart';
import 'package:family_hub/features/ledger/domain/ledger_entry.dart';
import 'package:family_hub/features/ledger/domain/ledger_summary.dart';
import 'package:family_hub/features/ledger/domain/savings_goal.dart';
import 'package:family_hub/features/ledger/presentation/ledger_open_guard.dart';
import 'package:family_hub/features/ledger/presentation/widgets/add_entry_fab.dart';
import 'package:family_hub/features/ledger/presentation/widgets/category_breakdown_card.dart';
import 'package:family_hub/features/ledger/presentation/widgets/entry_detail_sheet.dart';
import 'package:family_hub/features/ledger/presentation/widgets/goal_carousel.dart';
import 'package:family_hub/features/ledger/presentation/widgets/ledger_entry_tile.dart';
import 'package:family_hub/features/ledger/presentation/widgets/money_header.dart';
import 'package:family_hub/features/ledger/presentation/widgets/records_only_note.dart';
import 'package:family_hub/features/ledger/presentation/widgets/section_empty_card.dart';
import 'package:family_hub/shared/providers/shared_providers.dart';

/// Room below the last section so the "Add entry" button never covers it.
const _fabClearance = SizedBox(height: AppSpacing.xxxl + AppSpacing.xl);

/// The Money tab (docs/12-DESIGN_LANGUAGE.md §3b): a full-bleed emerald
/// header behind the transparent status bar with the month switcher, the
/// month's balance, income / expense pills and a "spent vs income" bar
/// ([MoneyHeader]); below it the category breakdown, the savings goals as a
/// carousel of gradient cards and the month's latest entries.
class MoneyScreen extends ConsumerStatefulWidget {
  const MoneyScreen({super.key});

  @override
  ConsumerState<MoneyScreen> createState() => _MoneyScreenState();
}

class _MoneyScreenState extends ConsumerState<MoneyScreen>
    with LedgerOpenGuard {
  bool _showArchived = false;

  void _push(String location) => guardedOpen(() => context.push(location));

  Future<void> _refresh(String monthKey) async {
    await Future.wait<Object?>([
      ref.refresh(ledgerSummaryProvider(monthKey).future),
      ref.refresh(recentLedgerEntriesProvider(monthKey).future),
      ref.refresh(savingsGoalsProvider.future),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final fmt = ref.watch(fmtProvider);
    final month = ref.watch(selectedLedgerMonthProvider);
    final monthKey = month.monthKey;
    final isAdmin = ref.watch(isAdminProvider);
    final summary = ref.watch(ledgerSummaryProvider(monthKey));
    final recent = ref.watch(recentLedgerEntriesProvider(monthKey));
    final goals = ref.watch(savingsGoalsProvider);

    // A month without any entries says so once (in the first card) instead
    // of an empty breakdown *and* an empty "Recent entries" section.
    final monthIsEmpty = summary.value?.isEmpty ?? false;
    final hideRecent = monthIsEmpty && (recent.value?.isEmpty ?? false);

    return Scaffold(
      floatingActionButton: const AddEntryFab(heroTag: 'money-add-entry'),
      // The gradient header replaces the app bar; keep a screen-reader
      // title for the tab.
      body: Semantics(
        label: l10n.ledgerTitle,
        explicitChildNodes: true,
        child: GradientHeaderScrollView(
          gradient: AppGradients.headerOf(AppAccents.money),
          onRefresh: () => _refresh(monthKey),
          header: MoneyHeader(
            month: month,
            summary: summary,
            onMonthChanged: (m) => ref
                .read(selectedLedgerMonthProvider.notifier)
                .select(m ?? currentLedgerMonth()),
            onOpenEntries: () => _push(AppRoutes.ledgerEntries),
          ),
          children: [
            // First card overlaps the header's rounded bottom edge.
            _SummaryCard(
              summary: summary,
              monthLabel: fmt.monthYear(month),
              onRetry: () => ref.invalidate(ledgerSummaryProvider(monthKey)),
            ),
            AppGap.xl,
            SectionHeader(
              title: l10n.ledgerGoalsTitle,
              icon: AppIcons.goal,
              accent: AppAccents.goals,
              actionLabel: isAdmin ? l10n.ledgerNewGoal : null,
              onAction: isAdmin ? () => _push(AppRoutes.goalNew) : null,
            ),
            AsyncValueView<List<SavingsGoal>>(
              value: goals,
              onRetry: () => ref.invalidate(savingsGoalsProvider),
              isEmpty: (list) => list.isEmpty,
              empty: SectionEmptyCard(
                icon: AppIcons.goalOutlined,
                accent: AppAccents.goals,
                title: l10n.ledgerGoalsEmpty,
                message: isAdmin
                    ? l10n.ledgerGoalsEmptyAdmin
                    : l10n.ledgerGoalsEmptyMember,
                action: isAdmin
                    ? AppButton(
                        label: l10n.ledgerNewGoal,
                        icon: AppIcons.add,
                        variant: AppButtonVariant.tonal,
                        expand: false,
                        onPressed: () => _push(AppRoutes.goalNew),
                      )
                    : null,
              ),
              data: (list) => _Goals(
                goals: list,
                showArchived: _showArchived,
                onToggleArchived: () =>
                    setState(() => _showArchived = !_showArchived),
              ),
            ),
            if (!hideRecent) ...[
              AppGap.xl,
              SectionHeader(
                title: l10n.ledgerRecentTitle,
                icon: AppIcons.ledger,
                accent: AppAccents.money,
                actionLabel: l10n.commonSeeAll,
                onAction: () => _push(AppRoutes.ledgerEntries),
              ),
              AsyncValueView<List<LedgerEntry>>(
                value: recent,
                onRetry: () =>
                    ref.invalidate(recentLedgerEntriesProvider(monthKey)),
                isEmpty: (list) => list.isEmpty,
                empty: SectionEmptyCard(
                  icon: AppIcons.ledger,
                  title: l10n.ledgerRecentEmpty,
                  message: l10n.ledgerRecentEmptyMessage,
                ),
                data: (list) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < list.length; i++) ...[
                      if (i > 0) AppGap.sm,
                      LedgerEntryTile(
                        list[i],
                        key: ValueKey('recent-${list[i].id}'),
                        onTap: () => guardedOpen(
                          () => showLedgerEntrySheet(context, list[i]),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            AppGap.lg,
            const RecordsOnlyNote(),
            _fabClearance,
          ],
        ),
      ),
    );
  }
}

/// The card right under the header: the category breakdown, or — for a
/// month without entries, while loading or after an error — a card of the
/// same place and shape, so the header always has a card overlapping it.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.summary,
    required this.monthLabel,
    required this.onRetry,
  });

  final AsyncValue<LedgerSummary> summary;
  final String monthLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final error = summary.error;
    if (!summary.hasValue && error != null) {
      // Same error view (with retry) AsyncValueView would show, on a card
      // so it reads well where it overlaps the header.
      return AppCard(
        child: ErrorView(
          error: error,
          onRetry: onRetry,
          isRetrying: summary.isLoading,
        ),
      );
    }
    return AsyncValueView<LedgerSummary>(
      value: summary,
      onRetry: onRetry,
      loading: const AppCard(child: LoadingView()),
      isEmpty: (s) => s.isEmpty,
      empty: SectionEmptyCard(
        icon: AppIcons.ledger,
        title: l10n.ledgerSummaryEmpty(monthLabel),
        message: l10n.ledgerRecentEmptyMessage,
      ),
      data: (s) => CategoryBreakdownCard(s),
    );
  }
}

/// Active goals as a carousel; archived ones behind a toggle.
class _Goals extends StatelessWidget {
  const _Goals({
    required this.goals,
    required this.showArchived,
    required this.onToggleArchived,
  });

  final List<SavingsGoal> goals;
  final bool showArchived;
  final VoidCallback onToggleArchived;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final visible = [
      for (final g in goals)
        if (!g.isArchived) g,
    ];
    final archived = [
      for (final g in goals)
        if (g.isArchived) g,
    ];
    final shown = showArchived ? [...visible, ...archived] : visible;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (shown.isNotEmpty)
          GoalCarousel(goals: shown)
        else
          SectionEmptyCard(
            icon: AppIcons.goalOutlined,
            accent: AppAccents.goals,
            title: l10n.ledgerGoalsEmpty,
          ),
        if (archived.isNotEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: AppSpacing.sm),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: AppButton(
                label: showArchived
                    ? l10n.ledgerHideArchivedGoals
                    : l10n.ledgerShowArchivedGoals(archived.length),
                icon: AppIcons.archive,
                variant: AppButtonVariant.text,
                expand: false,
                onPressed: onToggleArchived,
              ),
            ),
          ),
      ],
    );
  }
}
