import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/utils/formatters.dart';

// Frosted "glass" building blocks for content that sits on a gradient
// (the Money header, goal cards, the goal detail header). Everything here is
// white-on-colour; never use these on the plain canvas.
//
// Candidates for `lib/core/widgets/` (the dashboard header has a private
// `_GlassStat` with the same look) — see docs/progress/rd-ledger.md.

/// Opacity of the frosted white fill behind glass pills and buttons.
const double _glassOpacity = 0.16;

/// Opacity of the frosted fill of small chips (slightly stronger so short
/// labels stay legible).
const double _glassChipOpacity = 0.22;

/// Opacity of a faded (disabled) white icon on a gradient.
const double _disabledOpacity = 0.4;

/// Opacity of the translucent track behind [OnGradientProgressBar].
const double _trackOpacity = 0.25;

/// Opacity of secondary white text / icons on a gradient.
const double onGradientMutedOpacity = 0.85;

/// Secondary white for labels on gradients.
Color get onGradientMuted =>
    Colors.white.withValues(alpha: onGradientMutedOpacity);

/// Frosted white panel with an icon, a small [label] and a big [value]
/// (e.g. "Income ₹2,05,000"). [value] scales down instead of wrapping so
/// long amounts always fit; [label] ellipsises.
class GlassStat extends StatelessWidget {
  const GlassStat({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

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
          color: Colors.white.withValues(alpha: _glassOpacity),
          borderRadius: AppRadius.brLg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: AppSizes.iconXs, color: Colors.white),
                AppGap.hXs,
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: onGradientMuted,
                    ),
                  ),
                ),
              ],
            ),
            AppGap.xxs,
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                value,
                maxLines: 1,
                style: theme.textTheme.titleMedium
                    ?.merge(AppTypography.tabularFigures)
                    .copyWith(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small frosted pill with an optional icon (scope "Family", goal status
/// "Achieved", "On track"). Long labels ellipsise.
class GlassChip extends StatelessWidget {
  const GlassChip({super.key, required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: _glassChipOpacity),
        borderRadius: AppRadius.brPill,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xxs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: AppSizes.iconXs, color: Colors.white),
              AppGap.hXs,
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Round frosted [IconButton] for headers on a gradient (back, month
/// arrows, overflow menus). Disabled buttons fade out.
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// Shared style, also for `PopupMenuButton`s on gradients.
  static ButtonStyle style() => IconButton.styleFrom(
    foregroundColor: Colors.white,
    backgroundColor: Colors.white.withValues(alpha: _glassOpacity),
    disabledForegroundColor: Colors.white.withValues(alpha: _disabledOpacity),
    disabledBackgroundColor: Colors.white.withValues(alpha: _glassOpacity / 2),
    minimumSize: const Size.square(AppSizes.minTapTarget),
  );

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: style(),
      icon: Icon(icon, size: AppSizes.iconSm),
    );
  }
}

/// White progress bar on a translucent white track, for gradients
/// ([AppProgressBar] uses the theme track, which reads grey on colour).
/// Animates to [value] (clamped 0–1) and announces a localised percentage.
class OnGradientProgressBar extends ConsumerWidget {
  const OnGradientProgressBar({
    super.key,
    required this.value,
    this.height = AppSizes.progressBar,
  });

  final double value;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = ref.watch(fmtProvider);
    final target = value.isFinite ? value.clamp(0.0, 1.0) : 0.0;
    final animate = !MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: target),
      duration: animate ? AppDurations.slow : Duration.zero,
      curve: Curves.easeOutCubic,
      builder: (context, animated, _) => LinearProgressIndicator(
        value: animated,
        minHeight: height,
        color: Colors.white,
        backgroundColor: Colors.white.withValues(alpha: _trackOpacity),
        borderRadius: AppRadius.brPill,
        semanticsValue: context.l10n.widgetProgressLabel(fmt.percent(target)),
      ),
    );
  }
}

/// Frosted rounded square holding a white thin icon — the leading mark of a
/// gradient card (like [ActionTile]'s icon square).
class GlassIcon extends StatelessWidget {
  const GlassIcon({
    super.key,
    required this.icon,
    this.size = AppSizes.badgeSm,
  });

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: _glassChipOpacity),
        borderRadius: AppRadius.brMd,
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: size * 0.55, color: Colors.white),
    );
  }
}

/// White progress ring on a translucent track with the percentage in the
/// middle (goal detail header). Animates to [value] (clamped 0–1); screen
/// readers hear [semanticsLabel].
class OnGradientProgressRing extends StatelessWidget {
  const OnGradientProgressRing({
    super.key,
    required this.value,
    required this.centerLabel,
    required this.semanticsLabel,
    this.size = AppSizes.iconHero + AppSpacing.lg,
  });

  final double value;

  /// Text in the middle, e.g. "21%" (scales down to fit).
  final String centerLabel;
  final String semanticsLabel;
  final double size;

  @override
  Widget build(BuildContext context) {
    final target = value.isFinite ? value.clamp(0.0, 1.0) : 0.0;
    final animate = !MediaQuery.disableAnimationsOf(context);
    final stroke = size / 10;
    return Semantics(
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: size,
          child: Stack(
            fit: StackFit.expand,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween<double>(end: target),
                duration: animate ? AppDurations.slow : Duration.zero,
                curve: Curves.easeOutCubic,
                builder: (context, animated, _) => CircularProgressIndicator(
                  value: animated,
                  strokeWidth: stroke,
                  strokeCap: StrokeCap.round,
                  color: Colors.white,
                  backgroundColor: Colors.white.withValues(
                    alpha: _trackOpacity,
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(stroke * 1.5),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      centerLabel,
                      maxLines: 1,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.merge(AppTypography.tabularFigures)
                          .copyWith(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
