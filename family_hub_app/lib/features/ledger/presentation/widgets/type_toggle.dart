import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/features/ledger/domain/ledger_entry.dart';
import 'package:family_hub/features/ledger/presentation/ledger_labels.dart';

/// Income / Expense switch: a borderless pill track (canvas colour) whose
/// selected half fills with that type's gradient (income emerald, expense
/// rose) and white text. Used by the entry form and the category breakdown.
///
/// [onChanged] null renders it read-only (e.g. a goal contribution, whose
/// type is fixed). Each half is a ≥ 48 dp button for screen readers
/// ("Income, selected").
class LedgerTypeToggle extends StatelessWidget {
  const LedgerTypeToggle({
    super.key,
    required this.selected,
    required this.onChanged,
    this.types = const [LedgerType.income, LedgerType.expense],
    this.dense = false,
  });

  final LedgerType selected;
  final ValueChanged<LedgerType>? onChanged;

  /// Order of the halves.
  final List<LedgerType> types;

  /// Hug the labels instead of stretching (inside card headers).
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final track = context.semanticColors.canvas;
    final children = [
      for (final type in types)
        _Segment(
          type: type,
          selected: type == selected,
          dense: dense,
          onTap: onChanged == null || type == selected
              ? null
              : () => onChanged!(type),
          enabled: onChanged != null,
        ),
    ];
    return DecoratedBox(
      decoration: BoxDecoration(color: track, borderRadius: AppRadius.brPill),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxs),
        child: Row(
          mainAxisSize: dense ? MainAxisSize.min : MainAxisSize.max,
          children: [
            // Dense halves hug their labels but still shrink (labels
            // ellipsise) when the space is too narrow.
            for (final child in children)
              dense ? Flexible(child: child) : Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.type,
    required this.selected,
    required this.dense,
    required this.onTap,
    required this.enabled,
  });

  final LedgerType type;
  final bool selected;
  final bool dense;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final shades = context.accent(type.accent);
    final animate = !MediaQuery.disableAnimationsOf(context);
    final Color foreground;
    if (selected) {
      foreground = Colors.white;
    } else if (enabled) {
      foreground = shades.foreground;
    } else {
      foreground = theme.colorScheme.onSurfaceVariant;
    }

    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      inMutuallyExclusiveGroup: true,
      child: AnimatedContainer(
        duration: animate ? AppDurations.fast : Duration.zero,
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          gradient: selected ? AppGradients.of(type.accent) : null,
          borderRadius: AppRadius.brPill,
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: type.accent.base.withValues(
                      alpha: AppColors.glowOpacity,
                    ),
                    blurRadius: AppSizes.cardShadowBlur / 2,
                    offset: const Offset(0, AppSpacing.xxs),
                  ),
                ]
              : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: AppSizes.minTapTarget,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                // Icon + label shrink together (never truncated) when a
                // half is too narrow — large text, long translations.
                child: Center(
                  widthFactor: 1,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          type.icon,
                          size: AppSizes.iconSm,
                          color: foreground,
                        ),
                        AppGap.hXs,
                        Text(
                          type.label(l10n),
                          maxLines: 1,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: foreground,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
