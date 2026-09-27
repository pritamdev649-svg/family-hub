import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/utils/date_x.dart';
import 'package:family_hub/core/utils/formatters.dart';
import 'package:family_hub/core/utils/validators.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/ledger/application/ledger_providers.dart';
import 'package:family_hub/features/ledger/domain/ledger_requests.dart';
import 'package:family_hub/features/ledger/domain/savings_goal.dart';
import 'package:family_hub/features/ledger/presentation/ledger_errors.dart';
import 'package:family_hub/features/ledger/presentation/widgets/accent_button.dart';
import 'package:family_hub/features/ledger/presentation/widgets/amount_field.dart';
import 'package:family_hub/features/ledger/presentation/widgets/inline_error.dart';

/// Asks for an amount (and optional note) and records a contribution to
/// [goal] (`POST /goals/:id/contributions`). Any member may contribute.
/// Resolves to the result, or null when dismissed.
Future<GoalContributionResult?> showContributeSheet(
  BuildContext context,
  SavingsGoal goal,
) {
  return showModalBottomSheet<GoalContributionResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => ContributeSheet(goal: goal),
  );
}

/// Content of [showContributeSheet].
class ContributeSheet extends ConsumerStatefulWidget {
  const ContributeSheet({super.key, required this.goal});

  final SavingsGoal goal;

  @override
  ConsumerState<ContributeSheet> createState() => _ContributeSheetState();
}

class _ContributeSheetState extends ConsumerState<ContributeSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  bool _saving = false;
  Object? _error;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    final amount = amountFieldValue(context.l10n, _amount.text);
    if (amount == null) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(ledgerActionsProvider)
          .contribute(
            widget.goal.id,
            GoalContributionInput(
              amount: amount,
              note: _note.text,
              date: DateTime.now().startOfDay,
            ),
          );
      if (mounted) Navigator.of(context).pop(result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final fmt = ref.watch(fmtProvider);
    final theme = Theme.of(context);
    final goal = widget.goal;
    final error = _error;

    // No accidental dismissal (back / barrier tap) while the contribution
    // is being recorded: the result (celebration) would be lost.
    return PopScope(
      canPop: !_saving,
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsetsDirectional.only(
            start: AppSpacing.lg,
            end: AppSpacing.lg,
            bottom: AppSpacing.xl,
          ),
          child: Form(
            key: _formKey,
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Semantics(
                            header: true,
                            child: Text(
                              l10n.ledgerGoalContributeTitle(goal.title),
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          if (goal.remaining > 0) ...[
                            AppGap.xxs,
                            Text(
                              l10n.ledgerGoalRemainingHint(
                                fmt.money(goal.remaining),
                              ),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: context
                                    .accent(AppAccents.goals)
                                    .foreground,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                AppGap.lg,
                AmountField(controller: _amount, enabled: !_saving),
                AppGap.md,
                AppTextField(
                  controller: _note,
                  label: l10n.ledgerFieldNote,
                  hint: l10n.ledgerGoalContributionNoteHint,
                  maxLength: LedgerLimits.noteMax,
                  enabled: !_saving,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.done,
                  validator: Validators.maxLength(l10n, LedgerLimits.noteMax),
                  onSubmitted: (_) => _submit(),
                ),
                AppGap.sm,
                Text(
                  l10n.ledgerGoalContributeExplainer,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (error != null) ...[
                  AppGap.md,
                  // Archived (409), deleted (404), role changed (403), date
                  // outside the family's window (422)…
                  LedgerInlineError(
                    error: error,
                    message: ledgerErrorMessage(
                      error,
                      l10n,
                      subject: LedgerSubject.goal,
                    ),
                  ),
                ],
                AppGap.lg,
                LedgerAccentButton(
                  label: l10n.ledgerGoalContribute,
                  icon: AppIcons.goal,
                  accent: AppAccents.goals,
                  isLoading: _saving,
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
