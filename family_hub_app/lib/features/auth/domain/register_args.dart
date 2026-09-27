import 'package:flutter/foundation.dart';

import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/features/auth/domain/auth_rules.dart';
import 'package:family_hub/shared/data/auth_repository.dart' show RegisterMode;

export 'package:family_hub/features/auth/domain/auth_rules.dart';
export 'package:family_hub/shared/data/auth_repository.dart' show RegisterMode;

/// Arguments of `/register?mode=create|join&code=XXXX` (docs/05 §9).
///
/// Links from invitation emails may carry only `code`, so a code without a
/// mode means "join"; anything unknown falls back to "create".
@immutable
class RegisterArgs {
  const RegisterArgs({this.mode = RegisterMode.create, this.inviteCode = ''});

  factory RegisterArgs.fromQuery(Map<String, String> query) {
    final code = AuthInputs.sanitizeInviteCode(
      query[AppRoutes.codeQuery] ?? '',
    );
    final mode = switch (query[AppRoutes.modeQuery]?.trim().toLowerCase()) {
      AppRoutes.registerModeJoin => RegisterMode.join,
      AppRoutes.registerModeCreate => RegisterMode.create,
      _ => code.isEmpty ? RegisterMode.create : RegisterMode.join,
    };
    return RegisterArgs(mode: mode, inviteCode: code);
  }

  final RegisterMode mode;

  /// Sanitised invite code from the link ('' when none).
  final String inviteCode;

  /// The in-app location of these arguments.
  String get location => AppRoutes.register(
    mode: mode == RegisterMode.join
        ? AppRoutes.registerModeJoin
        : AppRoutes.registerModeCreate,
    code: inviteCode.isEmpty ? null : inviteCode,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RegisterArgs &&
          other.mode == mode &&
          other.inviteCode == inviteCode;

  @override
  int get hashCode => Object.hash(mode, inviteCode);

  @override
  String toString() => 'RegisterArgs(${mode.name}, $inviteCode)';
}
