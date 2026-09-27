import 'package:family_hub/core/network/mock/mock_db.dart';

/// Core demo data of the mock backend: the "Sharma Family" (India).
///
/// Stable ids so feature seeds (tasks, ledger, notices…) can reference the
/// same members across app restarts — the mock database lives in memory
/// but tokens persist in secure storage.
///
/// Demo logins (OTP in mock mode is always [otp]):
/// * `demo@familyhub.app` / `demo1234` → Amit (admin, Head of Family)
/// * `priya@familyhub.app` / `demo1234` → Priya (admin, Finance Head)
///
/// Aarav was pre-added by an admin with `aarav@familyhub.app` and no account:
/// registering with that email in `join` mode + invite code [inviteCode]
/// links the new account to his existing member profile.
abstract final class MockSeed {
  static const familyId = '64f1a0000000000000000001';

  static const amitUserId = '64f1a0000000000000000101';
  static const priyaUserId = '64f1a0000000000000000102';

  static const amitMemberId = '64f1a0000000000000000201';
  static const priyaMemberId = '64f1a0000000000000000202';
  static const aaravMemberId = '64f1a0000000000000000203';
  static const anayaMemberId = '64f1a0000000000000000204';
  static const kamlaMemberId = '64f1a0000000000000000205';

  static const inviteCode = 'DEMO2345';
  static const demoEmail = 'demo@familyhub.app';
  static const priyaEmail = 'priya@familyhub.app';
  static const aaravEmail = 'aarav@familyhub.app';
  static const demoPassword = 'demo1234';

  /// Every OTP (email verification, password reset) in mock mode.
  static const otp = '123456';

  /// All member ids of the demo family (admins first, then by age).
  static const memberIds = [
    amitMemberId,
    priyaMemberId,
    kamlaMemberId,
    aaravMemberId,
    anayaMemberId,
  ];

  /// Seeds `families`, `users` and `members` (once per [MockDb]).
  static void seedCore(MockDb db) {
    final now = DateTime.now();
    String daysAgo(int d) => MockDb.iso(now.subtract(Duration(days: d)));
    // Date-only fields: local midnight → UTC, exactly what the app sends.
    String dob(int y, int m, int d) => MockDb.iso(DateTime(y, m, d));
    final created = daysAgo(120);

    db.seedOnce(
      MockDb.families,
      () => [
        {
          'id': familyId,
          'name': 'Sharma Family',
          'inviteCode': inviteCode,
          'country': 'IN',
          'currency': 'INR',
          'timezone': 'Asia/Kolkata',
          'ownerId': amitUserId,
          'createdAt': created,
          'updatedAt': created,
        },
      ],
    );

    db.seedOnce(
      MockDb.users,
      () => [
        {
          'id': amitUserId,
          'email': demoEmail,
          // Plain text on purpose: this is an in-memory demo backend.
          'password': demoPassword,
          'name': 'Amit Sharma',
          'locale': 'en',
          'emailVerified': true,
          'familyId': familyId,
          'memberId': amitMemberId,
          'consentAcceptedAt': created,
          'failedLoginCount': 0,
          'lockUntil': null,
          'lastLoginAt': null,
          'createdAt': created,
          'updatedAt': created,
        },
        {
          'id': priyaUserId,
          'email': priyaEmail,
          'password': demoPassword,
          'name': 'Priya Sharma',
          'locale': 'en',
          'emailVerified': true,
          'familyId': familyId,
          'memberId': priyaMemberId,
          'consentAcceptedAt': daysAgo(118),
          'failedLoginCount': 0,
          'lockUntil': null,
          'lastLoginAt': null,
          'createdAt': daysAgo(118),
          'updatedAt': daysAgo(118),
        },
      ],
    );

    Map<String, dynamic> member({
      required String id,
      required String name,
      required String role,
      required String designation,
      required String dateOfBirth,
      required String gender,
      String? userId,
      String? email,
      String? phone,
      String locationSharing = 'never',
      Map<String, dynamic>? lastLocation,
      bool guardianConsent = false,
      required String createdAt,
    }) => {
      'id': id,
      'familyId': familyId,
      'userId': userId,
      'name': name,
      'email': email,
      'phone': phone,
      'avatarUrl': null,
      'dateOfBirth': dateOfBirth,
      'gender': gender,
      'designation': designation,
      'role': role,
      'locationSharing': locationSharing,
      'lastLocation': lastLocation,
      'guardianConsent': guardianConsent,
      'guardianConsentAt': guardianConsent ? createdAt : null,
      'guardianConsentById': guardianConsent ? amitMemberId : null,
      'createdAt': createdAt,
      'updatedAt': createdAt,
    };

    db.seedOnce(
      MockDb.members,
      () => [
        member(
          id: amitMemberId,
          userId: amitUserId,
          name: 'Amit',
          email: demoEmail,
          phone: '+919876543210',
          role: 'admin',
          designation: 'Head of Family',
          dateOfBirth: dob(1985, 2, 1),
          gender: 'male',
          locationSharing: 'always',
          lastLocation: {
            'lat': 28.6139,
            'lng': 77.2090,
            'accuracy': 15.0,
            'recordedAt': MockDb.iso(now.subtract(const Duration(minutes: 12))),
          },
          createdAt: created,
        ),
        member(
          id: priyaMemberId,
          userId: priyaUserId,
          name: 'Priya',
          email: priyaEmail,
          phone: '+919876543211',
          role: 'admin',
          designation: 'Finance Head',
          dateOfBirth: dob(1987, 7, 19),
          gender: 'female',
          locationSharing: 'sos_only',
          createdAt: daysAgo(118),
        ),
        member(
          id: aaravMemberId,
          email: aaravEmail,
          name: 'Aarav',
          role: 'member',
          designation: 'Chief Study Officer',
          dateOfBirth: dob(2010, 5, 14),
          gender: 'male',
          guardianConsent: true,
          createdAt: daysAgo(115),
        ),
        member(
          id: anayaMemberId,
          name: 'Anaya',
          role: 'member',
          designation: 'Junior Explorer',
          dateOfBirth: dob(2016, 8, 1),
          gender: 'female',
          guardianConsent: true,
          createdAt: daysAgo(115),
        ),
        member(
          id: kamlaMemberId,
          name: 'Kamla',
          phone: '+919876543219',
          role: 'member',
          designation: 'Advisor',
          dateOfBirth: dob(1952, 11, 3),
          gender: 'female',
          createdAt: daysAgo(114),
        ),
      ],
    );
  }
}
