import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/utils/date_x.dart';
import 'package:family_hub/core/utils/validators.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/ledger/application/ledger_providers.dart';
import 'package:family_hub/features/ledger/domain/ledger_requests.dart';
import 'package:family_hub/features/ledger/domain/savings_goal.dart';
import 'package:family_hub/features/ledger/presentation/ledger_errors.dart';
import 'package:family_hub/features/ledger/presentation/widgets/accent_button.dart';
import 'package:family_hub/features/ledger/presentation/widgets/amount_field.dart';
import 'package:family_hub/features/ledger/presentation/widgets/goal_not_found_view.dart';
import 'package:family_hub/features/ledger/presentation/widgets/records_only_note.dart';
import 'package:family_hub/shared/providers/shared_providers.dart';

/// `/money/goals/new` and `/money/goals/:id/edit` (admins only).
class GoalFormScreen extends ConsumerWidget {
  const GoalFormScreen({super.key, this.goalId});

  /// Null → create a new goal.
  final String? goalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final isAdmin = ref.watch(isAdminProvider);
    final id = goalId;

    final Widget body;
    if (!isAdmin) {
      body = EmptyState(icon: AppIcons.admin, title: l10n.ledgerGoalAdminOnly);
    } else if (id == null) {
      body = const _GoalForm(goal: null);
    } else {
      final goal = ref.watch(savingsGoalProvider(id));
      // Deleted meanwhile / stale link: a retry cannot help.
      body = !goal.isLoading && isLedgerNotFound(goal.error)
          ? const GoalNotFoundView()
          : AsyncValueView<SavingsGoal>(
              value: goal,
              onRetry: () => ref.invalidate(savingsGoalsProvider),
              data: (goal) => _GoalForm(key: ValueKey(goal.id), goal: goal),
            );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          id == null ? l10n.ledgerGoalNewTitle : l10n.ledgerGoalEditTitle,
        ),
      ),
      body: ResponsiveCenter(child: body),
    );
  }
}

class _GoalForm extends ConsumerStatefulWidget {
  const _GoalForm({super.key, required this.goal});

  final SavingsGoal? goal;

  @override
  ConsumerState<_GoalForm> createState() => _GoalFormState();
}

class _GoalFormState extends ConsumerState<_GoalForm> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _target = TextEditingController();
  DateTime? _targetDate;

  bool _saving = false;
  bool _dirty = false;
  bool _initialised = false;

  @override
  void initState() {
    super.initState();
    final g = widget.goal;
    _title.text = g?.title ?? '';
    _description.text = g?.description ?? '';
    _targetDate = g?.targetDate;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialised) return;
    _initialised = true;
    final g = widget.goal;
    if (g != null) {
      _target.text = DecimalAmountInputFormatter.textFor(
        g.targetAmount,
        decimalSeparator: Validators.decimalSeparatorFor(
          context.l10n.localeName,
        ),
      );
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _target.dispose();
    super.dispose();
  }

  void _changed() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<void> _submit() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    final l10n = context.l10n;
    final target = amountFieldValue(l10n, _target.text);
    if (target == null) return;

    final goal = widget.goal;
    setState(() => _saving = true);
    try {
      final actions = ref.read(ledgerActionsProvider);
      if (goal == null) {
        await actions.createGoal(
          GoalInput(
            title: _title.text,
            targetAmount: target,
            description: _description.text,
            targetDate: _targetDate,
          ),
        );
        if (!mounted) return;
        context.showSuccess(l10n.ledgerGoalCreated);
      } else {
        final patch = GoalPatch.diff(
          goal,
          title: _title.text,
          targetAmount: target,
          description: _description.text,
          targetDate: _targetDate,
        );
        await actions.updateGoal(goal.id, patch);
        if (!mounted) return;
        if (!patch.isEmpty) context.showSuccess(l10n.ledgerGoalUpdated);
      }
      setState(() {
        _dirty = false;
        _saving = false;
      });
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      context.showLedgerError(e, subject: LedgerSubject.goal);
      if (goal != null && isLedgerNotFound(e)) {
        // Deleted by another admin meanwhile: nothing left to edit.
        setState(() {
          _saving = false;
          _dirty = false;
        });
        context.pop(false);
        return;
      }
      setState(() => _saving = false);
    }
  }

  Future<void> _confirmDiscard() async {
    final l10n = context.l10n;
    final discard = await showConfirmDialog(
      context,
      title: l10n.commonDiscardChangesTitle,
      message: l10n.commonDiscardChangesMessage,
      confirmLabel: l10n.commonDiscard,
      destructive: true,
    );
    if (!discard || !mounted) return;
    setState(() => _dirty = false);
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final today = DateTime.now().startOfDay;
    final existing = widget.goal?.targetDate;
    // Keep an existing (past) target date selectable when editing.
    final firstDate = existing != null && existing.isBefore(today)
        ? existing
        : today;

    return PopScope(
      canPop: !_dirty || _saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const ExcludeSemantics(
                        child: IconBadge(
                          icon: AppIcons.goal,
                          accent: AppAccents.goals,
                        ),
                      ),
                      AppGap.hMd,
                      Expanded(
                        child: Text(
                          l10n.ledgerGoalsEmptyAdmin,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                    ],
                  ),
                  AppGap.lg,
                  AppTextField(
                    controller: _title,
                    label: l10n.ledgerGoalFieldTitle,
                    hint: l10n.ledgerGoalFieldTitleHint,
                    prefixIcon: AppIcons.goal,
                    maxLength: LedgerLimits.goalTitleMax,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.next,
                    validator: Validators.compose([
                      Validators.required(l10n),
                      Validators.maxLength(l10n, LedgerLimits.goalTitleMax),
                    ]),
                    onChanged: (_) => _changed(),
                  ),
                  AppGap.md,
                  AmountField(
                    controller: _target,
                    label: l10n.ledgerGoalFieldTarget,
                    onChanged: (_) => _changed(),
                  ),
                  AppGap.lg,
                  DatePickerField(
                    label: l10n.ledgerGoalFieldTargetDate,
                    value: _targetDate,
                    firstDate: firstDate,
                    onChanged: (d) {
                      setState(() {
                        _targetDate = d;
                        _dirty = true;
                      });
                    },
                  ),
                  AppGap.lg,
                  AppTextField(
                    controller: _description,
                    label: l10n.ledgerGoalFieldDescription,
                    maxLength: LedgerLimits.goalDescriptionMax,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    validator: Validators.maxLength(
                      l10n,
                      LedgerLimits.goalDescriptionMax,
                    ),
                    onChanged: (_) => _changed(),
                  ),
                ],
              ),
            ),
            AppGap.xl,
            LedgerAccentButton(
              label: l10n.commonSave,
              icon: AppIcons.save,
              accent: AppAccents.goals,
              isLoading: _saving,
              onPressed: _submit,
            ),
            AppGap.sm,
            const RecordsOnlyNote(),
          ],
        ),
      ),
    );
  }
}
