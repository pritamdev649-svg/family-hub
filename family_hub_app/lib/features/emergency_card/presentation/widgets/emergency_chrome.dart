import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/providers/core_providers.dart';
import 'package:family_hub/core/widgets/widgets.dart';

// Chrome for the emergency card screens that open with a full-bleed
// `GradientHeader` instead of an app bar (docs/12-DESIGN_LANGUAGE.md §3b).
//
// TODO(visual-qa): the header top bar and the glass pill / icon are generic —
// promote them to `core/widgets/gradient_header.dart` so every pushed screen
// with a gradient header shares them (handoff in docs/progress/rd-emergency.md).

/// Opacity of the frosted "glass" fill on gradients.
const double _glassOpacity = 0.18;

/// Opacity of secondary white text on gradients.
const double _mutedOnGradientOpacity = 0.85;

/// Secondary (slightly transparent) white for captions on gradients.
Color mutedOnGradient() =>
    Colors.white.withValues(alpha: _mutedOnGradientOpacity);

/// Frosted "glass" fill for buttons, pills and badges on gradients.
Color glassOnGradient() => Colors.white.withValues(alpha: _glassOpacity);

/// Top row of a gradient header on a pushed screen: a frosted back button
/// (only when there is something to go back to, like an app bar) and
/// trailing [actions]. Collapses to nothing when it has nothing to show.
class EmergencyHeaderTopBar extends StatelessWidget {
  const EmergencyHeaderTopBar({super.key, this.actions = const []});

  /// Usually [EmergencyGlassIconButton]s.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final canPop = ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
    if (!canPop && actions.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        if (canPop)
          EmergencyGlassIconButton(
            icon: AppIcons.back,
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        const Spacer(),
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) AppGap.hSm,
          actions[i],
        ],
      ],
    );
  }
}

/// Round frosted icon button with a white thin icon, for gradients.
class EmergencyGlassIconButton extends StatelessWidget {
  const EmergencyGlassIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: glassOnGradient(),
        iconSize: AppSizes.iconMd,
        minimumSize: const Size.square(AppSizes.minTapTarget),
      ),
    );
  }
}

/// Frosted rounded square holding a white thin icon — the "icon badge" of
/// solid gradient cards and headers (like [ActionTile]'s icon square).
class EmergencyGlassIcon extends StatelessWidget {
  const EmergencyGlassIcon({
    super.key,
    required this.icon,
    this.size = AppSizes.badgeSm,
  });

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: glassOnGradient(),
          borderRadius: AppRadius.brMd,
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: size * 0.5, color: Colors.white),
      ),
    );
  }
}

/// Frosted pill for headers: an optional big [value] (a count) above a
/// [label], or — without a value — an icon and a one-line label (status).
class EmergencyGlassPill extends StatelessWidget {
  const EmergencyGlassPill({
    super.key,
    required this.icon,
    required this.label,
    this.value,
  });

  final IconData icon;
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = mutedOnGradient();
    final v = value;

    final Widget content;
    if (v == null) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: AppSizes.iconXs, color: Colors.white),
          AppGap.hXs,
          Flexible(
            child: Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(color: Colors.white),
            ),
          ),
        ],
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: AppSizes.iconXs, color: Colors.white),
              AppGap.hXs,
              Flexible(
                child: Text(
                  v,
                  maxLines: 1,
                  style: theme.textTheme.titleLarge
                      ?.merge(AppTypography.tabularFigures)
                      .copyWith(color: Colors.white),
                ),
              ),
            ],
          ),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(color: muted),
          ),
        ],
      );
    }

    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: glassOnGradient(),
          borderRadius: v == null ? AppRadius.brPill : AppRadius.brLg,
        ),
        child: content,
      ),
    );
  }
}

/// The app's [OfflineBanner] as a rounded strip inside the content column
/// (the gradient header sits behind the status bar, so the banner cannot go
/// above it). Takes no space while online.
class EmergencyOfflineNotice extends ConsumerWidget {
  const EmergencyOfflineNotice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(connectivityStatusProvider).isOffline;
    if (!offline) return const SizedBox.shrink();
    return const Padding(
      padding: EdgeInsets.only(bottom: AppSpacing.sm),
      child: ClipRRect(borderRadius: AppRadius.brMd, child: OfflineBanner()),
    );
  }
}
