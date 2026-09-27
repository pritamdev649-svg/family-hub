import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/family/presentation/family_style.dart';
import 'package:family_hub/features/family/presentation/widgets/family_glass.dart';

/// The family's "membership card": a solid blue gradient card (like a
/// payment card) with the family name and — for admins — the invite code in
/// big equal-width characters plus frosted copy / regenerate buttons.
///
/// Without a [code] (members never receive it) the card says to ask an
/// admin instead.
class InviteCodeCard extends StatelessWidget {
  const InviteCodeCard({
    super.key,
    required this.familyName,
    this.code,
    this.onRegenerate,
    this.regenerating = false,
    this.enabled = true,
  });

  final String familyName;

  /// The invite code; `null` for members.
  final String? code;

  /// Creates a new code (admins); hides the button when `null`.
  final VoidCallback? onRegenerate;

  /// Shows the busy state on the "New code" button.
  final bool regenerating;

  /// `false` while another settings action runs.
  final bool enabled;

  Future<void> _copy(BuildContext context, String code) async {
    final message = context.l10n.familyInviteCodeCopied;
    try {
      await Clipboard.setData(ClipboardData(text: code));
      if (context.mounted) context.showSuccess(message);
    } catch (e) {
      if (context.mounted) context.showError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final code = this.code;
    final muted = FamilyStyle.mutedOnGradient;

    return GradientCard(
      // Solid blue (not the sky → blue hero gradient): white text stays
      // readable on every part of the card.
      gradient: AppGradients.of(FamilyStyle.accent),
      glowColor: FamilyStyle.accent.base,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const _GlassSquare(icon: AppIcons.family),
              AppGap.hMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      familyName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                      ),
                    ),
                    Semantics(
                      header: true,
                      child: Text(
                        l10n.familyInviteCodeTitle,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              AppGap.hSm,
              ExcludeSemantics(
                child: Icon(
                  AppIcons.inviteCode,
                  size: AppSizes.iconLg,
                  color: muted,
                ),
              ),
            ],
          ),
          AppGap.xl,
          if (code == null)
            Text(
              l10n.familyInviteCodeAdminOnly,
              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white),
            )
          else ...[
            InviteCodeCells(code: code),
            AppGap.md,
            Text(
              l10n.familyInviteCodeMessage,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
            AppGap.lg,
            FamilyFrostedButtons(
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  AppButton(
                    label: l10n.familyCopyInviteCode,
                    icon: AppIcons.copy,
                    variant: AppButtonVariant.tonal,
                    expand: false,
                    onPressed: () => _copy(context, code),
                  ),
                  if (onRegenerate != null)
                    AppButton(
                      label: l10n.familyNewInviteCode,
                      icon: AppIcons.sync,
                      variant: AppButtonVariant.tonal,
                      expand: false,
                      isLoading: regenerating,
                      onPressed: enabled ? onRegenerate : null,
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Frosted rounded square with a white thin icon (the card's "chip").
class _GlassSquare extends StatelessWidget {
  const _GlassSquare({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: AppSizes.badgeMd,
        height: AppSizes.badgeMd,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: FamilyStyle.glassFillStrong),
          borderRadius: AppRadius.brMd,
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: AppSizes.iconMd, color: Colors.white),
      ),
    );
  }
}

/// The code as one frosted, equal-width cell per character (a monospace
/// look without a hard-coded font) in bold white — for use on a gradient.
/// Always left-to-right, also in RTL languages, and read character by
/// character by screen readers.
class InviteCodeCells extends StatelessWidget {
  const InviteCodeCells({super.key, required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chars = code.characters.toList();
    final style = theme.textTheme.headlineMedium
        ?.merge(AppTypography.tabularFigures)
        .copyWith(color: Colors.white, fontWeight: AppTypography.bold);

    return Semantics(
      label: context.l10n.familyInviteCodeSemantics(chars.join(' ')),
      excludeSemantics: true,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: [
            for (var i = 0; i < chars.length; i++) ...[
              if (i > 0) AppGap.hXs,
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(
                      alpha: FamilyStyle.glassFill,
                    ),
                    borderRadius: AppRadius.brSm,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.md,
                      horizontal: AppSpacing.xxs,
                    ),
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(chars[i], style: style),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
