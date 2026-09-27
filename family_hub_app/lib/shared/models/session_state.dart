import 'package:flutter/foundation.dart';

import 'package:family_hub/shared/json.dart';
import 'package:family_hub/shared/models/auth_user.dart';
import 'package:family_hub/shared/models/family.dart';
import 'package:family_hub/shared/models/member.dart';

/// Snapshot of who is signed in and which family / member they belong to.
///
/// Also the shape of `GET /auth/me`, `POST /family`, `POST /family/join`
/// (`{ user, member, family }`) and of the offline cache (`session.last`).
@immutable
class SessionState {
  const SessionState({this.user, this.member, this.family});

  /// Parses `{ user, member, family }`. A missing / invalid `user` yields
  /// [signedOut]; member and family are dropped unless both are present, so
  /// a half-populated session never reaches the UI.
  factory SessionState.fromJson(Map<String, dynamic> json) {
    final userJson = json['user'];
    if (userJson is! Map) return signedOut;
    final user = AuthUser.fromJson(asMap(userJson));
    if (user.id.isEmpty) return signedOut;
    final memberJson = json['member'];
    final familyJson = json['family'];
    if (memberJson is! Map || familyJson is! Map) {
      return SessionState(user: user);
    }
    final member = Member.fromJson(asMap(memberJson));
    final family = Family.fromJson(asMap(familyJson));
    if (member.id.isEmpty || family.id.isEmpty) return SessionState(user: user);
    return SessionState(user: user, member: member, family: family);
  }

  static const signedOut = SessionState();

  final AuthUser? user;
  final Member? member;
  final Family? family;

  bool get isSignedIn => user != null;

  /// Signed in but the email OTP has not been confirmed yet.
  bool get needsEmailVerification => user != null && !user!.emailVerified;

  /// Signed in (and verified) but not part of a family → create / join.
  bool get needsFamily =>
      user != null && user!.emailVerified && (member == null || family == null);

  /// Signed in, verified and in a family — the app shell may be shown.
  bool get isComplete =>
      user != null && !needsEmailVerification && !needsFamily;

  bool get isAdmin => member?.isAdmin ?? user?.isAdmin ?? false;

  Map<String, dynamic> toJson() => {
    'user': user?.toJson(),
    'member': member?.toJson(),
    'family': family?.toJson(),
  };

  /// Nullable fields take a [ValueGetter] so they can be cleared:
  /// `state.copyWith(member: () => null, family: () => null)`.
  SessionState copyWith({
    ValueGetter<AuthUser?>? user,
    ValueGetter<Member?>? member,
    ValueGetter<Family?>? family,
  }) {
    return SessionState(
      user: user != null ? user() : this.user,
      member: member != null ? member() : this.member,
      family: family != null ? family() : this.family,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionState &&
          other.user == user &&
          other.member == member &&
          other.family == family;

  @override
  int get hashCode => Object.hash(user, member, family);

  @override
  String toString() =>
      'SessionState(user: ${user?.id}, member: ${member?.id}, '
      'family: ${family?.id})';
}
