import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/network/api_exception.dart';
import 'package:family_hub/features/family/application/family_providers.dart';
import 'package:family_hub/features/family/application/family_session_sync.dart';
import 'package:family_hub/features/family/application/family_settings_controller.dart';
import 'package:family_hub/features/family/application/member_editor_controller.dart';
import 'package:family_hub/features/family/application/member_removal_controller.dart';
import 'package:family_hub/features/family/domain/member_form_data.dart';
import 'package:family_hub/shared/data/family_repository.dart';
import 'package:family_hub/shared/models/models.dart';
import 'package:family_hub/shared/session/session_controller.dart';

import 'family_test_utils.dart';

void main() {
  late FakeFamilyRepository repo;
  late FakeSession session;
  late ProviderContainer container;

  Future<void> setUpAs(Member me, {Family? family}) async {
    repo = FakeFamilyRepository(
      members: [amit, kamla, aarav, anaya],
      family: family,
    );
    session = FakeSession(sessionFor(me, family: family));
    container = await createFamilyContainer(repo: repo, session: session);
    // Keep the auto-dispose controllers alive like a screen would.
    container.listen(memberEditorControllerProvider, (_, _) {});
    container.listen(memberRemovalControllerProvider, (_, _) {});
    container.listen(familySettingsControllerProvider, (_, _) {});
  }

  Map<DataScope, int> scopes() => container.read(dataRefreshProvider);

  MemberEditorController editor() =>
      container.read(memberEditorControllerProvider.notifier);

  group('MemberEditorController.add', () {
    setUp(() => setUpAs(amit));

    test('creates the member, saves the photo, announces the change', () async {
      final before = scopes();
      final result = await editor().add(
        MemberFormData(
          name: 'Anvi',
          birthDate: birthDateForAge(5),
          avatarUrl: 'https://res.cloudinary.com/demo/a.jpg',
          guardianConsent: true,
        ),
      );
      expect(result, isNotNull);
      expect(result!.avatarSaved, isTrue);
      expect(result.member.avatarUrl, 'https://res.cloudinary.com/demo/a.jpg');
      expect(repo.calls, ['addMember', 'updateMember ${result.member.id}']);
      final body = repo.bodies.first! as Map<String, dynamic>;
      expect(body['guardianConsent'], isTrue);
      expect(body.containsKey('avatarUrl'), isFalse);
      expect(repo.bodies[1], {
        'avatarUrl': 'https://res.cloudinary.com/demo/a.jpg',
      });

      final after = scopes();
      expect(after[DataScope.members], before[DataScope.members]! + 1);
      expect(after[DataScope.family], before[DataScope.family]! + 1);
      expect(after[DataScope.tasks], before[DataScope.tasks]);
      expect(container.read(memberEditorControllerProvider).hasError, isFalse);
    });

    test('a failed photo save still reports the created member', () async {
      repo.updateError = apiError(ApiErrorCode.validation, 422);
      final result = await editor().add(
        const MemberFormData(name: 'Dadi', avatarUrl: '/tmp/p.jpg'),
      );
      expect(result!.avatarSaved, isFalse);
      expect(repo.members.map((m) => m.name), contains('Dadi'));
    });

    test(
      'errors are rethrown, state is AsyncError, nothing announced',
      () async {
        repo.addError = apiError(ApiErrorCode.guardianConsentRequired, 422);
        final before = scopes();
        await expectLater(
          editor().add(
            MemberFormData(name: 'Kid', birthDate: birthDateForAge(4)),
          ),
          throwsA(
            isA<ApiException>().having(
              (e) => e.code,
              'code',
              ApiErrorCode.guardianConsentRequired,
            ),
          ),
        );
        expect(container.read(memberEditorControllerProvider).hasError, isTrue);
        expect(scopes(), before);
      },
    );

    test('a second submit while busy is ignored', () async {
      repo.gate = Completer<void>();
      final first = editor().add(const MemberFormData(name: 'One'));
      await Future<void>.delayed(Duration.zero);
      expect(container.read(memberEditorControllerProvider).isLoading, isTrue);
      expect(await editor().add(const MemberFormData(name: 'Two')), isNull);
      repo.gate!.complete();
      expect(await first, isNotNull);
      expect(repo.calls.where((c) => c == 'addMember'), hasLength(1));
      expect(container.read(memberEditorControllerProvider).isLoading, isFalse);
    });

    test(
      'timeout: the member may exist → the member list is refetched',
      () async {
        repo.addError = const ApiException.timeout();
        final before = scopes();
        await expectLater(
          editor().add(const MemberFormData(name: 'Dadi')),
          throwsA(isA<ApiException>()),
        );
        final after = scopes();
        expect(after[DataScope.members], before[DataScope.members]! + 1);
        expect(after[DataScope.family], before[DataScope.family]! + 1);
        expect(session.refreshes, 0);
      },
    );

    test('FORBIDDEN (demoted elsewhere) resyncs the session', () async {
      repo.addError = apiError(ApiErrorCode.forbidden, 403);
      await expectLater(
        editor().add(const MemberFormData(name: 'Dadi')),
        throwsA(isA<ApiException>()),
      );
      await pumpEventQueue();
      expect(session.refreshes, 1);
    });

    test('consentRequired sends the ticked consent for an "adult"', () async {
      final adult = MemberFormData(
        name: 'Rohan',
        birthDate: birthDateForAge(19),
        guardianConsent: true,
      );
      await editor().add(adult);
      expect((repo.lastBody('addMember')! as Map)['guardianConsent'], isFalse);
      await editor().add(adult, consentRequired: true);
      expect((repo.lastBody('addMember')! as Map)['guardianConsent'], isTrue);
    });
  });

  group('MemberEditorController.update', () {
    test('editing another member does not touch the session', () async {
      await setUpAs(amit);
      final data = MemberFormData.fromMember(
        kamla,
      ).copyWith(designation: () => 'Chief Mentor');
      final updated = await editor().update(
        kamla,
        data,
        MemberFormAccess.adminEdit,
      );
      expect(updated!.designation, 'Chief Mentor');
      expect(repo.bodies.single, {'designation': 'Chief Mentor'});
      expect(session.applied, isEmpty);
    });

    test('editing yourself updates the session; a rename refreshes '
        'denormalised names elsewhere', () async {
      await setUpAs(kamla);
      final before = scopes();
      final data = MemberFormData.fromMember(
        kamla,
      ).copyWith(name: 'Kamla Devi');
      final updated = await editor().update(
        kamla,
        data,
        MemberFormAccess.selfEdit,
      );
      expect(updated!.name, 'Kamla Devi');
      expect(session.applied.single.member?.name, 'Kamla Devi');
      expect(container.read(currentMemberProvider)?.name, 'Kamla Devi');
      final after = scopes();
      for (final s in [
        DataScope.members,
        DataScope.tasks,
        DataScope.notices,
        DataScope.sos,
      ]) {
        expect(after[s], greaterThan(before[s]!), reason: '$s');
      }
    });

    test('no changes → no request, returns the member', () async {
      await setUpAs(amit);
      final result = await editor().update(
        anaya,
        MemberFormData.fromMember(anaya),
        MemberFormAccess.adminEdit,
      );
      expect(result, anaya);
      expect(repo.calls, isEmpty);
    });

    test('LAST_ADMIN is rethrown', () async {
      await setUpAs(amit);
      repo.updateError = apiError(ApiErrorCode.lastAdmin);
      await expectLater(
        editor().update(
          kamla,
          MemberFormData.fromMember(kamla).copyWith(role: MemberRole.admin),
          MemberFormAccess.adminEdit,
        ),
        throwsA(isA<ApiException>()),
      );
    });

    test('NOT_FOUND (removed meanwhile) refetches the member list', () async {
      await setUpAs(amit);
      repo.updateError = apiError(ApiErrorCode.notFound, 404);
      final before = scopes();
      await expectLater(
        editor().update(
          kamla,
          MemberFormData.fromMember(kamla).copyWith(name: 'K'),
          MemberFormAccess.adminEdit,
        ),
        throwsA(isA<ApiException>()),
      );
      expect(scopes()[DataScope.members], before[DataScope.members]! + 1);
      expect(scopes()[DataScope.tasks], before[DataScope.tasks]);
    });
  });

  group('MemberRemovalController', () {
    setUp(() => setUpAs(amit));

    test('deletes and refreshes every scope the cascade touches', () async {
      final before = scopes();
      final outcome = await container
          .read(memberRemovalControllerProvider.notifier)
          .remove(kamla);
      expect(outcome, MemberRemovalOutcome.removed);
      expect(repo.calls, ['deleteMember ${kamla.id}']);
      final after = scopes();
      for (final s in memberRemovalScopes) {
        expect(after[s], before[s]! + 1, reason: '$s');
      }
      expect(after[DataScope.ledger], before[DataScope.ledger]);
    });

    test('LAST_ADMIN → rethrown, state AsyncError; the list is refetched '
        '(it was stale) but no cascade is announced', () async {
      repo.deleteError = apiError(ApiErrorCode.lastAdmin);
      final before = scopes();
      await expectLater(
        container.read(memberRemovalControllerProvider.notifier).remove(amit),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'LAST_ADMIN'),
        ),
      );
      expect(container.read(memberRemovalControllerProvider).hasError, isTrue);
      final after = scopes();
      expect(after[DataScope.members], before[DataScope.members]! + 1);
      expect(after[DataScope.tasks], before[DataScope.tasks]);
      expect(after[DataScope.emergencyCards], before[DataScope.emergencyCards]);
    });

    test('NOT_FOUND → already removed: success, cascade announced', () async {
      repo.deleteError = apiError(ApiErrorCode.notFound, 404);
      final before = scopes();
      final outcome = await container
          .read(memberRemovalControllerProvider.notifier)
          .remove(kamla);
      expect(outcome, MemberRemovalOutcome.alreadyRemoved);
      expect(container.read(memberRemovalControllerProvider).hasError, isFalse);
      for (final s in memberRemovalScopes) {
        expect(scopes()[s], before[s]! + 1, reason: '$s');
      }
    });

    test(
      'offline: the removal may have happened → cascade refetched',
      () async {
        repo.deleteError = const ApiException.network();
        final before = scopes();
        await expectLater(
          container
              .read(memberRemovalControllerProvider.notifier)
              .remove(kamla),
          throwsA(isA<ApiException>()),
        );
        for (final s in memberRemovalScopes) {
          expect(scopes()[s], before[s]! + 1, reason: '$s');
        }
      },
    );

    test('a second removal while one runs is ignored', () async {
      repo.gate = Completer<void>();
      final controller = container.read(
        memberRemovalControllerProvider.notifier,
      );
      final first = controller.remove(kamla);
      await Future<void>.delayed(Duration.zero);
      expect(await controller.remove(kamla), MemberRemovalOutcome.busy);
      repo.gate!.complete();
      expect(await first, MemberRemovalOutcome.removed);
      expect(
        repo.calls.where((c) => c.startsWith('deleteMember')),
        hasLength(1),
      );
    });
  });

  group('FamilySettingsController', () {
    setUp(() => setUpAs(amit));

    FamilySettingsController controller() =>
        container.read(familySettingsControllerProvider.notifier);

    test('sends only changed fields and updates the session', () async {
      final before = scopes();
      final family = testFamily();
      final saved = await controller().save(
        family,
        name: ' Sharma Parivar ',
        country: 'IN',
        currency: 'USD',
        timezone: family.timezone,
      );
      expect(repo.bodies.single, {'name': 'Sharma Parivar', 'currency': 'USD'});
      expect(saved!.currency, 'USD');
      expect(session.applied.single.family, saved);
      expect(container.read(currentFamilyProvider)?.currency, 'USD');
      final after = scopes();
      expect(after[DataScope.family], greaterThan(before[DataScope.family]!));
      expect(after[DataScope.ledger], greaterThan(before[DataScope.ledger]!));
      expect(after[DataScope.tasks], before[DataScope.tasks]);
      expect(container.read(familySettingsControllerProvider), isNull);
    });

    test('no changes → no request', () async {
      final family = testFamily();
      final result = await controller().save(family, name: family.name);
      expect(result, family);
      expect(repo.calls, isEmpty);
    });

    test('regenerating the invite code updates the session', () async {
      final family = await controller().regenerateInviteCode();
      expect(family!.inviteCode, 'N3WCQDE7');
      expect(container.read(currentFamilyProvider)?.inviteCode, 'N3WCQDE7');
      expect(repo.calls, ['regenerateInviteCode']);
    });

    test('timeout on a new code → the family is refetched', () async {
      repo.regenerateError = const ApiException.timeout();
      final before = scopes();
      await expectLater(
        controller().regenerateInviteCode(),
        throwsA(isA<ApiException>()),
      );
      expect(scopes()[DataScope.family], before[DataScope.family]! + 1);
      expect(container.read(familySettingsControllerProvider), isNull);
    });

    test('FORBIDDEN on save resyncs the session', () async {
      repo.updateFamilyError = apiError(ApiErrorCode.forbidden, 403);
      await expectLater(
        controller().save(testFamily(), name: 'New name'),
        throwsA(isA<ApiException>()),
      );
      await pumpEventQueue();
      expect(session.refreshes, 1);
    });

    test('scopesForPatch: time zone also refreshes tasks', () {
      final patch = FamilyPatch.diff(testFamily(), timezone: 'Asia/Dubai');
      expect(FamilySettingsController.scopesForPatch(patch), {
        DataScope.family,
        DataScope.ledger,
        DataScope.goals,
        DataScope.tasks,
      });
      final rename = FamilyPatch.diff(testFamily(), name: 'New');
      expect(FamilySettingsController.scopesForPatch(rename), {
        DataScope.family,
      });
    });
  });

  group('familyProvider', () {
    test('fetches GET /family and refetches on DataScope.family', () async {
      await setUpAs(amit);
      container.listen(familyProvider, (_, _) {});
      expect(await container.read(familyProvider.future), repo.family);
      repo.family = repo.family.copyWith(memberCount: 9);
      container.read(dataRefreshProvider.notifier).markChanged({
        DataScope.family,
      });
      expect((await container.read(familyProvider.future))?.memberCount, 9);
      expect(repo.calls.where((c) => c == 'getFamily'), hasLength(2));
    });

    test(
      'refetches when the role changes (invite code is admin-only)',
      () async {
        await setUpAs(kamla);
        repo.family = testFamily(inviteCode: null);
        container.listen(familyProvider, (_, _) {});
        expect(
          (await container.read(familyProvider.future))?.inviteCode,
          isNull,
        );

        repo.family = testFamily();
        await session.applyMe(null, kamla.copyWith(role: MemberRole.admin));
        expect(
          (await container.read(familyProvider.future))?.inviteCode,
          'K7Q2M9XD',
        );
      },
    );
  });

  group('FamilySessionSync', () {
    FamilySessionSync sync() => container.read(familySessionSyncProvider);

    test('applies a role change of the signed-in member', () async {
      await setUpAs(amit);
      final demoted = amit.copyWith(role: MemberRole.member);
      sync().syncSelf([demoted, kamla]);
      await pumpEventQueue();
      expect(session.applied.single.member, demoted);
      expect(container.read(isAdminProvider), isFalse);
    });

    test('ignores location-only differences and other members', () async {
      await setUpAs(amit);
      sync().syncSelf([
        amit.copyWith(
          lastLocation: () =>
              GeoPoint(lat: 1, lng: 2, recordedAt: DateTime(2026)),
          updatedAt: () => DateTime(2026),
        ),
        kamla.copyWith(name: 'Renamed'),
      ]);
      await pumpEventQueue();
      expect(session.applied, isEmpty);
    });

    test('a list without me → session resync', () async {
      await setUpAs(amit);
      sync().syncSelf([kamla]);
      await pumpEventQueue();
      expect(session.refreshes, 1);
    });

    test('a fresher family is merged; the same family is not', () async {
      await setUpAs(amit);
      sync().syncFamily(testFamily(inviteCode: 'K7Q2M9XD'));
      await pumpEventQueue();
      expect(session.applied, isEmpty);
      final renamed = testFamily().copyWith(name: 'Sharma Parivar');
      sync().syncFamily(renamed);
      await pumpEventQueue();
      expect(session.applied.single.family, renamed);
    });

    test('stale-session errors share one resync; others are ignored', () async {
      await setUpAs(amit);
      session.refreshGate = Completer<void>();
      sync()
        ..resyncIfStale(apiError(ApiErrorCode.noFamily, 403))
        ..resyncIfStale(apiError(ApiErrorCode.forbidden, 403))
        ..resyncIfStale(apiError(ApiErrorCode.validation, 422))
        ..resyncIfStale(const ApiException.network());
      await pumpEventQueue();
      expect(session.refreshes, 1);
      session.refreshGate!.complete();
      await pumpEventQueue();
      sync().resyncIfStale(apiError(ApiErrorCode.noFamily, 403));
      await pumpEventQueue();
      expect(session.refreshes, 2);
    });
  });
}
