import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/providers/core_providers.dart';
import 'package:family_hub/features/ledger/domain/ledger_entry.dart';
import 'package:family_hub/features/ledger/domain/ledger_requests.dart';
import 'package:family_hub/features/ledger/domain/ledger_summary.dart';
import 'package:family_hub/shared/data/repository_utils.dart';

/// Ledger entries + month summary (docs/03-API_CONTRACT.md §8).
class LedgerRepository {
  LedgerRepository(this._api);

  final ApiClient _api;

  static const _entries = '/ledger/entries';

  /// `GET /ledger/entries` — sorted by `date` desc. Admins see every entry;
  /// members only entries of / created by themselves (server rule).
  Future<Paged<LedgerEntry>> listEntries({
    LedgerEntryQuery query = const LedgerEntryQuery(),
    int page = 1,
    int limit = 20,
  }) => _api.getPaged(
    _entries,
    LedgerEntry.fromJson,
    query: query.toQuery(),
    page: page,
    limit: limit,
  );

  /// `POST /ledger/entries` → the created entry.
  Future<LedgerEntry> createEntry(LedgerEntryInput input) async {
    final data = await _api.post(_entries, body: input.toJson());
    return LedgerEntry.fromJson(requireObject(data));
  }

  /// `PATCH /ledger/entries/:id` → the updated entry. An empty [patch] is
  /// not sent; the caller keeps its entry.
  Future<LedgerEntry?> updateEntry(String id, LedgerEntryPatch patch) async {
    if (patch.isEmpty) return null;
    final data = await _api.patch(
      '$_entries/${pathId(id)}',
      body: patch.toJson(),
    );
    return LedgerEntry.fromJson(requireObject(data));
  }

  /// `DELETE /ledger/entries/:id`. Deleting a goal contribution lowers the
  /// goal's saved amount (server side).
  Future<void> deleteEntry(String id) async {
    await _api.delete('$_entries/${pathId(id)}');
  }

  /// `GET /ledger/summary?month=YYYY-MM` — family scope for admins,
  /// personal scope for members. [month] null = current month.
  Future<LedgerSummary> summary({String? month}) async {
    final data = await _api.get('/ledger/summary', query: {'month': month});
    return LedgerSummary.fromJson(requireObject(data));
  }
}

final ledgerRepositoryProvider = Provider<LedgerRepository>(
  (ref) => LedgerRepository(ref.watch(apiClientProvider)),
);
