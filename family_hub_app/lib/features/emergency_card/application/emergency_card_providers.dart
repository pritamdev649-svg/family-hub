import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/l10n/error_messages.dart';
import 'package:family_hub/core/providers/core_providers.dart';
import 'package:family_hub/core/utils/validators.dart';
import 'package:family_hub/features/emergency_card/data/emergency_card_offline_store.dart';
import 'package:family_hub/features/emergency_card/data/emergency_card_repository.dart';
import 'package:family_hub/features/emergency_card/domain/emergency_card.dart';
import 'package:family_hub/shared/models/member.dart';
import 'package:family_hub/shared/providers/shared_providers.dart';

export 'package:family_hub/features/emergency_card/domain/emergency_card.dart';

/// How long a card request may take before the offline copy (if any) is
/// shown. The request keeps running and replaces the copy when it arrives.
/// Overridable in tests.
final emergencyCardOfflineFallbackDelayProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 3),
);

/// Re-reads the signed-in session (`GET /auth/me`) after a save was refused
/// with `403 FORBIDDEN` / `NO_FAMILY`: the member's role or membership
/// changed while the form was open, and the refreshed session updates
/// [canEditEmergencyCardProvider] (or sends a removed member to the
/// family-setup screen). Overridable in tests.
final emergencyCardSessionRefreshProvider = Provider<Future<void> Function()>(
  (ref) =>
      () => ref.read(sessionControllerProvider.notifier).refreshMe(),
);

/// Whether [error] means "the server could not be reached / answer" — the
/// cases where the offline copy is better than an error screen.
bool isUnreachableError(Object error) {
  final e = unwrapProviderError(error);
  return e is ApiException && (e.isNetwork || e.isServer);
}

/// Whether [error] is `404 NOT_FOUND`: the member was removed from the
/// family (or the link points at another family / a bad id).
bool isEmergencyCardNotFound(Object? error) {
  if (error == null) return false;
  final e = unwrapProviderError(error);
  return e is ApiException && e.isNotFound;
}

/// The emergency card of a member (public API, docs/05-FLUTTER_GUIDE.md §10):
/// `ref.watch(emergencyCardProvider(memberId))`.
///
/// * Every successfully loaded card is kept as an offline copy
///   ([EmergencyCardOfflineStore]).
/// * When the server cannot be reached (no connection, timeout, 5xx) the
///   offline copy is returned instead of an error; it is marked with
///   [EmergencyCard.isOfflineCopy] / [EmergencyCard.offlineSavedAt] so the UI
///   shows an "offline copy" hint.
/// * On a slow network the offline copy is shown after
///   [emergencyCardOfflineFallbackDelayProvider] and replaced by the fresh
///   card once it arrives.
/// * `NOT_FOUND` (member removed / other family) deletes the offline copy and
///   surfaces the error.
/// * An offline copy refreshes by itself as soon as the server is reachable
///   again ([connectivityStatusProvider] turns online), and screens call
///   [EmergencyCardNotifier.refreshIfStale] when they open, so a card edited
///   on another phone is not shown out of date.
///
/// Refetches on account switch and on `markChanged({DataScope.emergencyCards})`.
final emergencyCardProvider =
    AsyncNotifierProvider.family<EmergencyCardNotifier, EmergencyCard, String>(
      EmergencyCardNotifier.new,
      retry: apiRetryPolicy,
    );

/// Loads one card with the offline fallback described on
/// [emergencyCardProvider].
class EmergencyCardNotifier extends AsyncNotifier<EmergencyCard> {
  EmergencyCardNotifier(this.memberId);

  /// How long a card loaded from the server counts as fresh for
  /// [refreshIfStale].
  static const freshFor = Duration(minutes: 1);

  final String memberId;

  /// When the current card last came from the server (`null`: never, or the
  /// state is an offline copy).
  DateTime? _fetchedAt;

  /// A request is running — also while the offline copy is already shown
  /// (`AsyncData`) on a slow network.
  bool _inFlight = false;

  /// Refetches in the background — the card stays on screen — unless the
  /// card came from the server less than [maxAge] ago or a request is
  /// already running. Offline copies are always retried. Call it when a
  /// screen showing the card opens.
  void refreshIfStale({Duration maxAge = freshFor}) {
    final current = state;
    if (_inFlight || current.isLoading || !current.hasValue) return;
    final fetchedAt = _fetchedAt;
    final fresh =
        !current.hasError &&
        !(current.value?.isOfflineCopy ?? true) &&
        fetchedAt != null &&
        DateTime.now().difference(fetchedAt) < maxAge;
    if (!fresh) ref.invalidateSelf();
  }

  @override
  Future<EmergencyCard> build() async {
    // This build's own ref. `ref` always points at the newest build, so only
    // `buildRef.mounted` tells whether this build was superseded while it
    // awaited (account switch, markChanged, refresh) — its late results must
    // then neither reach the state nor the offline store.
    final buildRef = ref;
    final userId = ref.watch(sessionUserIdProvider);
    ref.watch(dataRefreshProvider.select((m) => m[DataScope.emergencyCards]));
    final repository = ref.watch(emergencyCardRepositoryProvider);
    final store = ref.watch(emergencyCardOfflineStoreProvider);
    final fallbackAfter = ref.watch(emergencyCardOfflineFallbackDelayProvider);

    final id = memberId.trim();
    if (userId == null || id.isEmpty) {
      throw const ApiException(code: ApiErrorCode.notFound, statusCode: 404);
    }

    _inFlight = true;
    try {
      return await _load(
        buildRef,
        userId,
        id,
        repository,
        store,
        fallbackAfter,
      );
    } finally {
      if (buildRef.mounted) _inFlight = false;
    }
  }

  Future<EmergencyCard> _load(
    Ref buildRef,
    String userId,
    String id,
    EmergencyCardRepository repository,
    EmergencyCardOfflineStore store,
    Duration fallbackAfter,
  ) async {
    final request = repository
        .getCard(id)
        .then<_Outcome>(
          _Outcome.value,
          onError: (Object e, StackTrace s) => _Outcome.error(e, s),
        );

    // On a refresh the previous card stays visible while loading; only a
    // first load (or a previous offline copy) is replaced by the stored copy.
    final shown = state.value;
    EmergencyCard? offline;
    if ((shown == null || shown.isOfflineCopy) &&
        !await _settlesWithin(request, fallbackAfter)) {
      offline = await store.load(userId, id);
      // Show the copy while the request keeps running.
      if (offline != null && buildRef.mounted) state = AsyncData(offline);
    }

    final outcome = await request;
    final card = outcome.card;
    if (card != null) {
      if (buildRef.mounted) {
        _fetchedAt = DateTime.now();
        unawaited(store.save(userId, card));
      }
      return card;
    }

    if (buildRef.mounted) _fetchedAt = null;
    final error = outcome.error!;
    if (isUnreachableError(error)) {
      offline ??= await store.load(userId, id);
      if (offline != null) {
        if (buildRef.mounted) _refreshWhenBackOnline(buildRef);
        return offline;
      }
    } else if (error is ApiException && error.isNotFound) {
      if (buildRef.mounted) unawaited(store.remove(id));
    }
    Error.throwWithStackTrace(error, outcome.stackTrace ?? StackTrace.current);
  }

  /// While an offline copy is shown: refetch once any request reaches the
  /// server again. The listener belongs to [buildRef], so it ends with the
  /// next build.
  void _refreshWhenBackOnline(Ref buildRef) {
    buildRef.listen<ConnectivityStatus>(connectivityStatusProvider, (
      previous,
      next,
    ) {
      if (previous == ConnectivityStatus.offline &&
          next.isOnline &&
          buildRef.mounted) {
        buildRef.invalidateSelf();
      }
    });
  }
}

/// Result of a request that never throws.
class _Outcome {
  _Outcome.value(EmergencyCard this.card) : error = null, stackTrace = null;
  _Outcome.error(Object this.error, this.stackTrace) : card = null;

  final EmergencyCard? card;
  final Object? error;
  final StackTrace? stackTrace;
}

/// Completes with `true` when [future] settles within [timeout], else
/// `false` (without cancelling [future]). The timer is always cancelled so no
/// timer outlives the request.
Future<bool> _settlesWithin(Future<Object?> future, Duration timeout) {
  final result = Completer<bool>();
  final timer = Timer(timeout, () {
    if (!result.isCompleted) result.complete(false);
  });
  future.then((_) {
    timer.cancel();
    if (!result.isCompleted) result.complete(true);
  });
  return result.future;
}

/// Members for the cards list: [membersProvider], with the last known member
/// directory as a fallback when the server cannot be reached (so the cards
/// stay reachable offline).
final emergencyCardMembersProvider = FutureProvider<List<Member>>((ref) async {
  final userId = ref.watch(sessionUserIdProvider);
  final store = ref.watch(emergencyCardOfflineStoreProvider);
  try {
    final members = await ref.watch(membersProvider.future);
    if (userId != null && members.isNotEmpty) {
      unawaited(store.saveMembers(userId, members));
    }
    return members;
  } catch (e, stack) {
    final error = unwrapProviderError(e);
    if (userId != null && isUnreachableError(error)) {
      final cached = store.loadMembers(userId);
      if (cached != null && cached.isNotEmpty) return cached;
    }
    Error.throwWithStackTrace(error, stack);
  }
  // membersProvider already retries transient failures.
}, retry: (_, _) => null);

/// The member a card belongs to, for headers (`null` while unknown — the
/// card itself still renders). Falls back to the signed-in member for their
/// own card.
final emergencyCardMemberProvider = FutureProvider.family<Member?, String>((
  ref,
  memberId,
) async {
  final me = ref.watch(currentMemberProvider);
  try {
    final members = await ref.watch(emergencyCardMembersProvider.future);
    for (final m in members) {
      if (m.id == memberId) return m;
    }
  } catch (_) {
    // Handled below: the header simply has no name.
  }
  return me != null && me.id == memberId ? me : null;
}, retry: (_, _) => null);

/// Whether the signed-in member may edit [memberId]'s card (self or admin;
/// the backend enforces it too).
final canEditEmergencyCardProvider = Provider.family<bool, String>((
  ref,
  memberId,
) {
  final me = ref.watch(currentMemberProvider);
  if (me == null) return false;
  return ref.watch(isAdminProvider) || me.id == memberId;
});

/// The card as it is sent: phone numbers normalised (spaces / dashes
/// removed, native digits converted), lists cleaned, blank contacts dropped.
EmergencyCard normalizeEmergencyCard(EmergencyCard card) {
  String? phone(String? value) {
    if (value == null) return null;
    final normalized = Validators.normalizePhone(value);
    return normalized.isEmpty ? null : normalized;
  }

  String? text(String? value) {
    final t = value?.trim();
    return t == null || t.isEmpty ? null : t;
  }

  return card.copyWith(
    allergies: EmergencyCard.cleanList(card.allergies),
    medications: EmergencyCard.cleanList(card.medications),
    conditions: EmergencyCard.cleanList(card.conditions),
    doctorName: () => text(card.doctorName),
    doctorPhone: () => phone(card.doctorPhone),
    insuranceProvider: () => text(card.insuranceProvider),
    insurancePolicyNumber: () => text(card.insurancePolicyNumber),
    emergencyContacts: [
      for (final c in card.emergencyContacts)
        if (!c.isBlank)
          EmergencyContact(
            name: c.name.trim(),
            phone: phone(c.phone),
            relation: text(c.relation),
          ),
    ],
    notes: () => text(card.notes),
  );
}

/// Saves cards (`PUT`). The state is `true` while a save is running; the
/// form's save button shows it and a second call meanwhile is ignored.
class EmergencyCardSaveController extends Notifier<bool> {
  @override
  bool build() => false;

  /// Normalises and saves [card] for [memberId], refreshes the offline copy
  /// and announces `DataScope.emergencyCards`. Returns the stored card, or
  /// `null` when a save is already running. Throws the [ApiException]
  /// (`FORBIDDEN`, `NOT_FOUND`, `VALIDATION_ERROR`, network …) after
  /// resyncing what it reveals:
  ///
  /// * `FORBIDDEN` / `NO_FAMILY` — the session is re-read (role or
  ///   membership changed), so the form turns into its "no permission" state.
  /// * `NOT_FOUND` — the member was removed: members and cards refetch and
  ///   the offline copy is deleted.
  Future<EmergencyCard?> save(String memberId, EmergencyCard card) async {
    if (state) return null;
    state = true;
    // Captured up front: the form may be closed before the request returns.
    final repository = ref.read(emergencyCardRepositoryProvider);
    final store = ref.read(emergencyCardOfflineStoreProvider);
    final bus = ref.read(dataRefreshProvider.notifier);
    final refreshSession = ref.read(emergencyCardSessionRefreshProvider);
    final userId = ref.read(sessionUserIdProvider);
    try {
      final saved = await repository.saveCard(
        memberId,
        normalizeEmergencyCard(card),
      );
      if (userId != null) await store.save(userId, saved);
      bus.markChanged({DataScope.emergencyCards});
      return saved;
    } on ApiException catch (e) {
      if (e.isForbidden || e.code == ApiErrorCode.noFamily) {
        unawaited(
          refreshSession().catchError((Object error) {
            debugPrint('EmergencyCardSaveController: session resync failed');
          }),
        );
      } else if (e.isNotFound) {
        unawaited(store.remove(memberId));
        bus.markChanged({DataScope.members, DataScope.emergencyCards});
      }
      rethrow;
    } finally {
      if (ref.mounted) state = false;
    }
  }
}

final emergencyCardSaveControllerProvider =
    NotifierProvider.autoDispose<EmergencyCardSaveController, bool>(
      EmergencyCardSaveController.new,
    );
