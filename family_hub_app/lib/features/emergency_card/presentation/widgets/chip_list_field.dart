import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/emergency_card/domain/emergency_card.dart';
import 'package:family_hub/features/emergency_card/presentation/widgets/emergency_section.dart';

/// Result of [ChipListController.add].
enum ChipAddResult { added, empty, duplicate, full, tooLong }

/// State of a [ChipListField]: the entries plus the text being typed.
/// Owned (and disposed) by the form, like a `TextEditingController`.
class ChipListController extends ChangeNotifier {
  ChipListController({
    Iterable<String> items = const [],
    this.maxItems = EmergencyCardLimits.listMaxItems,
    this.maxItemLength = EmergencyCardLimits.listItemMaxLength,
  }) : _items = EmergencyCard.cleanList(items).take(maxItems).toList();

  final int maxItems;
  final int maxItemLength;

  /// The text field where the next entry is typed.
  final TextEditingController input = TextEditingController();

  final List<String> _items;

  List<String> get items => List.unmodifiable(_items);
  int get length => _items.length;
  bool get isFull => _items.length >= maxItems;

  /// Adds [text] (default: the typed text). On success the input is cleared.
  /// Duplicates are matched case-insensitively.
  ChipAddResult add([String? text]) {
    final value = (text ?? input.text).trim();
    if (value.isEmpty) return ChipAddResult.empty;
    if (value.length > maxItemLength) return ChipAddResult.tooLong;
    final lower = value.toLowerCase();
    if (_items.any((i) => i.toLowerCase() == lower)) {
      return ChipAddResult.duplicate;
    }
    if (isFull) return ChipAddResult.full;
    _items.add(value);
    if (text == null) input.clear();
    notifyListeners();
    return ChipAddResult.added;
  }

  void removeAt(int index) {
    if (index < 0 || index >= _items.length) return;
    _items.removeAt(index);
    notifyListeners();
  }

  /// Replaces every entry (cleaned and capped like the constructor) and
  /// clears the input, e.g. when the form adopts a newer card.
  void setItems(Iterable<String> items) {
    _items
      ..clear()
      ..addAll(EmergencyCard.cleanList(items).take(maxItems));
    input.clear();
    notifyListeners();
  }

  /// Adds whatever is still typed in the input (called before saving so
  /// nothing typed is lost). A duplicate is simply cleared; a full list keeps
  /// the text so the field's validator can point at it.
  ChipAddResult commitPending() {
    final result = add();
    if (result == ChipAddResult.duplicate) input.clear();
    return result;
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }
}

/// Editable list of short entries shown as removable chips (allergies,
/// medications, conditions). Type an entry and press the add button or the
/// keyboard's done key; entries are capped at [ChipListController.maxItems]
/// × [ChipListController.maxItemLength] characters.
///
/// Headed by a solid [IconBadge] in [accent]; chips are borderless soft
/// tints of the same accent and the add button is a solid round button.
/// Place it in a card (e.g. `AppCard`).
class ChipListField extends StatefulWidget {
  const ChipListField({
    super.key,
    required this.controller,
    required this.title,
    required this.inputLabel,
    required this.icon,
    required this.accent,
    this.hint,
    this.warning = false,
    this.enabled = true,
  });

  final ChipListController controller;

  /// Section title above the chips, e.g. "Allergies".
  final String title;

  /// Label of the input, e.g. "Add an allergy".
  final String inputLabel;
  final String? hint;

  /// Icon of the section badge.
  final IconData icon;

  /// Colour of the badge, the chips and the add button.
  final AppAccent accent;

  /// Marks every chip with a warning icon (allergies).
  final bool warning;
  final bool enabled;

  @override
  State<ChipListField> createState() => _ChipListFieldState();
}

class _ChipListFieldState extends State<ChipListField> {
  String? _error;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    widget.controller.input.addListener(_onTyped);
    _hasText = widget.controller.input.text.trim().isNotEmpty;
  }

  @override
  void didUpdateWidget(ChipListField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChanged);
      oldWidget.controller.input.removeListener(_onTyped);
      widget.controller.addListener(_onChanged);
      widget.controller.input.addListener(_onTyped);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    widget.controller.input.removeListener(_onTyped);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  /// Rebuilds when the add button's enabled state changes and clears a
  /// stale "already in the list" message.
  void _onTyped() {
    if (!mounted) return;
    final hasText = widget.controller.input.text.trim().isNotEmpty;
    if (_error != null || hasText != _hasText) {
      setState(() {
        _error = null;
        _hasText = hasText;
      });
    }
  }

  void _add() {
    final l10n = context.l10n;
    final c = widget.controller;
    final result = c.add();
    setState(() {
      _error = switch (result) {
        ChipAddResult.duplicate => l10n.emergencyCardDuplicateItem,
        ChipAddResult.full => l10n.emergencyCardListFull(c.maxItems),
        ChipAddResult.tooLong => l10n.validationMaxLength(c.maxItemLength),
        ChipAddResult.added || ChipAddResult.empty => null,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final shades = context.accent(widget.accent);
    final c = widget.controller;
    final items = c.items;
    final typed = c.input.text.trim();
    final canAdd = widget.enabled && !c.isFull && typed.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        EmergencySectionTitle(
          icon: widget.icon,
          accent: widget.accent,
          title: widget.title,
          trailing: l10n.emergencyCardItemCount(items.length, c.maxItems),
          trailingColor: c.isFull
              ? context.accent(AppAccents.warning).foreground
              : null,
        ),
        AppGap.md,
        if (items.isNotEmpty) ...[
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (var i = 0; i < items.length; i++)
                InputChip(
                  label: Text(items[i]),
                  labelStyle: theme.textTheme.labelLarge?.copyWith(
                    color: shades.onContainer,
                    fontWeight: AppTypography.semiBold,
                  ),
                  backgroundColor: shades.container,
                  side: BorderSide.none,
                  shape: const RoundedRectangleBorder(
                    borderRadius: AppRadius.brMd,
                  ),
                  avatar: widget.warning
                      ? Icon(AppIcons.warning, color: shades.foreground)
                      : null,
                  deleteIcon: const Icon(AppIcons.close, size: AppSizes.iconXs),
                  deleteIconColor: shades.foreground,
                  onDeleted: widget.enabled ? () => c.removeAt(i) : null,
                  deleteButtonTooltipMessage: l10n.emergencyCardRemoveItem(
                    items[i],
                  ),
                ),
            ],
          ),
          AppGap.md,
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AppTextField(
                controller: c.input,
                label: widget.inputLabel,
                hint: widget.hint,
                enabled: widget.enabled && !c.isFull,
                textInputAction: TextInputAction.done,
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(c.maxItemLength),
                ],
                onSubmitted: (_) => _add(),
                validator: (v) {
                  final text = v?.trim() ?? '';
                  if (text.isEmpty) return null;
                  if (c.isFull) return l10n.emergencyCardListFull(c.maxItems);
                  if (text.length > c.maxItemLength) {
                    return l10n.validationMaxLength(c.maxItemLength);
                  }
                  return null;
                },
              ),
            ),
            AppGap.hSm,
            Padding(
              padding: const EdgeInsetsDirectional.only(top: AppSpacing.xs),
              child: IconButton.filled(
                tooltip: l10n.emergencyCardAddItem(
                  typed.isEmpty ? widget.title : typed,
                ),
                onPressed: canAdd ? _add : null,
                icon: const Icon(AppIcons.add),
                style: IconButton.styleFrom(
                  // The deep shade keeps the white icon at AA contrast.
                  backgroundColor: widget.accent.dark,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
        if (_error != null || c.isFull)
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: AppSpacing.lg,
              top: AppSpacing.xs,
            ),
            child: Text(
              _error ?? l10n.emergencyCardListFull(c.maxItems),
              style: theme.textTheme.bodySmall?.copyWith(
                color: _error != null ? scheme.error : scheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}
