import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/config/app_languages.dart';
import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/settings/settings_controller.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/auth/presentation/auth_labels.dart';

/// Switches the app language (device setting, [settingsControllerProvider])
/// and reports failures to save it.
Future<void> switchAppLanguage(
  BuildContext context,
  WidgetRef ref,
  String code,
) async {
  try {
    await ref.read(settingsControllerProvider.notifier).setLocale(code);
  } catch (e) {
    if (context.mounted) context.showError(e);
  }
}

/// Frosted "glass" pill for the welcome gradient showing the current
/// language in its own script (e.g. "हिन्दी"); opens a sheet listing every
/// supported language by its native name. White on a translucent fill, so
/// it only suits gradient backgrounds.
class LanguagePickerButton extends ConsumerWidget {
  const LanguagePickerButton({super.key});

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _LanguageSheet(current: current),
    );
    if (picked == null || picked == current || !context.mounted) return;
    await switchAppLanguage(context, ref, picked);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final current = ref.watch(resolvedLocaleProvider).languageCode;
    final language = AppLanguages.byCode(current);
    return Tooltip(
      message: l10n.authLanguageLabel,
      child: Semantics(
        button: true,
        child: Material(
          color: Colors.white.withValues(alpha: AuthGlass.fill),
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _open(context, ref, current),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: AppSizes.minTapTarget,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      AppIcons.language,
                      size: AppSizes.iconSm,
                      color: Colors.white,
                    ),
                    AppGap.hSm,
                    Flexible(
                      child: Text(
                        language?.nativeName ?? current,
                        locale: language?.locale,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ),
                    AppGap.hXs,
                    const Icon(
                      AppIcons.expand,
                      size: AppSizes.iconXs,
                      color: Colors.white,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LanguageSheet extends StatelessWidget {
  const _LanguageSheet({required this.current});

  final String current;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final brand = context.accent(AppAccents.brand);
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        bottom: AppSpacing.lg + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Row(
              children: [
                const ExcludeSemantics(
                  child: IconBadge(
                    icon: AppIcons.language,
                    accent: AppAccents.settings,
                    size: AppSizes.badgeSm,
                  ),
                ),
                AppGap.hMd,
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      l10n.authLanguageSheetTitle,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                ),
              ],
            ),
          ),
          AppGap.md,
          for (final language in AppLanguages.all)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: ListTile(
                // Each name is shown (and read out) in its own language.
                title: Text(
                  language.nativeName,
                  locale: language.locale,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: language.code == current
                        ? brand.onContainer
                        : theme.colorScheme.onSurface,
                  ),
                ),
                selected: language.code == current,
                selectedTileColor: brand.container,
                trailing: language.code == current
                    ? Icon(AppIcons.check, color: brand.foreground)
                    : null,
                onTap: () => Navigator.of(context).pop(language.code),
              ),
            ),
        ],
      ),
    );
  }
}
