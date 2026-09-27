import 'package:family_hub/core/l10n/error_messages.dart'
    show unwrapProviderError;
import 'package:family_hub/core/network/api_exception.dart';

/// What a failed task request means for the screens (contract §1 / §7):
///
/// * [gone] — `404 NOT_FOUND` (deleted by someone else, its assignee was
///   removed, another family's task) or `400 BAD_REQUEST` (malformed id in a
///   link). The task no longer exists for the caller.
/// * [notAllowed] — `403 FORBIDDEN`: the caller's role changed since the
///   screen was built (e.g. an admin was demoted).
/// * [noFamily] — `403 NO_FAMILY`: the caller was removed from the family.
/// * [assigneeUnavailable] — `422 VALIDATION_ERROR` with
///   `details.assigneeId`: the chosen (or current) assignee is no longer a
///   member of the family.
/// * [other] — anything else (offline, timeout, server error, …).
enum TaskFailure {
  gone,
  notAllowed,
  noFamily,
  assigneeUnavailable,
  other;

  /// The session (role / membership) is out of date.
  bool get isAccessChange => this == notAllowed || this == noFamily;

  /// Classifies anything a task repository / provider can throw
  /// (Riverpod `ProviderException` wrappers are unwrapped first).
  static TaskFailure of(Object error) {
    final e = unwrapProviderError(error);
    if (e is! ApiException) return other;
    return switch (e.code) {
      ApiErrorCode.notFound || ApiErrorCode.badRequest => gone,
      ApiErrorCode.forbidden => notAllowed,
      ApiErrorCode.noFamily => noFamily,
      ApiErrorCode.validation
          when e.details?.containsKey('assigneeId') ?? false =>
        assigneeUnavailable,
      _ => other,
    };
  }
}
