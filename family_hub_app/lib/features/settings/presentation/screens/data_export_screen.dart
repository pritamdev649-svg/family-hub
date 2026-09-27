import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/utils/formatters.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/settings/application/settings_providers.dart';
import 'package:family_hub/features/settings/domain/data_export.dart';
import 'package:family_hub/features/settings/presentation/settings_labels.dart';
import 'package:family_hub/features/settings/presentation/widgets/settings_page.dart';
import 'package:family_hub/features/settings/presentation/widgets/settings_section.dart';

/// Shows the member's personal data export (`GET /me/export`): a summary of
/// what is stored plus the full JSON, selectable and copyable.
///
/// Opened as a full-screen dialog from the privacy screen (there is no
/// `AppRoutes` path for it) with [open].
class DataExportScreen extends ConsumerWidget {
  const DataExportScreen({super.key});

  /// Pushes the screen as a full-screen dialog on the current navigator.
  static Future<void> open(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => const DataExportScreen(),
    ),
  );

  Future<void> _copy(BuildContext context, DataExport export) async {
    final l10n = context.l10n;
    try {
      await Clipboard.setData(ClipboardData(text: export.prettyJson));
      if (context.mounted) context.showSuccess(l10n.commonCopied);
    } catch (e) {
      if (context.mounted) context.showError(e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final export = ref.watch(dataExportProvider);
    final data = export.value;

    return SettingsPage(
      title: l10n.settingsExportTitle,
      actions: [
        IconButton(
          tooltip: l10n.settingsExportCopy,
          icon: const Icon(AppIcons.copy),
          onPressed: data == null || data.isEmpty
              ? null
              : () => _copy(context, data),
        ),
      ],
      child: AsyncValueView<DataExport>(
        value: export,
        onRetry: () => ref.invalidate(dataExportProvider),
        isEmpty: (d) => d.isEmpty,
        empty: EmptyState(
          icon: AppIcons.export,
          title: l10n.settingsExportEmpty,
        ),
        data: (d) => _ExportBody(export: d),
      ),
    );
  }
}

class _ExportBody extends ConsumerWidget {
  const _ExportBody({required this.export});

  final DataExport export;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fmt = ref.watch(fmtProvider);
    final at = export.exportedAt;
    final lines = export.prettyJsonLines;
    final codeStyle = theme.textTheme.bodySmall;

    // One lazily built scroll view: an export can have tens of thousands of
    // JSON lines, which a single (Selectable)Text would lay out at once.
    return Scrollbar(
      child: SelectionArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                0,
              ),
              sliver: SliverList.list(
                children: [
                  if (at != null) ...[
                    Text(
                      l10n.settingsExportGeneratedAt(fmt.dateTime(at)),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    AppGap.md,
                  ],
                  if (export.sections.isNotEmpty) ...[
                    SettingsSection(
                      children: [
                        for (final s in export.sections)
                          SettingsTile(
                            icon: s.section.icon,
                            accent: s.section.accent,
                            title: s.section.label(l10n),
                            value: s.countLabel(l10n),
                          ),
                      ],
                    ),
                    AppGap.xl,
                  ],
                  SectionHeader(
                    title: l10n.settingsExportRawData,
                    icon: AppIcons.notes,
                    accent: AppAccents.settings,
                  ),
                ],
              ),
            ),
            SliverPadding(
              padding: EdgeInsetsDirectional.fromSTEB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.xl + MediaQuery.paddingOf(context).bottom,
              ),
              sliver: DecoratedSliver(
                decoration: BoxDecoration(
                  color: context.semanticColors.card,
                  borderRadius: AppRadius.brCard,
                ),
                sliver: SliverPadding(
                  padding: AppSpacing.card,
                  sliver: SliverList.builder(
                    itemCount: lines.length,
                    itemBuilder: (context, i) => Text(
                      lines[i],
                      // JSON keys and values are not translatable text.
                      textDirection: TextDirection.ltr,
                      style: codeStyle,
                    ),
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
