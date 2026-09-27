import 'package:flutter/foundation.dart';

/// Access + refresh token pair (`Tokens` in the API contract §2).
///
/// This is the single `AuthTokens` model of the app; `lib/shared/models`
/// re-exports / uses it instead of declaring its own.
@immutable
class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    this.expiresIn,
  });

  /// Parses `{ accessToken, refreshToken, expiresIn }`. Returns null when
  /// either token is missing/empty so callers never store a half session.
  static AuthTokens? tryParse(Object? json) {
    if (json is! Map) return null;
    final access = json['accessToken'];
    final refresh = json['refreshToken'];
    if (access is! String || access.isEmpty) return null;
    if (refresh is! String || refresh.isEmpty) return null;
    final exp = json['expiresIn'];
    return AuthTokens(
      accessToken: access,
      refreshToken: refresh,
      expiresIn: exp is num ? exp.toInt() : int.tryParse('${exp ?? ''}'),
    );
  }

  /// Like [tryParse] but throws [FormatException] on invalid input.
  factory AuthTokens.fromJson(Map<String, dynamic> json) {
    final tokens = tryParse(json);
    if (tokens == null) {
      throw const FormatException('Invalid tokens payload');
    }
    return tokens;
  }

  /// Short-lived JWT sent as `Authorization: Bearer …`.
  final String accessToken;

  /// Opaque, rotated on every `/auth/refresh`.
  final String refreshToken;

  /// Access-token lifetime in seconds as reported by the server.
  final int? expiresIn;

  Map<String, dynamic> toJson() => {
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    if (expiresIn != null) 'expiresIn': expiresIn,
  };

  AuthTokens copyWith({
    String? accessToken,
    String? refreshToken,
    int? expiresIn,
  }) => AuthTokens(
    accessToken: accessToken ?? this.accessToken,
    refreshToken: refreshToken ?? this.refreshToken,
    expiresIn: expiresIn ?? this.expiresIn,
  );

  @override
  bool operator ==(Object other) =>
      other is AuthTokens &&
      other.accessToken == accessToken &&
      other.refreshToken == refreshToken &&
      other.expiresIn == expiresIn;

  @override
  int get hashCode => Object.hash(accessToken, refreshToken, expiresIn);

  /// Never prints the secrets.
  @override
  String toString() => 'AuthTokens(expiresIn: $expiresIn)';
}
