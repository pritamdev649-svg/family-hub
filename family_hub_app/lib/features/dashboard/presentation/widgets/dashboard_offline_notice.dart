import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/utils/formatters.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/dashboard/application/dashboard_providers.dart';

/// Shown above an offline copy of the dashboard: the data is the copy saved
/// on the phone, with when it was saved and a retry button.
class DashboardOfflineNotice extends ConsumerWidget {
  const DashboardOfflineNotice({
    super.key,
    required this.savedAt,
    required this.onRetry,
    this.isRetrying = false,
  });

  final DateTime savedAt;
  final VoidCallback onRetry;
  final bool isRetrying;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fmt = ref.watch(fmtProvider);
    final now = ref.watch(dashboardClockProvider)();

    return Semantics(
      liveRegion: true,
      container: true,
      child: AppCard(
        color: scheme.surfaceContainerHighest,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  AppIcons.offline,
                  size: AppSizes.iconMd,
                  color: scheme.onSurfaceVariant,
                ),
                AppGap.hMd,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.dashboardOfflineTitle,
                        style: theme.textTheme.titleSmall,
                      ),
                      AppGap.xxs,
                      Text(
                        l10n.dashboardOfflineUpdated(
                          fmt.relative(savedAt, l10n, now: now),
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            AppGap.sm,
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: AppButton(
                label: l10n.commonRetry,
                icon: AppIcons.retry,
                variant: AppButtonVariant.text,
                expand: false,
                isLoading: isRetrying,
                onPressed: onRetry,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
