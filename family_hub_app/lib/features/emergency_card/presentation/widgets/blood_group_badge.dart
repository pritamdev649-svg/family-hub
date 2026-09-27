import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/features/emergency_card/domain/emergency_card.dart';
import 'package:family_hub/features/emergency_card/presentation/emergency_card_labels.dart';
import 'package:family_hub/features/emergency_card/presentation/emergency_card_style.dart';
import 'package:family_hub/features/emergency_card/presentation/widgets/emergency_chrome.dart';

/// Size / surface variants of [BloodGroupBadge].
enum BloodGroupBadgeSize {
  /// List tiles: a solid rose pill with a drop icon and the symbol.
  small,

  /// Card header on a normal surface: solid rose square with a
  /// "Blood group" caption above a large symbol.
  large,

  /// On a gradient header: a big white square with the symbol in the
  /// emergency red.
  header,

  /// Responder view: very large symbol on solid emergency red.
  hero,
}

/// A member's blood group. Known groups are painted in the module's rose
/// (or emergency red / white where they have to stand out); an unknown group
/// is a quiet neutral badge ("?" in lists). The symbol is always laid out
/// left-to-right so `AB+` never turns into `+AB` in RTL.
class BloodGroupBadge extends StatelessWidget {
  const BloodGroupBadge({
    super.key,
    required this.group,
    this.size = BloodGroupBadgeSize.small,
  });

  final BloodGroup group;
  final BloodGroupBadgeSize size;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic = context.semanticColors;
    final text = theme.textTheme;
    final known = group.isKnown;
    const accent = EmergencyCardAccents.bloodGroup;

    // Background (solid colour or gradient) and foreground per variant.
    final (Color? color, Gradient? gradient, Color foreground) = switch (size) {
      BloodGroupBadgeSize.small || BloodGroupBadgeSize.large =>
        known
            ? (null, AppGradients.of(accent), Colors.white)
            : (scheme.surfaceContainerHighest, null, scheme.onSurfaceVariant),
      BloodGroupBadgeSize.header =>
        known
            ? (Colors.white, null, semantic.sos)
            : (glassOnGradient(), null, Colors.white),
      BloodGroupBadgeSize.hero =>
        known
            ? (semantic.sos, null, semantic.onSos)
            : (scheme.surfaceContainerHighest, null, scheme.onSurface),
    };

    final symbol = size == BloodGroupBadgeSize.small
        ? (known ? group.wireName : '?')
        : group.label(l10n);
    final symbolStyle = switch (size) {
      BloodGroupBadgeSize.small => text.titleSmall,
      BloodGroupBadgeSize.large =>
        known ? text.headlineMedium : text.titleMedium,
      BloodGroupBadgeSize.header =>
        known ? text.displayMedium : text.titleLarge,
      BloodGroupBadgeSize.hero =>
        known ? text.displayLarge : text.headlineMedium,
    };

    final symbolText = Text(
      symbol,
      textAlign: TextAlign.center,
      // Symbols are LTR; the translated "Unknown" follows the locale.
      textDirection: known ? TextDirection.ltr : null,
      style: symbolStyle?.copyWith(
        color: foreground,
        fontWeight: AppTypography.extraBold,
      ),
    );

    final Widget content;
    if (size == BloodGroupBadgeSize.small) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(AppIcons.bloodGroup, size: AppSizes.iconXs, color: foreground),
          AppGap.hXxs,
          Flexible(child: symbolText),
        ],
      );
    } else {
      final captionStyle = size == BloodGroupBadgeSize.hero
          ? text.labelLarge
          : text.labelMedium;
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                AppIcons.bloodGroup,
                size: AppSizes.iconXs,
                color: foreground,
              ),
              AppGap.hXs,
              Flexible(
                child: Text(
                  l10n.emergencyCardBloodGroup,
                  textAlign: TextAlign.center,
                  style: captionStyle?.copyWith(color: foreground),
                ),
              ),
            ],
          ),
          AppGap.xxs,
          symbolText,
        ],
      );
    }

    final (EdgeInsets padding, BorderRadius radius) = switch (size) {
      BloodGroupBadgeSize.small => (
        const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        AppRadius.brPill,
      ),
      BloodGroupBadgeSize.large => (
        const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        AppRadius.brLg,
      ),
      BloodGroupBadgeSize.header => (
        const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        AppRadius.brCard,
      ),
      BloodGroupBadgeSize.hero => (
        const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.lg,
        ),
        AppRadius.brCard,
      ),
    };

    return Semantics(
      label: group.semanticLabel(l10n),
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: size == BloodGroupBadgeSize.small
              ? AppSizes.badgeMd
              : AppSizes.minTapTarget,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            gradient: gradient,
            borderRadius: radius,
          ),
          child: Padding(
            padding: padding,
            child: Center(widthFactor: 1, heightFactor: 1, child: content),
          ),
        ),
      ),
    );
  }
}
