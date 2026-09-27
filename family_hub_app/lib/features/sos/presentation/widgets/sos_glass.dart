import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/sos/presentation/sos_style.dart';

// Frosted white building blocks for content on the SOS red gradients
// (headers, alert cards) — same look as the dashboard header's glass stats.

/// Round frosted icon button with a white thin icon (48 dp target).
class SosGlassIconButton extends StatelessWidget {
  const SosGlassIconButton({
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
      style: IconButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: SosStyle.glassFill),
        foregroundColor: Colors.white,
        disabledForegroundColor: Colors.white.withValues(
          alpha: SosStyle.disabledOpacity,
        ),
        minimumSize: const Size.square(AppSizes.minTapTarget),
      ),
      icon: Icon(icon, size: AppSizes.iconMd),
    );
  }
}

/// Top row of a pushed screen's gradient header: a frosted back button
/// (only when there is a page to go back to, like an `AppBar`) and a small
/// [title]. Renders nothing when there is neither.
class SosHeaderTopBar extends StatelessWidget {
  const SosHeaderTopBar({super.key, this.title});

  final String? title;

  @override
  Widget build(BuildContext context) {
    final canGoBack = ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
    final text = title;
    if (!canGoBack && text == null) return const SizedBox.shrink();
    return Row(
      children: [
        if (canGoBack) ...[
          SosGlassIconButton(
            icon: AppIcons.back,
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            // `maybePop` respects `PopScope` like the app bar's back button.
            onPressed: () => Navigator.maybePop(context),
          ),
          AppGap.hMd,
        ],
        if (text != null)
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: SosStyle.mutedOnGradient),
            ),
          ),
      ],
    );
  }
}

/// Small frosted pill with an optional thin [icon] or [leading] widget
/// (e.g. a live dot). Wraps its label onto several lines with large text.
///
/// With [semanticsLabel] screen readers hear "<semanticsLabel>, <label>"
/// (e.g. "Your location during SOS, Only during SOS").
class SosGlassPill extends StatelessWidget {
  const SosGlassPill({
    super.key,
    required this.label,
    this.icon,
    this.leading,
    this.semanticsLabel,
  });

  final String label;
  final IconData? icon;
  final Widget? leading;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final lead =
        leading ??
        (icon == null
            ? null
            : Icon(icon, size: AppSizes.iconXs, color: Colors.white));
    final pill = DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: SosStyle.glassFill),
        borderRadius: AppRadius.brPill,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (lead != null) ...[lead, AppGap.hXs],
            Flexible(
              child: Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
    final description = semanticsLabel;
    if (description == null) return pill;
    return Semantics(
      container: true,
      label: description,
      value: label,
      excludeSemantics: true,
      child: pill,
    );
  }
}

/// A member avatar inside a frosted white ring (made of a fill, not a
/// border), for avatars on a red gradient.
class SosAvatarRing extends StatelessWidget {
  const SosAvatarRing({
    super.key,
    required this.name,
    required this.avatarUrl,
    this.radius = AppSizes.avatarMd,
  });

  final String? name;
  final String? avatarUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: SosStyle.glassFillStrong),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxs),
        child: MemberAvatar(name: name, avatarUrl: avatarUrl, radius: radius),
      ),
    );
  }
}
