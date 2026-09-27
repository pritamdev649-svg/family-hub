import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/providers/core_providers.dart';
import 'package:family_hub/features/emergency_card/domain/emergency_card.dart';
import 'package:family_hub/shared/data/repository_utils.dart';

/// `GET|PUT /family/members/:id/emergency-card` (docs/03-API_CONTRACT.md §6).
class EmergencyCardRepository {
  EmergencyCardRepository(this._api);

  final ApiClient _api;

  static String _path(String memberId) =>
      '/family/members/${pathId(memberId)}/emergency-card';

  /// The member's card; an empty card (`updatedAt == null`) when none was
  /// saved. Errors: `NOT_FOUND` (unknown member or another family's).
  Future<EmergencyCard> getCard(String memberId) async =>
      _card(await _api.get(_path(memberId)), memberId);

  /// Replaces the member's card (self or admin) and returns the stored card.
  /// Errors: `FORBIDDEN`, `NOT_FOUND`, `VALIDATION_ERROR`.
  Future<EmergencyCard> saveCard(String memberId, EmergencyCard card) async =>
      _card(
        await _api.put(_path(memberId), body: card.toUpdateJson()),
        memberId,
      );

  static EmergencyCard _card(Object? data, String memberId) =>
      EmergencyCard.fromJson(
        requireObject(data),
        fallbackMemberId: memberId.trim(),
      );
}

final emergencyCardRepositoryProvider = Provider<EmergencyCardRepository>(
  (ref) => EmergencyCardRepository(ref.watch(apiClientProvider)),
);
