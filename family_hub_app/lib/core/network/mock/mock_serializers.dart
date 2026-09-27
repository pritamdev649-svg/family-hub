import 'package:family_hub/core/network/mock/mock_db.dart';

/// Shared JSON shapes of the mock backend — the mock equivalent of the
/// backend's `services/serializers.js` + `memberDirectory.js`. Use these in
/// feature mock handlers instead of hand-building User / Family / Member
/// objects so every endpoint returns identical shapes and applies the same
/// privacy rules.
abstract final class MockSerializers {
  /// Contract `User`: strips the password and internal fields, adds the
  /// caller's `role` from their member document.
  static Map<String, dynamic> user(MockDb db, Map<String, dynamic> user) {
    final member = db.findById(MockDb.members, user['memberId']);
    return {
      'id': user['id'],
      'email': user['email'],
      'name': user['name'],
      'emailVerified': user['emailVerified'] == true,
      'locale': user['locale'] ?? 'en',
      'familyId': user['familyId'],
      'memberId': user['memberId'],
      'role': member?['role'],
      'createdAt': user['createdAt'],
    };
  }

  /// Contract `Family`: `inviteCode` only for admins, computed
  /// `memberCount`.
  static Map<String, dynamic> family(
    MockDb db,
    Map<String, dynamic> family, {
    required bool isAdmin,
  }) => {
    'id': family['id'],
    'name': family['name'],
    'inviteCode': isAdmin ? family['inviteCode'] : null,
    'country': family['country'],
    'currency': family['currency'],
    'timezone': family['timezone'],
    'ownerId': family['ownerId'],
    'memberCount': db.count(
      MockDb.members,
      (m) => m['familyId'] == family['id'],
    ),
    'createdAt': family['createdAt'],
  };

  /// Contract `Member`: `hasAccount` derived from `userId`; `lastLocation`
  /// only when the member shares `always` (privacy rule).
  static Map<String, dynamic> member(Map<String, dynamic> m) => {
    'id': m['id'],
    'familyId': m['familyId'],
    'userId': m['userId'],
    'name': m['name'],
    'email': m['email'],
    'phone': m['phone'],
    'avatarUrl': m['avatarUrl'],
    'dateOfBirth': m['dateOfBirth'],
    'gender': m['gender'],
    'designation': m['designation'],
    'role': m['role'] ?? 'member',
    'hasAccount': m['userId'] != null,
    'locationSharing': m['locationSharing'] ?? 'never',
    'lastLocation': m['locationSharing'] == 'always' ? m['lastLocation'] : null,
    'guardianConsent': m['guardianConsent'] == true,
    'createdAt': m['createdAt'],
    'updatedAt': m['updatedAt'],
  };

  /// Members of [familyId] serialized and sorted like `GET /family/members`:
  /// admins first, then oldest → youngest, members without DOB last.
  static List<Map<String, dynamic>> members(MockDb db, String familyId) {
    final list = db.where(MockDb.members, (m) => m['familyId'] == familyId)
      ..sort(compareMembers);
    return [for (final m in list) member(m)];
  }

  /// Sort order of the members list (see [members]).
  static int compareMembers(Map<String, dynamic> a, Map<String, dynamic> b) {
    final ra = a['role'] == 'admin' ? 0 : 1;
    final rb = b['role'] == 'admin' ? 0 : 1;
    if (ra != rb) return ra - rb;
    final da = MockDb.parse(a['dateOfBirth']);
    final dbb = MockDb.parse(b['dateOfBirth']);
    if (da == null && dbb == null) return 0;
    if (da == null) return 1;
    if (dbb == null) return -1;
    return da.compareTo(dbb);
  }

  /// Member display name for denormalized fields (`assigneeName`,
  /// `createdByName`, `authorName`, `memberName`). Empty when unknown.
  static String memberName(MockDb db, Object? memberId) =>
      '${db.findById(MockDb.members, memberId)?['name'] ?? ''}';

  /// `{ user, member, family }` as returned by `/auth/me`,
  /// `POST /family`, `/family/join` (member/family null when absent).
  static Map<String, dynamic> session(MockDb db, Map<String, dynamic> u) {
    final m = db.findById(MockDb.members, u['memberId']);
    final f = db.findById(MockDb.families, u['familyId']);
    return {
      'user': user(db, u),
      'member': m == null ? null : member(m),
      'family': f == null
          ? null
          : family(db, f, isAdmin: m != null && m['role'] == 'admin'),
    };
  }
}
