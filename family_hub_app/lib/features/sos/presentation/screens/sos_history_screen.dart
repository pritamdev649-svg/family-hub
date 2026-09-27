import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/sos/application/sos_providers.dart';
import 'package:family_hub/features/sos/presentation/widgets/sos_alert_tile.dart';

/// `/sos/history` — resolved and ended alerts of the family, newest first,
/// with "load more" pagination and pull-to-refresh.
class SosHistoryScreen extends ConsumerWidget {
  const SosHistoryScreen({super.key});

  Future<void> _loadMore(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(sosHistoryProvider.notifier).loadMore();
    } catch (e) {
      if (context.mounted) context.showError(e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final history = ref.watch(sosHistoryProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.sosHistoryTitle)),
      body: SafeArea(
        top: false,
        child: ResponsiveCenter(
          child: AppRefreshIndicator(
            onRefresh: () => ref.refresh(sosHistoryProvider.future),
            child: AsyncValueView<SosHistoryState>(
              value: history,
              onRetry: () => ref.invalidate(sosHistoryProvider),
              isEmpty: (s) => s.isEmpty,
              empty: EmptyState(
                icon: AppIcons.history,
                title: l10n.sosHistoryEmptyTitle,
                message: l10n.sosHistoryEmptyMessage,
              ),
              data: (s) => PaginatedListView<SosAlert>(
                items: s.items,
                hasMore: s.hasMore,
                isLoadingMore: s.isLoadingMore,
                onLoadMore: () => _loadMore(context, ref),
                itemBuilder: (context, alert) => SosAlertTile(alert),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
