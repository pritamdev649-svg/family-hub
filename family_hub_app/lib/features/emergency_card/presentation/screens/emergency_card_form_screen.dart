import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/utils/validators.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/emergency_card/application/emergency_card_providers.dart';
import 'package:family_hub/features/emergency_card/presentation/emergency_card_labels.dart';
import 'package:family_hub/features/emergency_card/presentation/emergency_card_style.dart';
import 'package:family_hub/features/emergency_card/presentation/widgets/card_notice.dart';
import 'package:family_hub/features/emergency_card/presentation/widgets/card_unavailable.dart';
import 'package:family_hub/features/emergency_card/presentation/widgets/chip_list_field.dart';
import 'package:family_hub/features/emergency_card/presentation/widgets/emergency_section.dart';

/// `/emergency-cards/:memberId/edit` (self or admin): blood group, allergy /
/// medication / condition lists, doctor, insurance, up to five emergency
/// contacts and notes, with the health-data disclaimer.
///
/// Edge cases: without permission (or after it was revoked while the form
/// was open) a "no permission" state replaces the form; a removed member
/// (`NOT_FOUND`) shows [EmergencyCardUnavailable]; a newer card arriving
/// while the form is open (the fresh card replacing an offline copy, or
/// someone else's save) is adopted when nothing was edited yet, otherwise a
/// warning says that saving replaces it.
class EmergencyCardFormScreen extends ConsumerWidget {
  const EmergencyCardFormScreen({super.key, required this.memberId});

  final String memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final canEdit = ref.watch(canEditEmergencyCardProvider(memberId));
    final memberName = ref
        .watch(emergencyCardMemberProvider(memberId))
        .value
        ?.name;

    final card = ref.watch(emergencyCardProvider(memberId));

    final Widget body;
    if (!canEdit) {
      body = EmergencyStateCard(
        icon: AppIcons.security,
        accent: EmergencyCardAccents.module,
        title: l10n.emergencyCardNoEditPermission,
        centered: true,
      );
    } else if (!card.isLoading && isEmergencyCardNotFound(card.error)) {
      body = const EmergencyCardUnavailable(centered: true);
    } else {
      body = AsyncValueView<EmergencyCard>(
        value: card,
        onRetry: () => ref.invalidate(emergencyCardProvider(memberId)),
        data: (card) => _EmergencyCardForm(
          // One form state per member; later refreshes never reset edits.
          key: ValueKey(memberId),
          memberId: memberId,
          memberName: memberName,
          initial: card,
        ),
      );
    }

    // Plain canvas app bar (docs/12-DESIGN_LANGUAGE.md §3b: forms never get
    // a coloured app bar); Material 3 keeps the status bar transparent. The
    // back button uses the thin app icon instead of Material's filled arrow.
    // TODO(visual-qa): move this `backButtonIconBuilder` into
    // `AppTheme.actionIconTheme` so every app bar gets it (handoff).
    return ActionIconTheme(
      data: ActionIconThemeData(
        backButtonIconBuilder: (_) => const Icon(AppIcons.back),
      ),
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.emergencyCardEditTitle)),
        body: ResponsiveCenter(child: body),
      ),
    );
  }
}

/// Text controllers of one emergency contact row.
class _ContactDraft {
  _ContactDraft([EmergencyContact? contact])
    : name = TextEditingController(text: contact?.name ?? ''),
      phone = TextEditingController(text: contact?.phone ?? ''),
      relation = TextEditingController(text: contact?.relation ?? '');

  final TextEditingController name;
  final TextEditingController phone;
  final TextEditingController relation;

  List<TextEditingController> get controllers => [name, phone, relation];

  EmergencyContact toContact() => EmergencyContact(
    name: name.text,
    phone: phone.text,
    relation: relation.text,
  );

  void dispose() {
    for (final c in controllers) {
      c.dispose();
    }
  }
}

class _EmergencyCardForm extends ConsumerStatefulWidget {
  const _EmergencyCardForm({
    super.key,
    required this.memberId,
    required this.memberName,
    required this.initial,
  });

  final String memberId;
  final String? memberName;
  final EmergencyCard initial;

  @override
  ConsumerState<_EmergencyCardForm> createState() => _EmergencyCardFormState();
}

class _EmergencyCardFormState extends ConsumerState<_EmergencyCardForm> {
  final _formKey = GlobalKey<FormState>();

  late BloodGroup _bloodGroup;
  late final ChipListController _allergies;
  late final ChipListController _medications;
  late final ChipListController _conditions;
  late final TextEditingController _doctorName;
  late final TextEditingController _doctorPhone;
  late final TextEditingController _insuranceProvider;
  late final TextEditingController _policyNumber;
  late final TextEditingController _notes;
  final List<_ContactDraft> _contacts = [];

  /// The card the form was filled from (what "unsaved changes" compares
  /// against).
  late EmergencyCard _initial;

  bool _dirty = false;
  bool _allowPop = false;

  /// Saved successfully; the form is closing (later card updates are ours).
  bool _closing = false;

  /// A different card arrived from the server after the user started
  /// editing: saving will replace it.
  bool _changedElsewhere = false;

  List<ChipListController> get _lists => [
    _allergies,
    _medications,
    _conditions,
  ];

  List<TextEditingController> get _textControllers => [
    _doctorName,
    _doctorPhone,
    _insuranceProvider,
    _policyNumber,
    _notes,
  ];

  @override
  void initState() {
    super.initState();
    final card = _initial = widget.initial;
    _bloodGroup = card.bloodGroup;
    _allergies = ChipListController(items: card.allergies);
    _medications = ChipListController(items: card.medications);
    _conditions = ChipListController(items: card.conditions);
    _doctorName = TextEditingController(text: card.doctorName ?? '');
    _doctorPhone = TextEditingController(text: card.doctorPhone ?? '');
    _insuranceProvider = TextEditingController(
      text: card.insuranceProvider ?? '',
    );
    _policyNumber = TextEditingController(
      text: card.insurancePolicyNumber ?? '',
    );
    _notes = TextEditingController(text: card.notes ?? '');
    _loadContacts(card);

    for (final list in _lists) {
      list
        ..addListener(_updateDirty)
        ..input.addListener(_updateDirty);
    }
    for (final c in _textControllers) {
      c.addListener(_updateDirty);
    }
  }

  @override
  void didUpdateWidget(_EmergencyCardForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.initial;
    if (_closing || identical(next, oldWidget.initial) || next == _initial) {
      return;
    }
    if (!_dirty) {
      // Nothing edited yet: take the newer card (e.g. the fresh card that
      // replaced the offline copy the form was opened with).
      _adopt(next);
      return;
    }
    // Edited: keep the user's work. Warn only about a real server change
    // (not the same card re-marked as an offline copy, not their own text).
    final changed =
        !next.isOfflineCopy &&
        !_sameContent(next, _initial) &&
        !_sameContent(next, _buildCard());
    if (changed && !_changedElsewhere) {
      setState(() => _changedElsewhere = true);
    }
  }

  @override
  void dispose() {
    for (final list in _lists) {
      list.dispose();
    }
    for (final c in _textControllers) {
      c.dispose();
    }
    for (final draft in _contacts) {
      draft.dispose();
    }
    super.dispose();
  }

  // ── State ────────────────────────────────────────────────────────────────

  void _addContactDraft(_ContactDraft draft) {
    for (final c in draft.controllers) {
      c.addListener(_updateDirty);
    }
    _contacts.add(draft);
  }

  void _loadContacts(EmergencyCard card) {
    for (final contact in card.emergencyContacts.take(
      EmergencyCardLimits.contactsMax,
    )) {
      _addContactDraft(_ContactDraft(contact));
    }
  }

  /// Refills every field from [card] (only while nothing was edited).
  void _adopt(EmergencyCard card) {
    _initial = card;
    final old = List.of(_contacts);
    _contacts.clear();
    // Their fields are still mounted during this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final draft in old) {
        draft.dispose();
      }
    });
    _loadContacts(card);
    _bloodGroup = card.bloodGroup;
    _allergies.setItems(card.allergies);
    _medications.setItems(card.medications);
    _conditions.setItems(card.conditions);
    _doctorName.text = card.doctorName ?? '';
    _doctorPhone.text = card.doctorPhone ?? '';
    _insuranceProvider.text = card.insuranceProvider ?? '';
    _policyNumber.text = card.insurancePolicyNumber ?? '';
    _notes.text = card.notes ?? '';
    _changedElsewhere = false;
    _updateDirty();
  }

  static bool _sameContent(EmergencyCard a, EmergencyCard b) =>
      normalizeEmergencyCard(a).sameContentAs(normalizeEmergencyCard(b));

  void _addContact() {
    if (_contacts.length >= EmergencyCardLimits.contactsMax) return;
    setState(() => _addContactDraft(_ContactDraft()));
  }

  void _removeContact(_ContactDraft draft) {
    setState(() => _contacts.remove(draft));
    // Its fields are still mounted during this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => draft.dispose());
    _updateDirty();
  }

  EmergencyCard _buildCard() => _initial.copyWith(
    bloodGroup: _bloodGroup,
    allergies: _allergies.items,
    medications: _medications.items,
    conditions: _conditions.items,
    doctorName: () => _doctorName.text,
    doctorPhone: () => _doctorPhone.text,
    insuranceProvider: () => _insuranceProvider.text,
    insurancePolicyNumber: () => _policyNumber.text,
    emergencyContacts: [for (final d in _contacts) d.toContact()],
    notes: () => _notes.text,
  );

  void _updateDirty() {
    if (!mounted) return;
    final pending = _lists.any((l) => l.input.text.trim().isNotEmpty);
    final dirty = pending || !_sameContent(_buildCard(), _initial);
    if (dirty != _dirty) setState(() => _dirty = dirty);
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  Future<void> _save() async {
    final l10n = context.l10n;
    if (ref.read(emergencyCardSaveControllerProvider)) return;
    // Keep entries that were typed but not added yet.
    for (final list in _lists) {
      list.commitPending();
    }
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      context.showInfo(l10n.emergencyCardFixErrors);
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      final saved = await ref
          .read(emergencyCardSaveControllerProvider.notifier)
          .save(widget.memberId, _buildCard());
      if (saved == null || !mounted) return;
      _closing = true;
      context.showSuccess(l10n.emergencyCardSaved);
      _leave(afterSave: true);
    } catch (e) {
      if (mounted) context.showError(e);
    }
  }

  /// Pops once the `PopScope` has been rebuilt to allow it. Opened without
  /// anything underneath (deep link), a save continues to the card instead.
  void _leave({bool afterSave = false}) {
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (context.canPop()) {
        context.pop();
      } else if (afterSave) {
        context.go(AppRoutes.emergencyCard(widget.memberId));
      }
    });
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
    if (discard && mounted) _leave();
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final saving = ref.watch(emergencyCardSaveControllerProvider);
    final contactsFull = _contacts.length >= EmergencyCardLimits.contactsMax;
    final memberName = widget.memberName;

    return PopScope(
      canPop: _allowPop || !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !saving) _confirmDiscard();
      },
      child: Column(
        children: [
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                children: [
                  if (memberName != null) ...[
                    Row(
                      children: [
                        const IconBadge(
                          icon: AppIcons.emergencyCard,
                          accent: EmergencyCardAccents.module,
                        ),
                        AppGap.hMd,
                        Expanded(
                          child: Text(
                            memberName,
                            style: theme.textTheme.titleLarge,
                          ),
                        ),
                      ],
                    ),
                    AppGap.lg,
                  ],
                  if (_initial.isOfflineCopy) ...[
                    CardNotice(
                      icon: AppIcons.offline,
                      accent: AppAccents.warning,
                      text: l10n.emergencyCardOfflineEditWarning,
                      liveRegion: true,
                    ),
                    AppGap.md,
                  ],
                  if (_changedElsewhere) ...[
                    CardNotice(
                      icon: AppIcons.warning,
                      accent: AppAccents.warning,
                      text: l10n.emergencyCardChangedWhileEditing,
                      liveRegion: true,
                    ),
                    AppGap.md,
                  ],
                  CardNotice(
                    icon: AppIcons.info,
                    accent: AppAccents.brand,
                    text:
                        '${l10n.emergencyCardDisclaimer}\n'
                        '${l10n.emergencyCardPrivacyNote}',
                  ),
                  AppGap.lg,
                  _FormSection(
                    icon: AppIcons.bloodGroup,
                    accent: EmergencyCardAccents.bloodGroup,
                    title: l10n.emergencyCardBloodGroup,
                    children: [
                      _BloodGroupPicker(
                        value: _bloodGroup,
                        onChanged: saving
                            ? null
                            : (g) {
                                setState(() => _bloodGroup = g);
                                _updateDirty();
                              },
                      ),
                    ],
                  ),
                  AppGap.md,
                  AppCard(
                    child: ChipListField(
                      controller: _allergies,
                      title: l10n.emergencyCardAllergies,
                      inputLabel: l10n.emergencyCardAllergyLabel,
                      hint: l10n.emergencyCardAllergyHint,
                      icon: AppIcons.allergy,
                      accent: EmergencyCardAccents.allergies,
                      warning: true,
                      enabled: !saving,
                    ),
                  ),
                  AppGap.md,
                  AppCard(
                    child: ChipListField(
                      controller: _medications,
                      title: l10n.emergencyCardMedications,
                      inputLabel: l10n.emergencyCardMedicationLabel,
                      hint: l10n.emergencyCardMedicationHint,
                      icon: AppIcons.medication,
                      accent: EmergencyCardAccents.medications,
                      enabled: !saving,
                    ),
                  ),
                  AppGap.md,
                  AppCard(
                    child: ChipListField(
                      controller: _conditions,
                      title: l10n.emergencyCardConditions,
                      inputLabel: l10n.emergencyCardConditionLabel,
                      hint: l10n.emergencyCardConditionHint,
                      icon: AppIcons.condition,
                      accent: EmergencyCardAccents.conditions,
                      enabled: !saving,
                    ),
                  ),
                  AppGap.md,
                  _FormSection(
                    icon: AppIcons.emergencyContact,
                    accent: EmergencyCardAccents.contacts,
                    title: l10n.emergencyCardContacts,
                    trailing: l10n.emergencyCardItemCount(
                      _contacts.length,
                      EmergencyCardLimits.contactsMax,
                    ),
                    children: [
                      Text(l10n.emergencyCardContactsNotice, style: muted),
                      for (var i = 0; i < _contacts.length; i++)
                        _ContactEditor(
                          key: ObjectKey(_contacts[i]),
                          number: i + 1,
                          draft: _contacts[i],
                          enabled: !saving,
                          onRemove: () => _removeContact(_contacts[i]),
                        ),
                      AppButton(
                        label: l10n.emergencyCardAddContact,
                        icon: AppIcons.addMember,
                        variant: AppButtonVariant.secondary,
                        onPressed: contactsFull || saving ? null : _addContact,
                      ),
                      if (contactsFull)
                        Text(
                          l10n.emergencyCardContactsLimit(
                            EmergencyCardLimits.contactsMax,
                          ),
                          style: muted,
                        ),
                    ],
                  ),
                  AppGap.md,
                  _FormSection(
                    icon: AppIcons.doctor,
                    accent: EmergencyCardAccents.doctor,
                    title: l10n.emergencyCardDoctor,
                    children: [
                      _LimitedTextField(
                        controller: _doctorName,
                        label: l10n.emergencyCardDoctorName,
                        maxLength: EmergencyCardLimits.textMaxLength,
                        enabled: !saving,
                        textCapitalization: TextCapitalization.words,
                      ),
                      _PhoneField(
                        controller: _doctorPhone,
                        label: l10n.emergencyCardDoctorPhone,
                        enabled: !saving,
                      ),
                    ],
                  ),
                  AppGap.md,
                  _FormSection(
                    icon: AppIcons.insurance,
                    accent: EmergencyCardAccents.insurance,
                    title: l10n.emergencyCardInsurance,
                    children: [
                      _LimitedTextField(
                        controller: _insuranceProvider,
                        label: l10n.emergencyCardInsuranceProvider,
                        maxLength: EmergencyCardLimits.textMaxLength,
                        enabled: !saving,
                        textCapitalization: TextCapitalization.words,
                      ),
                      _LimitedTextField(
                        controller: _policyNumber,
                        label: l10n.emergencyCardPolicyNumber,
                        maxLength: EmergencyCardLimits.textMaxLength,
                        enabled: !saving,
                      ),
                    ],
                  ),
                  AppGap.md,
                  _FormSection(
                    icon: AppIcons.notes,
                    accent: EmergencyCardAccents.notes,
                    title: l10n.emergencyCardNotes,
                    children: [
                      AppTextField(
                        controller: _notes,
                        label: l10n.emergencyCardNotes,
                        hint: l10n.emergencyCardNotesHint,
                        maxLines: 6,
                        maxLength: EmergencyCardLimits.notesMaxLength,
                        enabled: !saving,
                        textCapitalization: TextCapitalization.sentences,
                        validator: Validators.maxLength(
                          l10n,
                          EmergencyCardLimits.notesMaxLength,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Borderless bottom bar with the single gradient primary action.
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: AppButton(
                label: l10n.commonSave,
                icon: AppIcons.save,
                isLoading: saving,
                onPressed: _save,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A group of form fields in a borderless card, headed by a solid icon
/// badge in the section's colour, with even spacing.
class _FormSection extends StatelessWidget {
  const _FormSection({
    required this.icon,
    required this.accent,
    required this.title,
    required this.children,
    this.trailing,
  });

  final IconData icon;
  final AppAccent accent;
  final String title;
  final String? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          EmergencySectionTitle(
            icon: icon,
            accent: accent,
            title: title,
            trailing: trailing,
          ),
          for (final child in children) ...[AppGap.md, child],
        ],
      ),
    );
  }
}

/// Blood group as colourful single-choice chips (the eight groups and
/// "Unknown"): soft rose when not chosen, solid rose with white text when
/// chosen. Symbols stay left-to-right in RTL.
class _BloodGroupPicker extends StatelessWidget {
  const _BloodGroupPicker({required this.value, required this.onChanged});

  final BloodGroup value;

  /// `null` disables the chips (while saving).
  final ValueChanged<BloodGroup>? onChanged;

  static const _options = [...BloodGroup.known, BloodGroup.unknown];

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    const accent = EmergencyCardAccents.bloodGroup;
    final shades = context.accent(accent);
    final changed = onChanged;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final group in _options)
          Builder(
            builder: (context) {
              final selected = group == value;
              final foreground = selected ? Colors.white : shades.onContainer;
              return ChoiceChip(
                label: Text(
                  group.label(l10n),
                  textDirection: group.isKnown ? TextDirection.ltr : null,
                ),
                tooltip: group.semanticLabel(l10n),
                selected: selected,
                onSelected: changed == null ? null : (_) => changed(group),
                showCheckmark: false,
                avatar: Icon(
                  selected ? AppIcons.check : AppIcons.bloodGroup,
                  color: foreground,
                  size: AppSizes.iconXs,
                ),
                labelStyle: theme.textTheme.labelLarge?.copyWith(
                  color: foreground,
                  fontWeight: AppTypography.bold,
                ),
                backgroundColor: shades.container,
                // The deep shade keeps white text at AA contrast.
                selectedColor: accent.dark,
                side: BorderSide.none,
                shape: const RoundedRectangleBorder(
                  borderRadius: AppRadius.brPill,
                ),
              );
            },
          ),
      ],
    );
  }
}

/// Text field capped at [maxLength] characters without a visible counter.
class _LimitedTextField extends StatelessWidget {
  const _LimitedTextField({
    required this.controller,
    required this.label,
    required this.maxLength,
    this.hint,
    this.enabled = true,
    this.validator,
    this.textCapitalization = TextCapitalization.none,
  });

  final TextEditingController controller;
  final String label;
  final int maxLength;
  final String? hint;
  final bool enabled;
  final FormFieldValidator<String>? validator;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppTextField(
      controller: controller,
      label: label,
      hint: hint,
      enabled: enabled,
      textInputAction: TextInputAction.next,
      textCapitalization: textCapitalization,
      inputFormatters: [LengthLimitingTextInputFormatter(maxLength)],
      validator: Validators.compose([
        ?validator,
        Validators.maxLength(l10n, maxLength),
      ]),
    );
  }
}

class _PhoneField extends StatelessWidget {
  const _PhoneField({
    required this.controller,
    required this.label,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      controller: controller,
      label: label,
      prefixIcon: AppIcons.phone,
      keyboardType: TextInputType.phone,
      textInputAction: TextInputAction.next,
      enabled: enabled,
      inputFormatters: [
        LengthLimitingTextInputFormatter(EmergencyCardLimits.phoneMaxLength),
      ],
      validator: Validators.phone(context.l10n),
    );
  }
}

/// One emergency contact as a soft sky panel inside the contacts card.
/// The panel is keyed `emergencyContactEditor-<number>` (tests).
class _ContactEditor extends StatelessWidget {
  const _ContactEditor({
    super.key,
    required this.number,
    required this.draft,
    required this.onRemove,
    this.enabled = true,
  });

  final int number;
  final _ContactDraft draft;
  final VoidCallback onRemove;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final shades = context.accent(EmergencyCardAccents.contacts);
    return DecoratedBox(
      key: ValueKey('emergencyContactEditor-$number'),
      decoration: BoxDecoration(
        color: shades.container,
        borderRadius: AppRadius.brLg,
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.md,
          AppSpacing.xs,
          AppSpacing.xs,
          AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  AppIcons.member,
                  size: AppSizes.iconSm,
                  color: shades.foreground,
                ),
                AppGap.hSm,
                Expanded(
                  child: Text(
                    l10n.emergencyCardContactNumber(number),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: shades.onContainer,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: l10n.emergencyCardRemoveContact(number),
                  icon: const Icon(AppIcons.delete),
                  color: scheme.error,
                  onPressed: enabled ? onRemove : null,
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _LimitedTextField(
                    controller: draft.name,
                    label: l10n.emergencyCardContactName,
                    maxLength: EmergencyCardLimits.textMaxLength,
                    enabled: enabled,
                    textCapitalization: TextCapitalization.words,
                    // A contact needs a name once anything else is filled
                    // in; a completely empty row is simply dropped.
                    validator: (v) {
                      final other =
                          draft.phone.text.trim().isNotEmpty ||
                          draft.relation.text.trim().isNotEmpty;
                      return other && (v == null || v.trim().isEmpty)
                          ? l10n.validationRequired
                          : null;
                    },
                  ),
                  AppGap.md,
                  _PhoneField(
                    controller: draft.phone,
                    label: l10n.emergencyCardContactPhone,
                    enabled: enabled,
                  ),
                  AppGap.md,
                  _LimitedTextField(
                    controller: draft.relation,
                    label: l10n.emergencyCardContactRelation,
                    hint: l10n.emergencyCardContactRelationHint,
                    maxLength: EmergencyCardLimits.relationMaxLength,
                    enabled: enabled,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
