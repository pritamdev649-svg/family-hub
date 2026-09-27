import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/config/app_languages.dart';
import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/settings/settings_controller.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/settings/application/settings_actions.dart';
import 'package:family_hub/features/settings/presentation/settings_labels.dart';
import 'package:family_hub/features/settings/presentation/widgets/selection_check.dart';
import 'package:family_hub/features/settings/presentation/widgets/settings_page.dart';

/// Pick the app language: the phone's language or one of [AppLanguages]
/// (native name big, English name small). The choice applies instantly on
/// this phone and is stored on the account for pushes / emails (best
/// effort). The chosen row is tinted and marked with a solid indigo check.
class LanguageScreen extends ConsumerWidget {
  const LanguageScreen({super.key});

  /// Accent of the selection marker and tint.
  static const AppAccent _accent = AppAccent.indigo;

  Future<void> _select(
    BuildContext context,
    WidgetRef ref,
    String? code,
  ) async {
    final current = ref.read(settingsControllerProvider).localeCode;
    if (current == code) return;
    try {
      await ref.read(settingsActionsProvider).setLanguage(code);
    } catch (e) {
      if (context.mounted) context.showError(e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final chosen = ref.watch(
      settingsControllerProvider.select((s) => s.localeCode),
    );
    final effective = ref.watch(resolvedLocaleProvider).languageCode;

    return SettingsPage(
      title: l10n.settingsLanguage,
      child: SettingsListView(
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: AppSpacing.xs),
            child: Text(
              l10n.settingsLanguageHint,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          AppGap.lg,
          _LanguageGroup(
            // A single row: its tint fills the whole card.
            padding: EdgeInsets.zero,
            children: [
              _LanguageTile(
                selected: chosen == null,
                horizontalPadding: AppSpacing.lg,
                leading: const IconBadge(
                  icon: AppIcons.language,
                  accent: AppAccents.settings,
                  size: AppSizes.badgeSm,
                ),
                title: l10n.settingsLanguageDevice,
                subtitle: l10n.settingsLanguageDeviceCurrent(
                  languageNativeName(effective),
                ),
                onTap: () => _select(context, ref, null),
              ),
            ],
          ),
          AppGap.lg,
          _LanguageGroup(
            children: [
              for (final language in AppLanguages.all)
                _LanguageTile(
                  selected: chosen == language.code,
                  title: language.nativeName,
                  titleLocale: language.locale,
                  subtitle: language.englishName == language.nativeName
                      ? null
                      : language.englishName,
                  onTap: () => _select(context, ref, language.code),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Borderless card holding language rows. The default inner [padding] lets
/// a tinted selected row keep rounded corners inside the card.
class _LanguageGroup extends StatelessWidget {
  const _LanguageGroup({
    required this.children,
    this.padding = const EdgeInsets.all(AppSpacing.xs),
  });

  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) AppGap.xxs,
            children[i],
          ],
        ],
      ),
    );
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({
    required this.selected,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.titleLocale,
    this.leading,
    this.horizontalPadding = AppSpacing.md,
  });

  final bool selected;
  final String title;
  final String? subtitle;

  /// Locale of [title] so the native name uses the right glyphs.
  final Locale? titleLocale;
  final Widget? leading;
  final VoidCallback onTap;

  /// Start / end padding; together with the card's inner padding it lines
  /// the text up with other settings rows.
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shades = context.accent(LanguageScreen._accent);

    return ListTile(
      selected: selected,
      selectedColor: shades.foreground,
      selectedTileColor: shades.container,
      contentPadding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      leading: leading,
      title: Text(
        title,
        locale: titleLocale,
        style: theme.textTheme.titleMedium?.copyWith(
          color: selected ? shades.foreground : theme.colorScheme.onSurface,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
      trailing: SelectionCheck(
        selected: selected,
        accent: LanguageScreen._accent,
      ),
      onTap: onTap,
    );
  }
}
