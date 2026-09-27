import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/widgets/widgets.dart';

/// A titled group of [SettingsTile]s on one borderless [AppCard], separated
/// by hairline dividers inset past the icon badges (docs/12 §3 "Settings /
/// More"). Renders nothing when [children] is empty, so rows that depend on
/// permissions can use collection-`if`s.
///
/// [tint] gives the whole card a module's soft background, e.g.
/// `AppAccents.sos` for the log-out / delete "danger" rows.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    this.title,
    this.icon,
    this.accent,
    this.tint,
    required this.children,
  });

  final String? title;

  /// Thin icon before the [title], in [accent].
  final IconData? icon;
  final AppAccent? accent;
  final AppAccent? tint;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    final divider = Divider(
      height: AppSizes.hairline,
      thickness: AppSizes.hairline,
      // Starts under the title text, past the badge (RTL-aware).
      indent: SettingsTile.contentInset,
      color: context.semanticColors.border,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null)
          SectionHeader(title: title!, icon: icon, accent: accent),
        AppCard(
          accent: tint,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) divider,
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// One row of a settings list, like a modern fintech transaction row: a
/// solid [IconBadge] in the row's [accent] with a thin white icon, the
/// [title] (plus an optional [subtitle] below it), the current [value] at
/// the end and a chevron when the row navigates.
///
/// * [destructive] rows (log out, leave, delete) use the SOS red.
/// * While [busy] the row shows a spinner and ignores taps.
/// * Disabled rows ([enabled] false) are dimmed and ignore taps.
/// * Large text wraps. The [value] moves below the title when the two do
///   not fit on one line (so words never break mid-word).
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.accent = AppAccents.settings,
    this.subtitle,
    this.value,
    this.onTap,
    this.trailing,
    this.destructive = false,
    this.enabled = true,
    this.busy = false,
    this.showChevron = true,
  });

  /// Horizontal padding of the row.
  static const double _padding = AppSpacing.lg;

  /// Distance from the row's start edge to the title text (divider inset).
  static const double contentInset =
      _padding + AppSizes.badgeSm + AppSpacing.md;

  /// Widest share of the row the trailing [value] may take.
  static const double _maxValueFraction = 0.4;

  final IconData icon;
  final String title;
  final AppAccent accent;
  final String? subtitle;

  /// Current setting, shown before the chevron (e.g. "हिन्दी", "Dark").
  final String? value;
  final VoidCallback? onTap;

  /// Replaces the chevron (e.g. an "open externally" icon).
  final Widget? trailing;
  final bool destructive;
  final bool enabled;
  final bool busy;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final danger = context.accent(AppAccents.sos);
    final interactive = enabled && !busy && onTap != null;
    final muted = scheme.onSurfaceVariant;

    final Widget? end = busy
        ? const SizedBox.square(
            dimension: AppSizes.spinnerSm,
            child: CircularProgressIndicator(
              strokeWidth: AppSizes.spinnerStroke,
            ),
          )
        : trailing ??
              (onTap != null && showChevron
                  ? Icon(
                      AppIcons.chevron,
                      size: AppSizes.iconSm,
                      color: destructive ? danger.foreground : muted,
                    )
                  : null);

    final titleStyle = theme.textTheme.titleSmall?.copyWith(
      color: destructive ? danger.foreground : scheme.onSurface,
    );
    final valueStyle = theme.textTheme.bodyMedium?.copyWith(color: muted);
    final valueText = value;

    final content = ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: AppSizes.minTapTarget + AppSpacing.sm,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: _padding,
          vertical: AppSpacing.md,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // The value sits at the end when title and value both fit on
            // one line; otherwise (large text, long translations) it moves
            // below the title instead of breaking words.
            final inlineValue =
                valueText != null &&
                _fitsInline(
                  context,
                  maxWidth: constraints.maxWidth,
                  hasEnd: end != null,
                  titleStyle: titleStyle,
                  valueStyle: valueStyle,
                );
            return Row(
              children: [
                IconBadge(
                  icon: icon,
                  accent: destructive ? AppAccents.sos : accent,
                  size: AppSizes.badgeSm,
                ),
                AppGap.hMd,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: titleStyle),
                      if (subtitle != null) ...[
                        AppGap.xxs,
                        Text(
                          subtitle!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: muted,
                          ),
                        ),
                      ],
                      if (valueText != null && !inlineValue) ...[
                        AppGap.xxs,
                        Text(valueText, style: valueStyle),
                      ],
                    ],
                  ),
                ),
                if (valueText != null && inlineValue) ...[
                  AppGap.hSm,
                  Text(valueText, maxLines: 1, style: valueStyle),
                ],
                if (end != null) ...[
                  AppGap.hSm,
                  IconTheme.merge(
                    data: IconThemeData(color: muted, size: AppSizes.iconSm),
                    child: end,
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );

    return MergeSemantics(
      child: Semantics(
        button: onTap != null,
        enabled: onTap == null ? null : enabled && !busy,
        child: Opacity(
          opacity: enabled ? 1 : _disabledOpacity,
          child: InkWell(onTap: interactive ? onTap : null, child: content),
        ),
      ),
    );
  }

  static const double _disabledOpacity = 0.5;

  /// Whether [title] and [value] fit side by side on one line in a row of
  /// [maxWidth] (at the current text scale and direction).
  bool _fitsInline(
    BuildContext context, {
    required double maxWidth,
    required bool hasEnd,
    required TextStyle? titleStyle,
    required TextStyle? valueStyle,
  }) {
    final reserved =
        AppSizes.badgeSm +
        AppSpacing.md +
        AppSpacing.sm +
        (hasEnd ? AppSizes.iconSm + AppSpacing.sm : 0);
    final titleWidth = _lineWidth(context, title, titleStyle);
    final valueWidth = _lineWidth(context, value!, valueStyle);
    return valueWidth <= maxWidth * _maxValueFraction &&
        titleWidth + valueWidth <= maxWidth - reserved;
  }

  static double _lineWidth(
    BuildContext context,
    String text,
    TextStyle? style,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }
}
