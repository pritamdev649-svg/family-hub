import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/utils/formatters.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/ledger/application/ledger_providers.dart';
import 'package:family_hub/features/ledger/domain/ledger_entry.dart';
import 'package:family_hub/features/ledger/presentation/ledger_errors.dart';
import 'package:family_hub/features/ledger/presentation/ledger_labels.dart';
import 'package:family_hub/features/ledger/presentation/widgets/inline_error.dart';
import 'package:family_hub/shared/models/member.dart';
import 'package:family_hub/shared/providers/shared_providers.dart';

enum _SheetResult { edit, deleted, alreadyDeleted, openGoal }

/// Opens the details of [entry] in a bottom sheet with edit / delete for
/// admins and the entry's creator. Navigation and the success snackbar run
/// on [context] after the sheet closed.
///
/// [showGoalLink] hides "View goal" when already on that goal's screen.
Future<void> showLedgerEntrySheet(
  BuildContext context,
  LedgerEntry entry, {
  bool showGoalLink = true,
}) async {
  final result = await showModalBottomSheet<_SheetResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => LedgerEntrySheet(entry: entry, showGoalLink: showGoalLink),
  );
  if (!context.mounted || result == null) return;
  switch (result) {
    case _SheetResult.deleted:
      context.showSuccess(context.l10n.ledgerEntryDeleted);
    case _SheetResult.alreadyDeleted:
      context.showInfo(context.l10n.ledgerEntryAlreadyDeleted);
    case _SheetResult.edit:
      await context.push<bool>(
        AppRoutes.ledgerEntryNew(type: entry.type.wireName),
        extra: entry,
      );
    case _SheetResult.openGoal:
      final goalId = entry.goalId;
      if (goalId != null) await context.push(AppRoutes.goalDetail(goalId));
  }
}

/// Content of [showLedgerEntrySheet].
class LedgerEntrySheet extends ConsumerStatefulWidget {
  const LedgerEntrySheet({
    super.key,
    required this.entry,
    this.showGoalLink = true,
  });

  final LedgerEntry entry;
  final bool showGoalLink;

  @override
  ConsumerState<LedgerEntrySheet> createState() => _LedgerEntrySheetState();
}

class _LedgerEntrySheetState extends ConsumerState<LedgerEntrySheet> {
  bool _deleting = false;
  Object? _error;

  Future<void> _delete() async {
    final l10n = context.l10n;
    final entry = widget.entry;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.ledgerDeleteEntryTitle,
      message: entry.isGoalLinked
          ? l10n.ledgerDeleteContributionMessage
          : l10n.ledgerDeleteEntryMessage,
      confirmLabel: l10n.commonDelete,
      destructive: true,
    );
    if (!confirmed || !mounted || _deleting) return;
    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      await ref.read(ledgerActionsProvider).deleteEntry(entry.id);
      if (mounted) Navigator.of(context).pop(_SheetResult.deleted);
    } catch (e) {
      // Someone else deleted it meanwhile: what the user wanted is done
      // (the lists were refreshed by `LedgerActions`).
      if (mounted && isLedgerNotFound(e)) {
        Navigator.of(context).pop(_SheetResult.alreadyDeleted);
      } else if (mounted) {
        setState(() {
          _deleting = false;
          _error = e;
        });
      }
    }
  }

  /// Current name of member [id] ("(you)" for the signed-in member), or
  /// null when [members] does not contain them.
  String? _memberName(List<Member> members, String id, Member? me) {
    if (id.isEmpty) return null;
    for (final m in members) {
      if (m.id == id) {
        return m.id == me?.id ? context.l10n.ledgerMemberYou(m.name) : m.name;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final fmt = ref.watch(fmtProvider);
    final theme = Theme.of(context);
    final entry = widget.entry;
    final me = ref.watch(currentMemberProvider);
    final isAdmin = ref.watch(isAdminProvider);
    final membersValue = ref.watch(membersProvider);
    final members = membersValue.value ?? const <Member>[];
    // Only say "former member" once the list is known (not while loading /
    // offline).
    final membersKnown = membersValue.hasValue && !membersValue.hasError;
    final canModify = entry.canBeModifiedBy(memberId: me?.id, isAdmin: isAdmin);

    // Entries outlive removed members: fall back to the stored name.
    final owner =
        _memberName(members, entry.memberId, me) ??
        (entry.memberName.isEmpty
            ? (membersKnown ? l10n.ledgerFormerMember : null)
            : entry.memberName);
    final creator = entry.createdById == entry.memberId
        ? null
        : _memberName(members, entry.createdById, me) ??
              (membersKnown && entry.createdById.isNotEmpty
                  ? l10n.ledgerFormerMember
                  : null);

    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.only(
        start: AppSpacing.lg,
        end: AppSpacing.lg,
        bottom: AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              l10n.ledgerEntryDetailTitle,
              style: theme.textTheme.titleMedium,
            ),
          ),
          AppGap.lg,
          // Hero: solid category badge, type / goal chips and the amount.
          AppCard(
            accent: entry.type.accent,
            child: Row(
              children: [
                ExcludeSemantics(
                  child: IconBadge(
                    icon: entry.category.icon,
                    accent: entry.category.accent,
                    size: AppSizes.badgeLg,
                  ),
                ),
                AppGap.hLg,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.xs,
                        children: [
                          StatusChip(
                            label: entry.type.label(l10n),
                            icon: entry.type.icon,
                            color: context.accent(entry.type.accent).foreground,
                          ),
                          if (entry.isGoalLinked)
                            StatusChip(
                              label: l10n.ledgerEntryGoalBadge,
                              icon: AppIcons.goal,
                              color: context
                                  .accent(AppAccents.goals)
                                  .foreground,
                            ),
                        ],
                      ),
                      AppGap.sm,
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: MoneyText(
                          entry.amount,
                          flow: entry.type.flow,
                          style: theme.textTheme.headlineMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          AppGap.md,
          _DetailRow(
            icon: entry.category.icon,
            accent: entry.category.accent,
            label: l10n.ledgerDetailCategory,
            value: entry.category.label(l10n),
          ),
          _DetailRow(
            icon: AppIcons.calendar,
            accent: AppAccents.money,
            label: l10n.ledgerDetailDate,
            value: fmt.date(entry.date),
          ),
          if (owner != null)
            _DetailRow(
              icon: AppIcons.member,
              accent: AppAccents.family,
              label: l10n.ledgerDetailMember,
              value: owner,
            ),
          if (creator != null)
            _DetailRow(
              icon: AppIcons.edit,
              accent: AppAccents.tasks,
              label: l10n.ledgerDetailCreatedBy,
              value: creator,
            ),
          if (entry.note != null)
            _DetailRow(
              icon: AppIcons.notes,
              accent: AppAccents.notices,
              label: l10n.ledgerDetailNote,
              value: entry.note!,
            ),
          if (entry.isGoalLinked)
            _DetailRow(
              icon: AppIcons.goal,
              accent: AppAccents.goals,
              label: l10n.ledgerDetailGoal,
              value: null,
              trailing: widget.showGoalLink
                  ? TextButton(
                      onPressed: _deleting
                          ? null
                          : () => Navigator.of(
                              context,
                            ).pop(_SheetResult.openGoal),
                      child: Text(l10n.ledgerDetailOpenGoal),
                    )
                  : null,
            ),
          if (_error case final error?) ...[
            AppGap.md,
            LedgerInlineError(
              error: error,
              message: ledgerErrorMessage(
                error,
                l10n,
                subject: LedgerSubject.entry,
              ),
            ),
          ],
          if (canModify) ...[
            AppGap.xl,
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              alignment: WrapAlignment.end,
              children: [
                AppButton(
                  label: l10n.commonDelete,
                  icon: AppIcons.delete,
                  variant: AppButtonVariant.danger,
                  expand: false,
                  isLoading: _deleting,
                  onPressed: _delete,
                ),
                AppButton(
                  label: l10n.commonEdit,
                  icon: AppIcons.edit,
                  variant: AppButtonVariant.secondary,
                  expand: false,
                  onPressed: _deleting
                      ? null
                      : () => Navigator.of(context).pop(_SheetResult.edit),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.accent,
    required this.label,
    required this.value,
    this.trailing,
  });

  final IconData icon;
  final AppAccent accent;
  final String label;
  final String? value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: MergeSemantics(
        child: Row(
          children: [
            ExcludeSemantics(
              child: IconBadge(
                icon: icon,
                accent: accent,
                size: AppSizes.badgeSm,
                soft: true,
              ),
            ),
            AppGap.hMd,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (value != null)
                    Text(value!, style: theme.textTheme.bodyLarge),
                ],
              ),
            ),
            if (trailing != null) ...[AppGap.hSm, trailing!],
          ],
        ),
      ),
    );
  }
}
