import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/utils/formatters.dart';
import 'package:family_hub/features/notices/application/notices_providers.dart';
import 'package:family_hub/shared/providers/shared_providers.dart';

/// Content of the amber full-bleed header of the notice board (rendered
/// inside `GradientHeaderScrollView`, so it starts behind the transparent
/// status bar): back button, family name, "Notice board", a short subtitle
/// and — once the board has loaded — two frosted stat pills (notices on the
/// board, pinned notices).
///
/// Text and icons are white (the header's default); everything scales with
/// the text size and mirrors in right-to-left layouts.
class NoticesHeader extends ConsumerWidget {
  const NoticesHeader({super.key, this.board});

  /// Secondary white text / icons on the gradient (same as the dashboard
  /// header).
  static const double onGradientOpacity = 0.85;

  /// Frosted white fill of the glass pills, badge and back button.
  static const double glassOpacity = 0.16;

  /// The loaded board, `null` while it loads or failed to load (the stat
  /// pills are hidden then).
  final NoticeListState? board;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final fmt = ref.watch(fmtProvider);
    final familyName = ref.watch(
      currentFamilyProvider.select((f) => f?.name.trim() ?? ''),
    );
    // Same rule as an AppBar's automatic back button.
    final canPop = ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
    final onGradient = Colors.white.withValues(alpha: onGradientOpacity);
    final board = this.board;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (canPop) ...[
              _GlassIconButton(
                icon: AppIcons.back,
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: () => Navigator.maybePop(context),
              ),
              AppGap.hMd,
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (familyName.isNotEmpty) ...[
                    Row(
                      children: [
                        Icon(
                          AppIcons.family,
                          size: AppSizes.iconSm,
                          color: onGradient,
                        ),
                        AppGap.hXs,
                        Flexible(
                          child: Text(
                            familyName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: onGradient,
                            ),
                          ),
                        ),
                      ],
                    ),
                    AppGap.xxs,
                  ],
                  Semantics(
                    header: true,
                    child: Text(
                      l10n.noticesTitle,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            AppGap.hMd,
            const _GlassBadge(icon: AppIcons.notice),
          ],
        ),
        AppGap.sm,
        Text(
          l10n.noticesSubtitle,
          style: theme.textTheme.bodyMedium?.copyWith(color: onGradient),
        ),
        if (board != null) ...[
          AppGap.lg,
          Row(
            children: [
              Expanded(
                child: _GlassStat(
                  icon: AppIcons.noticeOutlined,
                  // A notice posted a moment ago is already in the list but
                  // not yet in the server total.
                  value: fmt.number(
                    math.max(board.paged.total, board.items.length),
                  ),
                  label: l10n.noticesStatTotal,
                ),
              ),
              AppGap.hSm,
              Expanded(
                child: _GlassStat(
                  icon: AppIcons.pin,
                  // Pinned notices sort first, so the loaded window holds
                  // all of them.
                  value: fmt.number(board.items.where((n) => n.pinned).length),
                  label: l10n.noticesPinned,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Frosted white circle button for use on the header gradient.
class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: Colors.white.withValues(
          alpha: NoticesHeader.glassOpacity,
        ),
        foregroundColor: Colors.white,
        minimumSize: const Size.square(AppSizes.minTapTarget),
      ),
      icon: Icon(icon, size: AppSizes.iconMd),
    );
  }
}

/// Decorative frosted square with the module icon (end of the title row).
class _GlassBadge extends StatelessWidget {
  const _GlassBadge({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: AppSizes.badgeLg,
        height: AppSizes.badgeLg,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: NoticesHeader.glassOpacity),
          borderRadius: AppRadius.brLg,
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: AppSizes.iconLg, color: Colors.white),
      ),
    );
  }
}

/// Frosted white pill with a number and a label, for use on the header
/// gradient (same look as the dashboard header's stats).
class _GlassStat extends StatelessWidget {
  const _GlassStat({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: NoticesHeader.glassOpacity),
          borderRadius: AppRadius.brLg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: AppSizes.iconXs, color: Colors.white),
                AppGap.hXs,
                Flexible(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge
                        ?.merge(AppTypography.tabularFigures)
                        .copyWith(color: Colors.white),
                  ),
                ),
              ],
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: Colors.white.withValues(
                  alpha: NoticesHeader.onGradientOpacity,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
