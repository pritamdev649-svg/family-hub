import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/l10n/error_messages.dart';
import 'package:family_hub/core/providers/core_providers.dart';
import 'package:family_hub/features/emergency_card/application/emergency_card_providers.dart';
import 'package:family_hub/features/emergency_card/data/emergency_card_offline_store.dart';
import 'package:family_hub/shared/models/member.dart';
import 'package:family_hub/shared/providers/shared_providers.dart';

import 'emergency_card_test_utils.dart';

void main() {
  late FakeEmergencyCardRepository repo;
  late InMemorySecureStore secure;
  late SessionRefreshSpy spy;

  setUp(() {
    repo = FakeEmergencyCardRepository();
    secure = InMemorySecureStore();
    spy = SessionRefreshSpy();
  });

  Future<ProviderContainer> container({
    Member? me,
    String? userId = testUserId,
    Duration fallbackDelay = const Duration(seconds: 3),
    Object? membersError,
  }) async {
    final c = ProviderContainer(
      retry: (_, _) => null,
      overrides: emergencyOverrides(
        prefs: await mockPrefs(),
        repository: repo,
        secure: secure,
        me: me,
        userId: userId,
        fallbackDelay: fallbackDelay,
        membersError: membersError,
        sessionRefresh: spy,
      ),
    );
    addTearDown(c.dispose);
    return c;
  }

  // Riverpod 3 pauses providers (and their retries) without listeners, so
  // every read goes through a live subscription — like a screen watching it.
  Future<EmergencyCard> card(ProviderContainer c, String id) {
    final sub = c.listen(emergencyCardProvider(id), (_, _) {});
    addTearDown(sub.close);
    return c.read(emergencyCardProvider(id).future);
  }

  Future<List<Member>> members(ProviderContainer c) {
    final sub = c.listen(emergencyCardMembersProvider, (_, _) {});
    addTearDown(sub.close);
    return c.read(emergencyCardMembersProvider.future);
  }

  Future<Object> errorOf(Future<Object?> f) async {
    try {
      await f;
    } catch (e) {
      return unwrapProviderError(e);
    }
    fail('expected an error');
  }

  group('emergencyCardProvider', () {
    test('loads the card and keeps an offline copy', () async {
      repo.cards['m1'] = fullCard('m1');
      final c = await container();

      final loaded = await card(c, 'm1');
      expect(loaded, fullCard('m1'));
      expect(loaded.isOfflineCopy, isFalse);
      await pumpEventQueue();
      final store = c.read(emergencyCardOfflineStoreProvider);
      expect(await store.load(testUserId, 'm1'), isNotNull);
    });

    test('member without a saved card → empty card', () async {
      final c = await container();
      final loaded = await card(c, 'm2');
      expect(loaded.isEmpty, isTrue);
      expect(loaded.memberId, 'm2');
    });

    test('offline → the saved copy, marked as offline copy', () async {
      repo.cards['m1'] = fullCard('m1');
      final c = await container();
      await card(c, 'm1');
      await pumpEventQueue();

      repo.getError = networkError;
      c.invalidate(emergencyCardProvider('m1'));
      final loaded = await card(c, 'm1');
      expect(loaded.isOfflineCopy, isTrue);
      expect(loaded.allergies, ['Penicillin']);
      expect(c.read(emergencyCardProvider('m1')).hasError, isFalse);
    });

    test('server errors (5xx) also fall back to the offline copy', () async {
      repo.cards['m1'] = fullCard('m1');
      final c = await container();
      await card(c, 'm1');
      await pumpEventQueue();

      repo.getError = const ApiException(
        code: ApiErrorCode.internal,
        statusCode: 500,
      );
      c.invalidate(emergencyCardProvider('m1'));
      expect((await card(c, 'm1')).isOfflineCopy, isTrue);
    });

    test('offline without a copy → the network error', () async {
      repo.getError = networkError;
      final c = await container();
      final error = await errorOf(card(c, 'm1'));
      expect(error, isA<ApiException>());
      expect((error as ApiException).isNetwork, isTrue);
    });

    test('NOT_FOUND surfaces and deletes the offline copy', () async {
      repo.cards['m1'] = fullCard('m1');
      final c = await container();
      await card(c, 'm1');
      await pumpEventQueue();

      repo.getError = notFoundError;
      c.invalidate(emergencyCardProvider('m1'));
      final error = await errorOf(card(c, 'm1'));
      expect((error as ApiException).isNotFound, isTrue);
      await pumpEventQueue();
      expect(
        secure.data.containsKey(EmergencyCardOfflineStore.secureKey('m1')),
        isFalse,
      );
    });

    test(
      'cold start on a slow network: offline copy first, then fresh',
      () async {
        final prefs = await mockPrefs();
        await EmergencyCardOfflineStore(
          cache: LocalCache(prefs),
          secure: secure,
        ).save(testUserId, fullCard('m1'));

        final c = ProviderContainer(
          retry: (_, _) => null,
          overrides: emergencyOverrides(
            prefs: prefs,
            repository: repo,
            secure: secure,
            fallbackDelay: Duration.zero,
          ),
        );
        addTearDown(c.dispose);
        final gate = repo.getGate = Completer<void>();
        repo.cards['m1'] = fullCard('m1').copyWith(notes: () => 'fresh');
        final sub = c.listen(emergencyCardProvider('m1'), (_, _) {});
        addTearDown(sub.close);

        await pumpEventQueue();
        final offline = c.read(emergencyCardProvider('m1'));
        expect(offline.value?.isOfflineCopy, isTrue);
        expect(offline.value?.notes, 'Glucose tablets in handbag');

        // A screen opening now must not restart the running request.
        c.read(emergencyCardProvider('m1').notifier).refreshIfStale();
        await pumpEventQueue();
        expect(repo.getCalls, ['m1']);

        gate.complete();
        await pumpEventQueue();
        final fresh = c.read(emergencyCardProvider('m1')).value;
        expect(fresh?.isOfflineCopy, isFalse);
        expect(fresh?.notes, 'fresh');
      },
    );

    test(
      'slow refresh keeps the fresh card instead of the offline copy',
      () async {
        repo.cards['m1'] = fullCard('m1');
        final c = await container(fallbackDelay: Duration.zero);
        await card(c, 'm1');
        await pumpEventQueue();

        final gate = repo.getGate = Completer<void>();
        c.invalidate(emergencyCardProvider('m1'));
        await pumpEventQueue();
        final refreshing = c.read(emergencyCardProvider('m1'));
        expect(refreshing.isLoading, isTrue);
        expect(refreshing.value?.isOfflineCopy, isFalse);

        gate.complete();
        await pumpEventQueue();
        expect(c.read(emergencyCardProvider('m1')).isLoading, isFalse);
      },
    );

    test('slow network that then fails keeps the offline copy', () async {
      repo.cards['m1'] = fullCard('m1');
      final c = await container(fallbackDelay: Duration.zero);
      await card(c, 'm1');
      await pumpEventQueue();

      final gate = repo.getGate = Completer<void>();
      repo.getError = const ApiException(code: ApiErrorCode.timeout);
      c.invalidate(emergencyCardProvider('m1'));
      final sub = c.listen(emergencyCardProvider('m1'), (_, _) {});
      addTearDown(sub.close);
      await pumpEventQueue();
      gate.complete();
      await pumpEventQueue();

      final state = c.read(emergencyCardProvider('m1'));
      expect(state.hasError, isFalse);
      expect(state.value?.isOfflineCopy, isTrue);
    });

    test('signed out → NOT_FOUND without a request', () async {
      final c = await container(userId: null);
      final error = await errorOf(card(c, 'm1'));
      expect((error as ApiException).isNotFound, isTrue);
      expect(repo.getCalls, isEmpty);
    });

    test('an offline copy refreshes by itself once back online', () async {
      repo.cards['m1'] = fullCard('m1');
      final c = await container();
      await card(c, 'm1');
      await pumpEventQueue();

      // The request fails without a response: the client reports offline.
      final connectivity = c.read(connectivityStatusProvider.notifier);
      repo.getError = networkError;
      connectivity.report(false);
      c.invalidate(emergencyCardProvider('m1'));
      expect((await card(c, 'm1')).isOfflineCopy, isTrue);
      final calls = repo.getCalls.length;

      // Any later request that reaches the server flips it back online.
      repo.getError = null;
      repo.cards['m1'] = fullCard('m1').copyWith(notes: () => 'fresh');
      connectivity.report(true);
      await pumpEventQueue();
      expect(repo.getCalls.length, calls + 1);
      final state = c.read(emergencyCardProvider('m1')).value;
      expect(state?.isOfflineCopy, isFalse);
      expect(state?.notes, 'fresh');

      // Only the offline copy listens: a fresh card does not refetch again.
      connectivity
        ..report(false)
        ..report(true);
      await pumpEventQueue();
      expect(repo.getCalls.length, calls + 1);
    });

    test(
      'refreshIfStale refetches old cards and offline copies only',
      () async {
        repo.cards['m1'] = fullCard('m1');
        final c = await container();
        await card(c, 'm1');
        final notifier = c.read(emergencyCardProvider('m1').notifier);

        notifier.refreshIfStale(); // just loaded
        await pumpEventQueue();
        expect(repo.getCalls, ['m1']);

        notifier.refreshIfStale(maxAge: Duration.zero); // "older" than allowed
        await pumpEventQueue();
        expect(repo.getCalls, ['m1', 'm1']);

        repo.getError = networkError;
        c.invalidate(emergencyCardProvider('m1'));
        expect((await card(c, 'm1')).isOfflineCopy, isTrue);
        final calls = repo.getCalls.length;
        repo.getError = null;
        notifier.refreshIfStale(); // offline copies are always retried
        await pumpEventQueue();
        expect(repo.getCalls.length, calls + 1);
        expect(
          c.read(emergencyCardProvider('m1')).value?.isOfflineCopy,
          isFalse,
        );
      },
    );

    test('refreshIfStale does nothing while the first load runs', () async {
      final gate = repo.getGate = Completer<void>();
      final c = await container();
      final sub = c.listen(emergencyCardProvider('m1'), (_, _) {});
      addTearDown(sub.close);
      await pumpEventQueue();
      c.read(emergencyCardProvider('m1').notifier).refreshIfStale();
      gate.complete();
      await pumpEventQueue();
      expect(repo.getCalls, ['m1']);
    });

    test(
      'an account switch mid-request leaves nothing of the old account',
      () async {
        repo.cards['m1'] = fullCard('m1');
        final c = ProviderContainer(
          retry: (_, _) => null,
          overrides: emergencyOverrides(
            prefs: await mockPrefs(),
            repository: repo,
            secure: secure,
            fallbackDelay: Duration.zero,
            userIdBuilder: (ref) => ref.watch(_userIdProvider),
          ),
        );
        addTearDown(c.dispose);
        final gate = repo.getGate = Completer<void>();
        final sub = c.listen(emergencyCardProvider('m1'), (_, _) {});
        addTearDown(sub.close);
        await pumpEventQueue();

        // Signed out while the request of the old account is in flight.
        c.read(_userIdProvider.notifier).set(null);
        await pumpEventQueue();
        gate.complete();
        await pumpEventQueue();

        expect(secure.data, isEmpty);
        final state = c.read(emergencyCardProvider('m1'));
        expect(state.value?.memberId == 'm1' && !state.hasError, isFalse);
      },
    );

    test('refetches on markChanged(emergencyCards)', () async {
      final c = await container();
      final sub = c.listen(emergencyCardProvider('m1'), (_, _) {});
      addTearDown(sub.close);
      await card(c, 'm1');
      expect(repo.getCalls, ['m1']);

      c.read(dataRefreshProvider.notifier).markChanged({DataScope.tasks});
      await pumpEventQueue();
      expect(repo.getCalls, ['m1']);

      c.read(dataRefreshProvider.notifier).markChanged({
        DataScope.emergencyCards,
      });
      await pumpEventQueue();
      expect(repo.getCalls, ['m1', 'm1']);
    });
  });

  group('emergencyCardMembersProvider', () {
    test('returns the members and caches the directory', () async {
      final c = await container();
      expect(await members(c), testMembers);
      await pumpEventQueue();
      expect(
        c.read(emergencyCardOfflineStoreProvider).loadMembers(testUserId),
        hasLength(testMembers.length),
      );
    });

    test('offline → the cached directory', () async {
      final prefs = await mockPrefs();
      final first = ProviderContainer(
        retry: (_, _) => null,
        overrides: emergencyOverrides(
          prefs: prefs,
          repository: repo,
          secure: secure,
        ),
      );
      addTearDown(first.dispose);
      await members(first);
      await pumpEventQueue();

      final offline = ProviderContainer(
        retry: (_, _) => null,
        overrides: emergencyOverrides(
          prefs: prefs,
          repository: repo,
          secure: secure,
          membersError: networkError,
        ),
      );
      addTearDown(offline.dispose);
      final loaded = await members(offline);
      expect(loaded.map((m) => m.id), testMembers.map((m) => m.id));
    });

    test('offline without a cache → the error', () async {
      final c = await container(membersError: networkError);
      final error = await errorOf(members(c));
      expect((error as ApiException).isNetwork, isTrue);
    });

    test(
      'emergencyCardMemberProvider finds members; null when unknown',
      () async {
        final c = await container();
        expect(
          await c.read(emergencyCardMemberProvider(kamla.id).future),
          kamla,
        );
        expect(
          await c.read(emergencyCardMemberProvider('nobody').future),
          isNull,
        );
      },
    );
  });

  group('canEditEmergencyCardProvider', () {
    test('admins edit everyone; members only themselves', () async {
      final admin = await container(me: amit);
      expect(admin.read(canEditEmergencyCardProvider(kamla.id)), isTrue);

      final member = await container(me: aarav);
      expect(member.read(canEditEmergencyCardProvider(aarav.id)), isTrue);
      expect(member.read(canEditEmergencyCardProvider(kamla.id)), isFalse);

      final signedOut = await container(userId: null);
      expect(signedOut.read(canEditEmergencyCardProvider(kamla.id)), isFalse);
    });
  });

  group('EmergencyCardSaveController', () {
    test(
      'normalises, saves, refreshes the offline copy and marks changed',
      () async {
        final c = await container();
        final sub = c.listen(emergencyCardSaveControllerProvider, (_, _) {});
        addTearDown(sub.close);
        final before = c.read(dataRefreshProvider)[DataScope.emergencyCards];

        final saved = await c
            .read(emergencyCardSaveControllerProvider.notifier)
            .save(
              'm1',
              EmergencyCard(
                memberId: 'm1',
                bloodGroup: BloodGroup.aPositive,
                allergies: const [' Dust ', 'dust', ''],
                doctorPhone: '+91 98765-43210',
                emergencyContacts: const [
                  EmergencyContact(name: ' Ravi ', phone: '०९८७६५४३२१०'),
                  EmergencyContact(name: ''),
                ],
                notes: '  ',
              ),
            );

        expect(saved, isNotNull);
        final sent = repo.saveCalls.single.$2;
        expect(sent.allergies, ['Dust']);
        expect(sent.doctorPhone, '+919876543210');
        expect(sent.emergencyContacts, const [
          EmergencyContact(name: 'Ravi', phone: '09876543210'),
        ]);
        expect(sent.notes, isNull);
        expect(
          c.read(dataRefreshProvider)[DataScope.emergencyCards],
          before! + 1,
        );
        expect(
          (await c
                  .read(emergencyCardOfflineStoreProvider)
                  .load(testUserId, 'm1'))
              ?.allergies,
          ['Dust'],
        );
        expect(c.read(emergencyCardSaveControllerProvider), isFalse);
      },
    );

    test('busy while saving; a second save meanwhile is ignored', () async {
      final c = await container();
      final sub = c.listen(emergencyCardSaveControllerProvider, (_, _) {});
      addTearDown(sub.close);
      final controller = c.read(emergencyCardSaveControllerProvider.notifier);
      final gate = repo.saveGate = Completer<void>();

      final first = controller.save('m1', fullCard('m1'));
      await pumpEventQueue();
      expect(c.read(emergencyCardSaveControllerProvider), isTrue);
      expect(await controller.save('m1', fullCard('m1')), isNull);

      gate.complete();
      expect(await first, isNotNull);
      expect(repo.saveCalls, hasLength(1));
      expect(c.read(emergencyCardSaveControllerProvider), isFalse);
    });

    test('errors are rethrown, nothing is marked changed', () async {
      final c = await container();
      final sub = c.listen(emergencyCardSaveControllerProvider, (_, _) {});
      addTearDown(sub.close);
      repo.saveError = const ApiException(
        code: ApiErrorCode.validation,
        statusCode: 422,
      );
      final before = c.read(dataRefreshProvider);

      await expectLater(
        c
            .read(emergencyCardSaveControllerProvider.notifier)
            .save('m1', fullCard('m1')),
        throwsA(isA<ApiException>()),
      );
      expect(c.read(dataRefreshProvider), before);
      expect(c.read(emergencyCardSaveControllerProvider), isFalse);
      expect(spy.calls, 0);
    });

    test('FORBIDDEN / NO_FAMILY re-read the session', () async {
      final c = await container();
      final sub = c.listen(emergencyCardSaveControllerProvider, (_, _) {});
      addTearDown(sub.close);
      final controller = c.read(emergencyCardSaveControllerProvider.notifier);

      for (final code in [ApiErrorCode.forbidden, ApiErrorCode.noFamily]) {
        repo.saveError = ApiException(code: code, statusCode: 403);
        await expectLater(
          controller.save('m1', fullCard('m1')),
          throwsA(isA<ApiException>()),
        );
      }
      await pumpEventQueue();
      expect(spy.calls, 2);
      expect(c.read(emergencyCardSaveControllerProvider), isFalse);
    });

    test(
      'NOT_FOUND (member removed) refetches members + cards, drops the copy',
      () async {
        repo.cards['m1'] = fullCard('m1');
        final c = await container();
        await card(c, 'm1');
        await pumpEventQueue();
        expect(secure.data, isNotEmpty);
        final sub = c.listen(emergencyCardSaveControllerProvider, (_, _) {});
        addTearDown(sub.close);
        final before = c.read(dataRefreshProvider);

        // The member was removed on the server: GET and PUT answer 404.
        repo.saveError = notFoundError;
        repo.getError = notFoundError;
        await expectLater(
          c
              .read(emergencyCardSaveControllerProvider.notifier)
              .save('m1', fullCard('m1')),
          throwsA(isA<ApiException>()),
        );
        await pumpEventQueue();
        final after = c.read(dataRefreshProvider);
        expect(after[DataScope.members], before[DataScope.members]! + 1);
        expect(
          after[DataScope.emergencyCards],
          before[DataScope.emergencyCards]! + 1,
        );
        expect(secure.data, isEmpty);
        expect(spy.calls, 0);
      },
    );

    test(
      'a save that finishes after logout keeps nothing on the device',
      () async {
        final c = ProviderContainer(
          retry: (_, _) => null,
          overrides: emergencyOverrides(
            prefs: await mockPrefs(),
            repository: repo,
            secure: secure,
            userIdBuilder: (ref) => ref.watch(_userIdProvider),
          ),
        );
        addTearDown(c.dispose);
        final sub = c.listen(emergencyCardSaveControllerProvider, (_, _) {});
        addTearDown(sub.close);
        final gate = repo.saveGate = Completer<void>();

        final saving = c
            .read(emergencyCardSaveControllerProvider.notifier)
            .save('m1', fullCard('m1'));
        await pumpEventQueue();
        c.read(_userIdProvider.notifier).set(null); // logout
        await pumpEventQueue();
        gate.complete();
        await saving;
        await pumpEventQueue();
        expect(secure.data, isEmpty);
      },
    );
  });

  test('offline copies are wiped when the account changes', () async {
    repo.cards['m1'] = fullCard('m1');
    final c = ProviderContainer(
      retry: (_, _) => null,
      overrides: emergencyOverrides(
        prefs: await mockPrefs(),
        repository: repo,
        secure: secure,
        userIdBuilder: (ref) => ref.watch(_userIdProvider),
      ),
    );
    addTearDown(c.dispose);
    final sub = c.listen(emergencyCardProvider('m1'), (_, _) {});
    addTearDown(sub.close);
    await c.read(emergencyCardProvider('m1').future);
    await pumpEventQueue();
    expect(secure.data, isNotEmpty);

    c.read(_userIdProvider.notifier).set(null); // logout
    await pumpEventQueue();
    expect(secure.data, isEmpty);
  });

  test('isUnreachableError', () {
    expect(isUnreachableError(networkError), isTrue);
    expect(
      isUnreachableError(const ApiException(code: ApiErrorCode.timeout)),
      isTrue,
    );
    expect(
      isUnreachableError(
        const ApiException(code: ApiErrorCode.internal, statusCode: 500),
      ),
      isTrue,
    );
    expect(isUnreachableError(notFoundError), isFalse);
    expect(isUnreachableError(StateError('x')), isFalse);
  });
}

/// Signed-in user id that a test can change (logout / account switch).
final _userIdProvider = NotifierProvider<_UserId, String?>(_UserId.new);

class _UserId extends Notifier<String?> {
  @override
  String? build() => testUserId;

  void set(String? value) => state = value;
}
