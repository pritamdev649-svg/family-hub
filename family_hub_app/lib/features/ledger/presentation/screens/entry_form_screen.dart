import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/utils/date_x.dart';
import 'package:family_hub/core/utils/validators.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/ledger/application/ledger_providers.dart';
import 'package:family_hub/features/ledger/domain/ledger_entry.dart';
import 'package:family_hub/features/ledger/domain/ledger_requests.dart';
import 'package:family_hub/features/ledger/presentation/ledger_errors.dart';
import 'package:family_hub/features/ledger/presentation/ledger_labels.dart';
import 'package:family_hub/features/ledger/presentation/widgets/accent_button.dart';
import 'package:family_hub/features/ledger/presentation/widgets/amount_field.dart';
import 'package:family_hub/features/ledger/presentation/widgets/category_grid.dart';
import 'package:family_hub/features/ledger/presentation/widgets/form_notice.dart';
import 'package:family_hub/features/ledger/presentation/widgets/records_only_note.dart';
import 'package:family_hub/features/ledger/presentation/widgets/type_toggle.dart';
import 'package:family_hub/shared/models/member.dart';
import 'package:family_hub/shared/providers/shared_providers.dart';

/// Earliest selectable entry date.
final ledgerFirstEntryDate = DateTime(2000);

/// Latest allowed entry date: tomorrow (contract: `date ≤ today + 1 day`,
/// absorbs time-zone differences between phone and server).
DateTime ledgerLastEntryDate([DateTime? now]) =>
    (now ?? DateTime.now()).startOfDay.add(const Duration(days: 1));

/// `/money/entries/new?type=income|expense` — records a new entry, or edits
/// [entry] when given (passed as the route's `extra`; the contract has no
/// `GET /ledger/entries/:id`).
///
/// * Members always record for themselves (member field locked); admins may
///   pick any family member.
/// * Goal contributions keep their amount, type and category.
class EntryFormScreen extends ConsumerStatefulWidget {
  const EntryFormScreen({super.key, this.initialType, this.entry});

  final LedgerType? initialType;
  final LedgerEntry? entry;

  bool get isEdit => entry != null;

  @override
  ConsumerState<EntryFormScreen> createState() => _EntryFormScreenState();
}

class _EntryFormScreenState extends ConsumerState<EntryFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();

  late LedgerType _type;
  LedgerCategory? _category;
  late DateTime _date;
  String? _memberId;

  bool _saving = false;
  bool _dirty = false;
  bool _initialised = false;

  LedgerEntry? get _entry => widget.entry;
  bool get _locked => _entry?.isGoalLinked ?? false;

  @override
  void initState() {
    super.initState();
    final e = _entry;
    _type = e?.type ?? widget.initialType ?? LedgerType.expense;
    _category = e?.category;
    _date = e?.date ?? DateTime.now().startOfDay;
    _memberId = e?.memberId;
    _note.text = e?.note ?? '';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialised) return;
    _initialised = true;
    final e = _entry;
    if (e != null) {
      _amount.text = DecimalAmountInputFormatter.textFor(
        e.amount,
        decimalSeparator: Validators.decimalSeparatorFor(
          context.l10n.localeName,
        ),
      );
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _changed() {
    if (!_dirty) setState(() => _dirty = true);
  }

  void _setType(LedgerType type) {
    if (type == _type) return;
    setState(() {
      _type = type;
      // A category never carries over to the other type.
      if (_category?.type != type) _category = null;
      _dirty = true;
    });
  }

  Future<void> _submit() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    final l10n = context.l10n;
    final entry = _entry;
    final amount = _locked
        ? entry!.amount
        : amountFieldValue(l10n, _amount.text);
    final category = _category;
    if (amount == null || category == null) return; // flagged by validators

    final isAdmin = ref.read(isAdminProvider);
    final me = ref.read(currentMemberProvider);
    setState(() => _saving = true);
    try {
      final actions = ref.read(ledgerActionsProvider);
      if (entry == null) {
        await actions.createEntry(
          LedgerEntryInput(
            type: _type,
            amount: amount,
            category: category,
            date: _date,
            note: _note.text,
            // Members always record for themselves (server default).
            memberId: isAdmin ? (_memberId ?? me?.id) : null,
          ),
        );
        if (!mounted) return;
        context.showSuccess(l10n.ledgerEntryAdded);
      } else {
        final patch = LedgerEntryPatch.diff(
          entry,
          type: _type,
          amount: amount,
          category: category,
          date: _date,
          note: _note.text,
          memberId: isAdmin ? _memberId : null,
        );
        await actions.updateEntry(entry.id, patch);
        if (!mounted) return;
        if (!patch.isEmpty) context.showSuccess(l10n.ledgerEntrySaved);
      }
      setState(() {
        _dirty = false;
        _saving = false;
      });
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      context.showLedgerError(e, subject: LedgerSubject.entry);
      if (entry != null && isLedgerNotFound(e)) {
        // Deleted by someone else meanwhile: nothing left to edit (the
        // lists were refreshed by `LedgerActions`).
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
    final theme = Theme.of(context);
    final isAdmin = ref.watch(isAdminProvider);
    final entry = _entry;
    final keep = entry != null && entry.type == _type ? entry.category : null;
    final categories = LedgerCategory.manualFor(_type, keep: keep);
    final lastDate = ledgerLastEntryDate();

    return PopScope(
      canPop: !_dirty || _saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.isEdit
                ? l10n.ledgerEditEntryTitle
                : l10n.ledgerNewEntryTitle,
          ),
        ),
        body: ResponsiveCenter(
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
                if (_locked) ...[
                  FormNotice(
                    icon: AppIcons.goal,
                    message: l10n.ledgerGoalLinkedLocked,
                  ),
                  AppGap.lg,
                ],
                // Type + the big amount.
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LedgerTypeToggle(
                        selected: _type,
                        onChanged: _locked || _saving ? null : _setType,
                      ),
                      AppGap.lg,
                      AmountField.hero(
                        controller: _amount,
                        enabled: !_locked,
                        accent: _type.accent,
                        onChanged: (_) => _changed(),
                      ),
                    ],
                  ),
                ),
                AppGap.lg,
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SectionHeader(
                        title: l10n.ledgerFieldCategory,
                        icon: AppIcons.category,
                        accent: _type.accent,
                      ),
                      AppGap.xs,
                      FormField<LedgerCategory>(
                        // Re-validated against the controlled [_category].
                        validator: (_) => _category == null
                            ? l10n.ledgerCategoryRequired
                            : null,
                        builder: (field) => Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            LedgerCategoryGrid(
                              categories: categories,
                              selected: _category,
                              onSelected: _locked || _saving
                                  ? null
                                  : (c) {
                                      setState(() {
                                        _category = c;
                                        _dirty = true;
                                      });
                                      field.didChange(c);
                                    },
                            ),
                            if (field.hasError) ...[
                              AppGap.sm,
                              Semantics(
                                liveRegion: true,
                                child: Text(
                                  field.errorText ?? '',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.error,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                AppGap.lg,
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SectionHeader(
                        title: l10n.ledgerFormDetailsTitle,
                        icon: AppIcons.notes,
                        accent: AppAccents.money,
                      ),
                      AppGap.xs,
                      DatePickerField(
                        label: l10n.ledgerFieldDate,
                        value: _date,
                        allowClear: false,
                        firstDate: _date.isBefore(ledgerFirstEntryDate)
                            ? _date
                            : ledgerFirstEntryDate,
                        lastDate: lastDate,
                        validator: (d) {
                          if (d == null) return l10n.validationRequired;
                          return d.startOfDay.isAfter(lastDate)
                              ? l10n.ledgerDateInFuture
                              : null;
                        },
                        onChanged: (d) {
                          if (d == null) return;
                          setState(() {
                            _date = d;
                            _dirty = true;
                          });
                        },
                      ),
                      AppGap.md,
                      _MemberField(
                        isAdmin: isAdmin,
                        memberId: _memberId,
                        recordedName: entry?.memberName,
                        enabled: !_saving,
                        onChanged: (id) {
                          setState(() {
                            _memberId = id;
                            _dirty = true;
                          });
                        },
                      ),
                      AppGap.md,
                      AppTextField(
                        controller: _note,
                        label: l10n.ledgerFieldNote,
                        hint: l10n.ledgerFieldNoteHint,
                        maxLength: LedgerLimits.noteMax,
                        maxLines: 3,
                        textCapitalization: TextCapitalization.sentences,
                        validator: Validators.maxLength(
                          l10n,
                          LedgerLimits.noteMax,
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
                  accent: _type.accent,
                  isLoading: _saving,
                  onPressed: _submit,
                ),
                AppGap.sm,
                const RecordsOnlyNote(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Admins pick whose money it is; members see themselves (locked).
class _MemberField extends ConsumerWidget {
  const _MemberField({
    required this.isAdmin,
    required this.memberId,
    required this.onChanged,
    required this.enabled,
    this.recordedName,
  });

  final bool isAdmin;

  /// Selected member (null = the signed-in member).
  final String? memberId;
  final ValueChanged<String?> onChanged;
  final bool enabled;

  /// Name stored on the entry being edited (null for a new entry); shown
  /// when that member is no longer in the family.
  final String? recordedName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final me = ref.watch(currentMemberProvider);
    final selectedId = memberId ?? me?.id;

    String nameOf(Member m) =>
        m.id == me?.id ? l10n.ledgerMemberYou(m.name) : m.name;

    if (!isAdmin) {
      // New entries are always recorded for the signed-in member (also
      // right after losing the admin role with someone else selected).
      final String name;
      if (recordedName == null || selectedId == null || selectedId == me?.id) {
        name = me == null ? (recordedName ?? '') : nameOf(me);
      } else {
        name = recordedName ?? '';
      }
      return InputDecorator(
        decoration: InputDecoration(
          labelText: l10n.ledgerFieldMember,
          helperText: l10n.ledgerFieldMemberLocked,
          helperMaxLines: 3,
          enabled: false,
          prefixIcon: const Icon(AppIcons.memberOutlined),
        ),
        child: Text(name),
      );
    }

    final membersValue = ref.watch(membersProvider);
    final members = membersValue.value ?? [?me];
    Member? selected;
    for (final m in members) {
      if (m.id == selectedId) selected = m;
    }
    // Editing an entry of someone who left the family: the dropdown cannot
    // show them, so say whose it is (saving keeps the owner unchanged).
    final recorded = recordedName;
    final ownerGone =
        membersValue.hasValue &&
        selected == null &&
        recorded != null &&
        recorded.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppDropdownField<Member>(
          // Rebuild when the list arrives so the initial value shows up.
          key: ValueKey('member-${members.length}-${selected?.id}'),
          label: l10n.ledgerFieldMember,
          value: selected,
          items: members,
          itemLabel: nameOf,
          leading: (m) => MemberAvatar(
            name: m.name,
            avatarUrl: m.avatarUrl,
            radius: AppSizes.avatarSm,
          ),
          onChanged: enabled ? (m) => onChanged(m?.id) : null,
        ),
        if (ownerGone) ...[
          AppGap.xs,
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: AppSpacing.md,
            ),
            child: Text(
              l10n.ledgerMemberNoLongerInFamily(recorded),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
