import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/settings/settings_controller.dart';
import 'package:family_hub/core/settings/text_scale.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/settings/presentation/settings_labels.dart';
import 'package:family_hub/features/settings/presentation/widgets/selection_check.dart';
import 'package:family_hub/features/settings/presentation/widgets/settings_page.dart';

/// Theme (phone / light / dark) as three visual cards with mini previews,
/// and the "Large text" switch with a live preview. Both apply to the whole
/// app instantly (device-only settings).
class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  /// Accent of this screen (matches its row on the More tab).
  static const AppAccent accent = AppAccent.violet;

  Future<void> _run(
    BuildContext context,
    Future<void> Function() change,
  ) async {
    try {
      await change();
    } catch (e) {
      // The controller rolled the setting back; tell the user why.
      if (context.mounted) context.showError(e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);

    return SettingsPage(
      title: l10n.settingsAppearance,
      child: SettingsListView(
        children: [
          SectionHeader(
            title: l10n.settingsAppearanceTheme,
            icon: AppIcons.appearance,
            accent: accent,
          ),
          _ThemeChoices(
            selected: settings.themeMode,
            onSelected: (mode) {
              if (mode == settings.themeMode) return;
              _run(context, () => controller.setThemeMode(mode));
            },
          ),
          AppGap.xl,
          SectionHeader(
            title: l10n.settingsAppearanceTextSize,
            icon: AppIcons.textSize,
            accent: accent,
          ),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: SwitchListTile(
              value: settings.largeText,
              onChanged: (on) =>
                  _run(context, () => controller.setLargeText(on)),
              secondary: const IconBadge(
                icon: AppIcons.textSize,
                accent: AppAccent.sky,
                size: AppSizes.badgeSm,
              ),
              title: Text(
                l10n.settingsAppearanceLargeText,
                style: theme.textTheme.titleSmall,
              ),
              subtitle: Text(
                l10n.settingsAppearanceLargeTextDescription,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          AppGap.lg,
          Padding(
            padding: const EdgeInsetsDirectional.only(start: AppSpacing.xs),
            child: Text(
              l10n.settingsAppearancePreview,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          AppGap.sm,
          TextSizePreview(largeText: settings.largeText),
        ],
      ),
    );
  }
}

/// The three theme cards in one row; the cards share the height of the
/// tallest one (long / large-text labels wrap).
class _ThemeChoices extends StatelessWidget {
  const _ThemeChoices({required this.selected, required this.onSelected});

  final ThemeMode selected;
  final ValueChanged<ThemeMode> onSelected;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final mode in ThemeMode.values) ...[
            if (mode.index > 0) AppGap.hSm,
            Expanded(
              child: _ThemeCard(
                mode: mode,
                selected: mode == selected,
                onTap: () => onSelected(mode),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One theme option: a mini preview of the app in that theme and its name.
/// The selected card is tinted and its preview carries a check.
class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final ThemeMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final shades = context.accent(AppearanceScreen.accent);

    return MergeSemantics(
      child: Semantics(
        inMutuallyExclusiveGroup: true,
        checked: selected,
        child: AppCard(
          accent: selected ? AppearanceScreen.accent : null,
          padding: const EdgeInsets.all(AppSpacing.sm),
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Stack(
                children: [
                  _ThemePreview(mode: mode),
                  PositionedDirectional(
                    top: AppSpacing.xs,
                    end: AppSpacing.xs,
                    child: SelectionCheck(
                      selected: selected,
                      accent: AppearanceScreen.accent,
                    ),
                  ),
                ],
              ),
              AppGap.sm,
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    mode.icon,
                    size: AppSizes.iconXs,
                    color: selected
                        ? shades.foreground
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  AppGap.hXs,
                  Flexible(
                    child: Text(
                      mode.label(l10n),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: selected
                            ? shades.foreground
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Miniature of the app in [mode]: canvas, a card with text lines and an
/// accent swatch. "Same as phone" shows light and dark halves side by side.
/// Drawn at a fixed design size and scaled to the available width, so it
/// never overflows.
class _ThemePreview extends StatelessWidget {
  const _ThemePreview({required this.mode});

  final ThemeMode mode;

  static const double _width = AppSpacing.xxxl * 2;
  static const double _height = AppSpacing.xxxl * 1.5;

  @override
  Widget build(BuildContext context) {
    final Widget scene = switch (mode) {
      ThemeMode.light => const _MiniScene(brightness: Brightness.light),
      ThemeMode.dark => const _MiniScene(brightness: Brightness.dark),
      ThemeMode.system => Stack(
        fit: StackFit.expand,
        children: [
          const _MiniScene(brightness: Brightness.light),
          ClipRect(
            clipper: _EndHalfClipper(Directionality.of(context)),
            child: const _MiniScene(brightness: Brightness.dark),
          ),
        ],
      ),
    };
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: AppRadius.brMd,
        child: AspectRatio(
          aspectRatio: _width / _height,
          child: FittedBox(
            fit: BoxFit.fill,
            child: SizedBox(width: _width, height: _height, child: scene),
          ),
        ),
      ),
    );
  }
}

/// Canvas + card + lines + accent swatch in the colours of [brightness]
/// (taken from the design tokens of that theme, whatever the current one).
class _MiniScene extends StatelessWidget {
  const _MiniScene({required this.brightness});

  final Brightness brightness;

  static const double _line = AppSpacing.xs;
  static const double _swatch = AppSpacing.md;

  @override
  Widget build(BuildContext context) {
    final colors = AppSemanticColors.of(brightness);
    final other = AppSemanticColors.of(
      brightness == Brightness.light ? Brightness.dark : Brightness.light,
    );
    // Placeholder "text": the opposite theme's surface, faded.
    final ink = other.card.withValues(alpha: 0.22);

    Widget line(double widthFactor) => FractionallySizedBox(
      alignment: AlignmentDirectional.centerStart,
      widthFactor: widthFactor,
      child: Container(
        height: _line,
        decoration: BoxDecoration(color: ink, borderRadius: AppRadius.brPill),
      ),
    );

    return ColoredBox(
      color: colors.canvas,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: _swatch,
                  height: _swatch,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppGradients.brand,
                  ),
                ),
                AppGap.hXs,
                Expanded(child: line(0.7)),
              ],
            ),
            AppGap.sm,
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: AppRadius.brSm,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      line(1),
                      AppGap.xs,
                      line(0.6),
                      const Spacer(),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: Container(
                          width: AppSpacing.xl,
                          height: AppSpacing.sm,
                          decoration: const BoxDecoration(
                            gradient: AppGradients.brand,
                            borderRadius: AppRadius.brPill,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Clips to the end half (right in LTR, left in RTL).
class _EndHalfClipper extends CustomClipper<Rect> {
  const _EndHalfClipper(this.direction);

  final TextDirection direction;

  @override
  Rect getClip(Size size) {
    final half = size.width / 2;
    return direction == TextDirection.ltr
        ? Rect.fromLTWH(half, 0, half, size.height)
        : Rect.fromLTWH(0, 0, half, size.height);
  }

  @override
  bool shouldReclip(_EndHalfClipper oldClipper) =>
      oldClipper.direction != direction;
}

/// Sample notice card rendered with the text scale that [largeText]
/// produces, so the preview is right even before the app-wide scale is
/// rebuilt.
class TextSizePreview extends StatelessWidget {
  const TextSizePreview({super.key, required this.largeText});

  final bool largeText;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);

    return MediaQuery(
      data: media.copyWith(
        // Idempotent on top of the app-wide scaler (same bounds).
        textScaler: AppTextScale.resolve(
          media.textScaler,
          largeText: largeText,
        ),
      ),
      child: AppCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const IconBadge(
              icon: AppIcons.notice,
              accent: AppAccents.notices,
              size: AppSizes.badgeSm,
            ),
            AppGap.hMd,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.settingsAppearancePreviewTitle,
                    style: theme.textTheme.titleMedium,
                  ),
                  AppGap.xs,
                  Text(
                    l10n.settingsAppearancePreviewBody,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
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
