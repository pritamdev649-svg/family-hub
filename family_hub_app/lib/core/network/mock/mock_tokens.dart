import 'package:family_hub/core/network/mock/mock_backend.dart';

/// Token issuing for the mock backend, mirroring the server's
/// `services/tokens.js` (contract §2 "Tokens"):
///
/// * access token: `mock-access.<userId>` (never expires in the mock),
/// * refresh token: `mock-refresh.<userId>.<random>`, stored in the
///   `refreshTokens` collection, valid 30 days, **rotated** on every
///   refresh; reusing a revoked token revokes all of that user's tokens.
///
/// Use from the auth / me / family mock handlers:
/// ```dart
/// return MockResponse.ok({'user': ..., 'tokens': MockTokens.issue(db, uid)});
/// ```
abstract final class MockTokens {
  static const expiresIn = 900;
  static const refreshValidity = Duration(days: 30);

  /// Issues a new token pair for [userId] (contract `Tokens` JSON).
  static Map<String, dynamic> issue(MockDb db, String userId) {
    final refresh = MockRequest.refreshTokenFor(db, userId);
    db.insert(MockDb.refreshTokens, {
      'userId': userId,
      'token': refresh,
      'expiresAt': MockDb.iso(DateTime.now().add(refreshValidity)),
      'revokedAt': null,
    });
    return {
      'accessToken': MockRequest.accessTokenFor(userId),
      'refreshToken': refresh,
      'expiresIn': expiresIn,
    };
  }

  /// Validates and rotates [refreshToken]; returns the new pair.
  /// Throws `401 INVALID_REFRESH_TOKEN` when unknown, expired, revoked
  /// (reuse → revokes every token of the user) or the user is gone.
  static Map<String, dynamic> rotate(MockDb db, Object? refreshToken) {
    const invalid = MockException.unauthorized(
      'INVALID_REFRESH_TOKEN',
      'Invalid refresh token',
    );
    if (refreshToken is! String || refreshToken.isEmpty) throw invalid;
    final doc = db.findOne(
      MockDb.refreshTokens,
      (t) => t['token'] == refreshToken,
    );
    if (doc == null) throw invalid;
    final userId = doc['userId'] as String;
    if (doc['revokedAt'] != null) {
      revokeAll(db, userId);
      throw invalid;
    }
    final expiresAt = MockDb.parse(doc['expiresAt']);
    if (expiresAt == null || expiresAt.isBefore(DateTime.now())) throw invalid;
    if (db.findById(MockDb.users, userId) == null) throw invalid;
    db.update(MockDb.refreshTokens, doc['id'] as String, {
      'revokedAt': db.nowIso(),
    });
    return issue(db, userId);
  }

  /// Revokes one refresh token (logout). Unknown tokens are ignored.
  static void revoke(MockDb db, Object? refreshToken) {
    if (refreshToken is! String) return;
    db.updateWhere(
      MockDb.refreshTokens,
      (t) => t['token'] == refreshToken && t['revokedAt'] == null,
      {'revokedAt': db.nowIso()},
    );
  }

  /// Revokes every refresh token of [userId] (password reset, removal from
  /// family, account deletion, token reuse).
  static void revokeAll(MockDb db, String userId) {
    db.updateWhere(
      MockDb.refreshTokens,
      (t) => t['userId'] == userId && t['revokedAt'] == null,
      {'revokedAt': db.nowIso()},
    );
  }
}
