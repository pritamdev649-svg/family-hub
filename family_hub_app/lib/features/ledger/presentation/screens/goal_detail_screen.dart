import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/network/api_exception.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/utils/formatters.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/ledger/application/ledger_providers.dart';
import 'package:family_hub/features/ledger/domain/ledger_requests.dart';
import 'package:family_hub/features/ledger/domain/savings_goal.dart';
import 'package:family_hub/features/ledger/presentation/ledger_errors.dart';
import 'package:family_hub/features/ledger/presentation/ledger_labels.dart';
import 'package:family_hub/features/ledger/presentation/ledger_open_guard.dart';
import 'package:family_hub/features/ledger/presentation/widgets/accent_button.dart';
import 'package:family_hub/features/ledger/presentation/widgets/contribute_sheet.dart';
import 'package:family_hub/features/ledger/presentation/widgets/entry_detail_sheet.dart';
import 'package:family_hub/features/ledger/presentation/widgets/form_notice.dart';
import 'package:family_hub/features/ledger/presentation/widgets/goal_not_found_view.dart';
import 'package:family_hub/features/ledger/presentation/widgets/goal_progress_card.dart';
import 'package:family_hub/features/ledger/presentation/widgets/ledger_entry_tile.dart';
import 'package:family_hub/features/ledger/presentation/widgets/on_gradient.dart';
import 'package:family_hub/features/ledger/presentation/widgets/records_only_note.dart';
import 'package:family_hub/features/ledger/presentation/widgets/section_empty_card.dart';
import 'package:family_hub/shared/providers/shared_providers.dart';

/// `/money/goals/:id` — a pink gradient header (behind the transparent
/// status bar) with the progress ring, title, status, saved / target and the
/// deadline; below it the "still to go" card with the Contribute button (any
/// member), the contributions list and — in the header — the admin actions
/// (edit / archive / restore / delete).
///
/// While the goal loads or failed to load the screen has a plain app bar
/// (with a way back). A goal that no longer exists (deleted by an admin —
/// also while this screen is open — or a stale notification link) shows
/// [GoalNotFoundView].
class GoalDetailScreen extends ConsumerWidget {
  const GoalDetailScreen({super.key, required this.goalId});

  final String goalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goal = ref.watch(savingsGoalProvider(goalId));
    final gone = !goal.isLoading && isLedgerNotFound(goal.error);
    final loaded = gone ? null : goal.value;

    return Scaffold(
      // With a goal the gradient header (own back button + menu) replaces
      // the app bar.
      appBar: loaded == null ? AppBar() : null,
      body: gone
          ? const ResponsiveCenter(child: GoalNotFoundView())
          : AsyncValueView<SavingsGoal>(
              value: goal,
              onRetry: () => ref.invalidate(savingsGoalsProvider),
              data: (g) => _GoalDetailBody(goal: g),
            ),
    );
  }
}

class _GoalDetailBody extends ConsumerStatefulWidget {
  const _GoalDetailBody({required this.goal});

  final SavingsGoal goal;

  @override
  ConsumerState<_GoalDetailBody> createState() => _GoalDetailBodyState();
}

class _GoalDetailBodyState extends ConsumerState<_GoalDetailBody>
    with LedgerOpenGuard {
  Future<void> _contribute() async {
    final before = widget.goal;
    final result = await showContributeSheet(context, before);
    if (result == null || !mounted) return;
    if (result.goal.isAchieved && !before.isAchieved) {
      await showGoalAchievedDialog(context, result.goal);
    } else {
      context.showSuccess(context.l10n.ledgerGoalContributed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final goal = widget.goal;
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final isAdmin = ref.watch(isAdminProvider);
    final query = LedgerEntryQuery.forGoal(goal.id);
    final contributions = ref.watch(ledgerEntriesProvider(query));

    Future<void> loadMore() async {
      try {
        await ref.read(ledgerEntriesProvider(query).notifier).loadMore();
      } catch (e) {
        if (context.mounted) context.showError(e);
      }
    }

    return GradientHeaderScrollView(
      gradient: AppGradients.headerOf(AppAccents.goals),
      onRefresh: () => Future.wait<Object?>([
        ref.refresh(savingsGoalsProvider.future),
        ref.refresh(ledgerEntriesProvider(query).future),
      ]),
      header: _GoalHeader(goal: goal, isAdmin: isAdmin),
      children: [
        // Overlaps the header's rounded bottom edge.
        _ContributeCard(
          goal: goal,
          onContribute: goal.acceptsContributions
              ? () => guardedOpen(_contribute)
              : null,
        ),
        AppGap.xl,
        SectionHeader(
          title: l10n.ledgerGoalContributionsTitle,
          icon: AppIcons.history,
          accent: AppAccents.goals,
        ),
        if (!isAdmin) ...[
          Text(
            l10n.ledgerGoalContributionsMineOnly,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          AppGap.sm,
        ],
        AsyncValueView<LedgerEntriesState>(
          value: contributions,
          onRetry: () => ref.invalidate(ledgerEntriesProvider(query)),
          isEmpty: (s) => s.isEmpty,
          empty: SectionEmptyCard(
            icon: AppIcons.goalOutlined,
            accent: AppAccents.goals,
            title: l10n.ledgerGoalContributionsEmpty,
            message: goal.acceptsContributions
                ? l10n.ledgerGoalContributionsEmptyMessage
                : null,
          ),
          data: (state) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < state.items.length; i++) ...[
                if (i > 0) AppGap.sm,
                LedgerEntryTile(
                  state.items[i],
                  key: ValueKey('contribution-${state.items[i].id}'),
                  onTap: () => guardedOpen(
                    () => showLedgerEntrySheet(
                      context,
                      state.items[i],
                      showGoalLink: false,
                    ),
                  ),
                ),
              ],
              if (state.hasMore || state.isLoadingMore) ...[
                AppGap.sm,
                Center(
                  child: AppButton(
                    label: l10n.commonLoadMore,
                    icon: AppIcons.expand,
                    variant: AppButtonVariant.text,
                    expand: false,
                    isLoading: state.isLoadingMore,
                    onPressed: loadMore,
                  ),
                ),
              ],
            ],
          ),
        ),
        AppGap.lg,
        const RecordsOnlyNote(),
      ],
    );
  }
}

/// White-on-pink header: back / admin menu, progress ring, title, status,
/// description, saved + target pills and the target date / days left.
class _GoalHeader extends ConsumerWidget {
  const _GoalHeader({required this.goal, required this.isAdmin});

  final SavingsGoal goal;
  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final fmt = ref.watch(fmtProvider);
    final theme = Theme.of(context);
    final deadline = goalDeadlineLabel(goal, l10n, fmt);
    final target = goal.targetDate;
    final overdue = goal.isOverdue();
    final percent = fmt.percent(goal.progress);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            GlassIconButton(
              icon: AppIcons.back,
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            const Spacer(),
            if (isAdmin) _GoalActionsMenu(goal: goal),
          ],
        ),
        AppGap.lg,
        Row(
          children: [
            OnGradientProgressRing(
              value: goal.progress,
              centerLabel: percent,
              semanticsLabel: l10n.ledgerGoalPercentSaved(percent),
            ),
            AppGap.hLg,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      goal.title,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ),
                  AppGap.sm,
                  GlassChip(
                    label: goal.status.label(l10n),
                    icon: goal.status.icon,
                  ),
                ],
              ),
            ),
          ],
        ),
        if (goal.description != null) ...[
          AppGap.md,
          Text(
            goal.description!,
            style: theme.textTheme.bodyMedium?.copyWith(color: onGradientMuted),
          ),
        ],
        AppGap.lg,
        Row(
          children: [
            Expanded(
              child: GlassStat(
                icon: AppIcons.goal,
                label: l10n.ledgerGoalSavedLabel,
                value: fmt.money(goal.savedAmount),
              ),
            ),
            AppGap.hSm,
            Expanded(
              child: GlassStat(
                icon: AppIcons.target,
                label: l10n.ledgerGoalTargetLabel,
                value: fmt.money(goal.targetAmount),
              ),
            ),
          ],
        ),
        AppGap.md,
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  AppIcons.dueDate,
                  size: AppSizes.iconXs,
                  color: onGradientMuted,
                ),
                AppGap.hXs,
                Flexible(
                  child: Text(
                    target == null
                        ? l10n.ledgerGoalNoTargetDate
                        : l10n.ledgerGoalTargetDate(fmt.date(target)),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: onGradientMuted,
                    ),
                  ),
                ),
              ],
            ),
            if (goal.isActive && deadline != null)
              GlassChip(
                label: deadline,
                icon: overdue ? AppIcons.warning : AppIcons.time,
              ),
          ],
        ),
      ],
    );
  }
}

/// The card overlapping the header: how much is still to go (or the
/// "target reached" / "archived" notice) and the Contribute button.
class _ContributeCard extends StatelessWidget {
  const _ContributeCard({required this.goal, required this.onContribute});

  final SavingsGoal goal;
  final VoidCallback? onContribute;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (goal.isAchieved)
            FormNotice(
              icon: AppIcons.goalAchieved,
              accent: AppAccents.success,
              message: l10n.ledgerGoalReachedMessage,
            )
          else
            MergeSemantics(
              child: Row(
                children: [
                  const ExcludeSemantics(
                    child: IconBadge(
                      icon: AppIcons.target,
                      accent: AppAccents.goals,
                      soft: true,
                    ),
                  ),
                  AppGap.hMd,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.ledgerGoalRemainingLabel,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerStart,
                          child: MoneyText(
                            goal.remaining,
                            style: theme.textTheme.titleLarge,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (goal.isArchived) ...[
            AppGap.md,
            FormNotice(
              icon: AppIcons.archive,
              accent: AppAccents.warning,
              message: l10n.ledgerGoalArchivedNotice,
            ),
          ],
          AppGap.lg,
          LedgerAccentButton(
            label: l10n.ledgerGoalContribute,
            icon: AppIcons.goal,
            accent: AppAccents.goals,
            onPressed: onContribute,
          ),
        ],
      ),
    );
  }
}

enum _GoalAction { edit, archive, restore, delete }

/// Admin overflow menu. Shows a spinner while an action runs so it cannot be
/// triggered twice.
class _GoalActionsMenu extends ConsumerStatefulWidget {
  const _GoalActionsMenu({required this.goal});

  final SavingsGoal goal;

  @override
  ConsumerState<_GoalActionsMenu> createState() => _GoalActionsMenuState();
}

class _GoalActionsMenuState extends ConsumerState<_GoalActionsMenu> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      // Deleted meanwhile (the screen then shows "not found"), role
      // changed, …
      if (mounted) context.showLedgerError(e, subject: LedgerSubject.goal);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onSelected(_GoalAction action) async {
    final l10n = context.l10n;
    final goal = widget.goal;
    final actions = ref.read(ledgerActionsProvider);
    switch (action) {
      case _GoalAction.edit:
        await context.push<bool>(AppRoutes.goalEdit(goal.id));
      case _GoalAction.archive:
        final ok = await showConfirmDialog(
          context,
          title: l10n.ledgerGoalArchiveTitle,
          message: l10n.ledgerGoalArchiveMessage,
          confirmLabel: l10n.ledgerGoalArchive,
        );
        if (!ok || !mounted) return;
        await _run(() async {
          await actions.setGoalStatus(goal.id, GoalStatus.archived);
          if (mounted) context.showSuccess(l10n.ledgerGoalArchivedDone);
        });
      case _GoalAction.restore:
        await _run(() async {
          await actions.setGoalStatus(goal.id, GoalStatus.active);
          if (mounted) context.showSuccess(l10n.ledgerGoalRestoredDone);
        });
      case _GoalAction.delete:
        final ok = await showConfirmDialog(
          context,
          title: l10n.ledgerGoalDeleteTitle,
          message: l10n.ledgerGoalDeleteMessage,
          confirmLabel: l10n.commonDelete,
          destructive: true,
        );
        if (!ok || !mounted) return;
        await _run(() async {
          try {
            await actions.deleteGoal(goal.id);
          } on ApiException catch (e) {
            // Another admin deleted it first: the result is the same.
            if (!e.isNotFound) rethrow;
            if (!mounted) return;
            context.showInfo(l10n.ledgerGoalAlreadyDeleted);
            context.pop();
            return;
          }
          if (!mounted) return;
          context.showSuccess(l10n.ledgerGoalDeleted);
          context.pop();
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (_busy) {
      return Semantics(
        label: l10n.commonLoading,
        child: const SizedBox.square(
          dimension: AppSizes.minTapTarget,
          child: Center(
            child: SizedBox.square(
              dimension: AppSizes.spinnerSm,
              child: CircularProgressIndicator(
                strokeWidth: AppSizes.spinnerStroke,
                color: Colors.white,
              ),
            ),
          ),
        ),
      );
    }
    final goal = widget.goal;
    PopupMenuItem<_GoalAction> item(
      _GoalAction value,
      IconData icon,
      String label, {
      Color? color,
    }) => PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, color: color),
          AppGap.hMd,
          Flexible(
            child: Text(
              label,
              style: color == null
                  ? null
                  : Theme.of(
                      context,
                    ).textTheme.bodyLarge?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );

    return PopupMenuButton<_GoalAction>(
      tooltip: l10n.ledgerGoalActions,
      // Frosted white button on the pink header.
      style: GlassIconButton.style(),
      icon: const Icon(AppIcons.moreVert, size: AppSizes.iconSm),
      onSelected: _onSelected,
      itemBuilder: (context) => [
        item(_GoalAction.edit, AppIcons.edit, l10n.commonEdit),
        if (goal.isArchived)
          item(_GoalAction.restore, AppIcons.reopen, l10n.ledgerGoalRestore)
        else
          item(_GoalAction.archive, AppIcons.archive, l10n.ledgerGoalArchive),
        item(
          _GoalAction.delete,
          AppIcons.delete,
          l10n.ledgerGoalDelete,
          color: Theme.of(context).colorScheme.error,
        ),
      ],
    );
  }
}

/// Celebration shown when a contribution completes [goal].
Future<void> showGoalAchievedDialog(BuildContext context, SavingsGoal goal) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final l10n = dialogContext.l10n;
      return Consumer(
        builder: (context, ref, _) {
          final fmt = ref.watch(fmtProvider);
          return AlertDialog(
            scrollable: true,
            icon: const IconBadge(
              icon: AppIcons.goalAchieved,
              accent: AppAccents.goals,
              size: AppSizes.badgeLg,
            ),
            title: Text(l10n.ledgerGoalAchievedTitle),
            content: Text(
              l10n.ledgerGoalAchievedMessage(
                goal.title,
                fmt.money(goal.targetAmount),
              ),
              textAlign: TextAlign.center,
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(l10n.ledgerGoalCelebrate),
              ),
            ],
          );
        },
      );
    },
  );
}
