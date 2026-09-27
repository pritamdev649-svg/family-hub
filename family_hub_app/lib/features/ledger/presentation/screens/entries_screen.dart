import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/utils/date_x.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/ledger/application/ledger_providers.dart';
import 'package:family_hub/features/ledger/domain/ledger_entry.dart';
import 'package:family_hub/features/ledger/domain/ledger_requests.dart';
import 'package:family_hub/features/ledger/presentation/ledger_labels.dart';
import 'package:family_hub/features/ledger/presentation/ledger_open_guard.dart';
import 'package:family_hub/features/ledger/presentation/widgets/add_entry_fab.dart';
import 'package:family_hub/features/ledger/presentation/widgets/entry_detail_sheet.dart';
import 'package:family_hub/features/ledger/presentation/widgets/ledger_entry_tile.dart';
import 'package:family_hub/features/ledger/presentation/widgets/month_switcher.dart';
import 'package:family_hub/features/ledger/presentation/widgets/records_only_note.dart';
import 'package:family_hub/shared/models/member.dart';
import 'package:family_hub/shared/providers/shared_providers.dart';

/// `/money/entries` — every entry the caller may see, newest first, with
/// month / type / member (admins) filters and "load more".
///
/// Starts on the month selected on the Money tab.
class EntriesScreen extends ConsumerStatefulWidget {
  const EntriesScreen({super.key});

  @override
  ConsumerState<EntriesScreen> createState() => _EntriesScreenState();
}

class _EntriesScreenState extends ConsumerState<EntriesScreen>
    with LedgerOpenGuard {
  late LedgerEntryQuery _query;

  @override
  void initState() {
    super.initState();
    _query = LedgerEntryQuery(
      month: ref.read(selectedLedgerMonthProvider).monthKey,
    );
  }

  void _update(LedgerEntryQuery query) {
    if (query == _query) return;
    setState(() => _query = query);
  }

  /// The filters actually sent: only admins filter by member (a member who
  /// lost the admin role keeps no hidden member filter).
  LedgerEntryQuery _effective(bool isAdmin) =>
      isAdmin ? _query : _query.copyWith(memberId: () => null);

  Future<void> _loadMore(LedgerEntryQuery query) async {
    try {
      await ref.read(ledgerEntriesProvider(query).notifier).loadMore();
    } catch (e) {
      if (mounted) context.showError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isAdmin = ref.watch(isAdminProvider);
    final query = _effective(isAdmin);
    final entries = ref.watch(ledgerEntriesProvider(query));

    final filters = _EntryFilters(
      query: query,
      isAdmin: isAdmin,
      onChanged: _update,
    );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.ledgerEntriesTitle)),
      floatingActionButton: const AddEntryFab(heroTag: 'entries-add-entry'),
      body: ResponsiveCenter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Outside the async view so the filters stay put while a new
            // filter combination loads.
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: AppSpacing.lg,
                top: AppSpacing.sm,
                end: AppSpacing.lg,
              ),
              child: filters,
            ),
            Expanded(
              child: AppRefreshIndicator(
                onRefresh: () =>
                    ref.refresh(ledgerEntriesProvider(query).future),
                child: AsyncValueView<LedgerEntriesState>(
                  value: entries,
                  onRetry: () => ref.invalidate(ledgerEntriesProvider(query)),
                  isEmpty: (s) => s.isEmpty,
                  empty: EmptyState(
                    icon: query.hasFilters ? AppIcons.filter : AppIcons.ledger,
                    title: l10n.ledgerEntriesEmpty,
                    message: query.hasFilters
                        ? l10n.ledgerEntriesEmptyFiltered
                        : l10n.ledgerEntriesEmptyMessage,
                    action: query.hasFilters
                        ? AppButton(
                            label: l10n.ledgerClearFilters,
                            icon: AppIcons.clear,
                            variant: AppButtonVariant.secondary,
                            expand: false,
                            onPressed: () => _update(const LedgerEntryQuery()),
                          )
                        : null,
                  ),
                  data: (state) => PaginatedListView<LedgerEntry>(
                    items: state.items,
                    hasMore: state.hasMore,
                    isLoadingMore: state.isLoadingMore,
                    onLoadMore: () => _loadMore(query),
                    padding: AppSpacing.screenWithFab.copyWith(
                      top: AppSpacing.sm,
                      bottom:
                          AppSpacing.screenWithFab.bottom +
                          MediaQuery.paddingOf(context).bottom,
                    ),
                    itemBuilder: (context, entry) => LedgerEntryTile(
                      entry,
                      onTap: () => guardedOpen(
                        () => showLedgerEntrySheet(context, entry),
                      ),
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

/// Month switcher, type chips, member dropdown (admins) and the visibility
/// caption for members.
class _EntryFilters extends ConsumerWidget {
  const _EntryFilters({
    required this.query,
    required this.isAdmin,
    required this.onChanged,
  });

  final LedgerEntryQuery query;
  final bool isAdmin;
  final ValueChanged<LedgerEntryQuery> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final me = ref.watch(currentMemberProvider);
    final members = isAdmin
        ? (ref.watch(membersProvider).value ?? const <Member>[])
        : const <Member>[];
    final month = parseMonthKey(query.month);

    // `null` = "Everyone"; AppDropdownField needs a non-null item for it.
    const everyone = '';
    final selectedMember = query.memberId;
    final memberIds = [
      everyone,
      for (final m in members) m.id,
      // The filtered member left the family (or the list is refreshing):
      // keep the choice visible instead of an empty field.
      if (selectedMember != null &&
          members.every((m) => m.id != selectedMember))
        selectedMember,
    ];
    String memberLabel(String id) {
      if (id == everyone) return l10n.ledgerFilterAllMembers;
      for (final m in members) {
        if (m.id == id) {
          return m.id == me?.id ? l10n.ledgerMemberYou(m.name) : m.name;
        }
      }
      return l10n.ledgerFormerMember;
    }

    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MonthSwitcher(
            month: month,
            allowAllMonths: true,
            onChanged: (m) =>
                onChanged(query.copyWith(month: () => m?.monthKey)),
          ),
          AppGap.md,
          ChoiceChipsField<LedgerType?>(
            options: const [null, LedgerType.income, LedgerType.expense],
            selected: query.type,
            label: (t) => t?.label(l10n) ?? l10n.ledgerFilterAllTypes,
            icon: (t) => t?.icon ?? AppIcons.filter,
            onSelected: (t) => onChanged(query.copyWith(type: () => t)),
          ),
          if (isAdmin && members.isNotEmpty) ...[
            AppGap.md,
            AppDropdownField<String>(
              key: ValueKey('member-filter-${query.memberId}'),
              label: l10n.ledgerFilterMember,
              value: query.memberId ?? everyone,
              items: memberIds,
              itemLabel: memberLabel,
              onChanged: (id) => onChanged(
                query.copyWith(
                  memberId: () => id == null || id == everyone ? null : id,
                ),
              ),
            ),
          ],
          if (!isAdmin) ...[
            AppGap.sm,
            Text(
              l10n.ledgerEntriesVisibleToMember,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const RecordsOnlyNote(),
        ],
      ),
    );
  }
}
