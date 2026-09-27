import 'package:flutter/foundation.dart';

import 'package:family_hub/core/network/api_client.dart';
import 'package:family_hub/core/storage/token_storage.dart';
import 'package:family_hub/shared/data/family_repository.dart'
    show CreateFamilyRequest;
import 'package:family_hub/shared/data/repository_utils.dart';
import 'package:family_hub/shared/json.dart';
import 'package:family_hub/shared/models/auth_user.dart';
import 'package:family_hub/shared/models/family.dart';
import 'package:family_hub/shared/models/member.dart';
import 'package:family_hub/shared/models/session_state.dart';

/// `mode` of `POST /auth/register`.
enum RegisterMode { create, join }

/// Body of `POST /auth/register` (docs/03-API_CONTRACT.md §4).
///
/// Use [RegisterRequest.create] to start a new family (the user becomes its
/// admin) or [RegisterRequest.join] to join with an invite code.
@immutable
class RegisterRequest {
  const RegisterRequest.create({
    required this.name,
    required this.email,
    required this.password,
    required this.locale,
    required this.consentAccepted,
    required CreateFamilyRequest this.family,
    this.dateOfBirth,
  }) : mode = RegisterMode.create,
       inviteCode = null;

  const RegisterRequest.join({
    required this.name,
    required this.email,
    required this.password,
    required this.locale,
    required this.consentAccepted,
    required String this.inviteCode,
    this.dateOfBirth,
  }) : mode = RegisterMode.join,
       family = null;

  final String name;
  final String email;
  final String password;

  /// UI language code (`hi`, `ta` …) — the server uses it for emails/pushes.
  final String locale;

  /// Privacy policy + terms accepted (must be `true`, else VALIDATION_ERROR).
  final bool consentAccepted;
  final DateTime? dateOfBirth;
  final RegisterMode mode;
  final CreateFamilyRequest? family;
  final String? inviteCode;

  /// Contract-exact body. Name / email are normalised; the password is sent
  /// verbatim. Absent optional values are sent as `null` (as in the contract
  /// example).
  Map<String, dynamic> toJson() => {
    'name': name.trim(),
    'email': normalizeEmail(email) ?? '',
    'password': password,
    'locale': locale,
    'consentAccepted': consentAccepted,
    'dateOfBirth': isoOrNull(dateOfBirth),
    'mode': mode.name,
    'family': mode == RegisterMode.create ? family?.toJson() : null,
    'inviteCode': mode == RegisterMode.join && inviteCode != null
        ? normalizeInviteCode(inviteCode!)
        : null,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RegisterRequest &&
          other.name == name &&
          other.email == email &&
          other.password == password &&
          other.locale == locale &&
          other.consentAccepted == consentAccepted &&
          other.dateOfBirth == dateOfBirth &&
          other.mode == mode &&
          other.family == family &&
          other.inviteCode == inviteCode;

  @override
  int get hashCode => Object.hash(
    name,
    email,
    password,
    locale,
    consentAccepted,
    dateOfBirth,
    mode,
    family,
    inviteCode,
  );

  /// Never prints the password.
  @override
  String toString() => 'RegisterRequest(${mode.name}, $email)';
}

/// Result of register / login: the account, the stored tokens and — when
/// the endpoint returns them (register) — the member and family.
@immutable
class AuthResult {
  const AuthResult({
    required this.user,
    required this.tokens,
    this.member,
    this.family,
  });

  final AuthUser user;
  final AuthTokens tokens;
  final Member? member;
  final Family? family;

  /// Whether [member] and [family] came with the response (register), so no
  /// extra `GET /auth/me` is needed.
  bool get hasMembership => member != null && family != null;

  SessionState get session =>
      SessionState(user: user, member: member, family: family);
}

/// `/auth/*` endpoints. Successful register / login store the tokens through
/// [TokenStorage]; [logout] always clears them.
class AuthRepository {
  AuthRepository(this._api, this._tokens);

  final ApiClient _api;
  final TokenStorage _tokens;

  /// `POST /auth/register` → `{ user, tokens, family, member }`.
  /// Errors: `EMAIL_TAKEN`, `INVALID_INVITE_CODE`, `VALIDATION_ERROR`.
  Future<AuthResult> register(RegisterRequest request) async {
    final data = await _api.post('/auth/register', body: request.toJson());
    return _signedIn(data);
  }

  /// `POST /auth/login` → `{ user, tokens }` (member / family are loaded
  /// with [me]). Errors: `INVALID_CREDENTIALS`, `TOO_MANY_REQUESTS`.
  Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    final data = await _api.post(
      '/auth/login',
      body: {'email': normalizeEmail(email) ?? '', 'password': password},
    );
    return _signedIn(data);
  }

  /// `POST /auth/logout` (best effort, time-boxed by [timeout]: network /
  /// server errors are ignored) and then **always** clears the stored tokens.
  /// Unregister the push device *before* calling this (it needs the tokens).
  Future<void> logout({
    String? deviceToken,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    try {
      final refreshToken = await _tokens.refreshToken;
      if (refreshToken != null && refreshToken.isNotEmpty) {
        await _api
            .post(
              '/auth/logout',
              body: {
                'refreshToken': refreshToken,
                if (deviceToken != null && deviceToken.isNotEmpty)
                  'deviceToken': deviceToken,
              },
            )
            .timeout(timeout);
      }
    } on Exception catch (e) {
      debugPrint('AuthRepository.logout: server logout skipped ($e)');
    } finally {
      await _tokens.clear();
    }
  }

  /// `POST /auth/verify-email` → `{ user }` (now `emailVerified: true`).
  /// Errors: `INVALID_OTP`, `OTP_EXPIRED`.
  Future<AuthUser> verifyEmail(String otp) async {
    final data = await _api.post(
      '/auth/verify-email',
      body: {'otp': normalizeOtp(otp)},
    );
    return AuthUser.fromJson(requireObject(data, 'user'));
  }

  /// `POST /auth/resend-verification` → seconds until the next resend is
  /// allowed (defaults to 60). Errors: `TOO_MANY_REQUESTS`
  /// (`retryAfterSeconds` in details).
  Future<int> resendVerification() async {
    final data = await _api.post('/auth/resend-verification');
    final seconds = asInt(asMap(data)['retryAfterSeconds'], 60);
    return seconds < 0 ? 0 : seconds;
  }

  /// `POST /auth/forgot-password` — always succeeds for well-formed emails
  /// (the server never reveals whether the account exists).
  Future<void> forgotPassword(String email) async {
    await _api.post(
      '/auth/forgot-password',
      body: {'email': normalizeEmail(email) ?? ''},
    );
  }

  /// `POST /auth/reset-password`. Revokes all sessions of the account on the
  /// server. Errors: `INVALID_OTP`, `OTP_EXPIRED`, `VALIDATION_ERROR`.
  Future<void> resetPassword({
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    await _api.post(
      '/auth/reset-password',
      body: {
        'email': normalizeEmail(email) ?? '',
        'otp': normalizeOtp(otp),
        'newPassword': newPassword,
      },
    );
  }

  /// `POST /auth/change-password`. Errors: `INVALID_CREDENTIALS` (wrong
  /// current password), `VALIDATION_ERROR`.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _api.post(
      '/auth/change-password',
      body: {'currentPassword': currentPassword, 'newPassword': newPassword},
    );
  }

  /// `GET /auth/me` → `{ user, member|null, family|null }`.
  Future<SessionState> me() async {
    return _session(await _api.get('/auth/me'));
  }

  /// Whether tokens are stored (i.e. a session can be restored).
  Future<bool> hasTokens() => _tokens.hasTokens;

  /// Drops the stored tokens without contacting the server.
  Future<void> clearTokens() => _tokens.clear();

  Future<AuthResult> _signedIn(Object? data) async {
    final tokens = AuthTokens.tryParse(asMap(data)['tokens']);
    if (tokens == null) _malformed('missing tokens');
    final session = _session(data);
    await _tokens.save(tokens);
    return AuthResult(
      user: session.user ?? _malformed('missing user'),
      tokens: tokens,
      member: session.member,
      family: session.family,
    );
  }

  /// `{ user, member?, family? }` → [SessionState]; a missing / id-less user
  /// is a malformed response.
  SessionState _session(Object? data) {
    final session = SessionState.fromJson(requireObject(data));
    if (!session.isSignedIn) _malformed('missing user');
    return session;
  }

  static Never _malformed(String what) =>
      throw ApiException.unknown('Malformed response: $what');
}
