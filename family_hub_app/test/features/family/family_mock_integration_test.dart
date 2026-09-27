// The shared FamilyRepository against the in-memory mock backend with the
// real providers (ApiClient → interceptors → MockBackend → family mocks), so
// request bodies and response shapes of both sides stay compatible.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:family_hub/core/network/mock/mock_backend.dart';
import 'package:family_hub/core/providers/core_providers.dart';
import 'package:family_hub/core/config/countries.dart';
import 'package:family_hub/features/family/domain/member_designation.dart';
import 'package:family_hub/features/family/domain/member_form_data.dart';
import 'package:family_hub/shared/data/family_repository.dart';
import 'package:family_hub/shared/models/models.dart';
import 'package:family_hub/shared/session/session_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> signedInAsDemo() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    await container.read(sessionControllerProvider.future);
    await container
        .read(sessionControllerProvider.notifier)
        .login(email: MockSeed.demoEmail, password: MockSeed.demoPassword);
    return container;
  }

  test(
    'members, add a minor with consent, edit, remove, invite code',
    () async {
      final container = await signedInAsDemo();
      final repo = container.read(familyRepositoryProvider);
      final india = Countries.byCode('IN');

      final members = await repo.getMembers();
      expect(members.map((m) => m.name), [
        'Amit',
        'Priya',
        'Kamla',
        'Aarav',
        'Anaya',
      ]);
      expect(members.first.lastLocation, isNotNull);
      expect(members[3].accountStatus, MemberAccountStatus.invited);

      final now = DateTime.now();
      final child = MemberFormData(
        name: 'Veer',
        birthDate: DateTime(now.year - 6, now.month, 1),
        designation: 'Junior Explorer',
        gender: Gender.male,
      );
      // Without consent the server refuses.
      await expectLater(
        repo.addMember(child.toNewMemberRequest(india)),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            ApiErrorCode.guardianConsentRequired,
          ),
        ),
      );
      final added = await repo.addMember(
        child.copyWith(guardianConsent: true).toNewMemberRequest(india),
      );
      expect(added.guardianConsent, isTrue);
      expect(added.hasAccount, isFalse);
      expect(added.birthDate, child.birthDate);

      final edited = await repo.updateMember(
        added.id,
        MemberFormData.fromMember(added)
            .copyWith(designation: () => 'Chief Fun Officer')
            .toPatch(added, MemberFormAccess.adminEdit, india),
      );
      expect(edited.designation, 'Chief Fun Officer');
      expect(edited.birthDate, child.birthDate);

      await repo.deleteMember(added.id);
      await expectLater(
        repo.getMember(added.id),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            ApiErrorCode.notFound,
          ),
        ),
      );

      final family = await repo.regenerateInviteCode();
      expect(family.inviteCode, isNot(MockSeed.inviteCode));
      expect(family.memberCount, 5);
      final patched = await repo.updateFamily(
        FamilyPatch.diff(family, currency: 'usd'),
      );
      expect(patched.currency, 'USD');
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );
}
