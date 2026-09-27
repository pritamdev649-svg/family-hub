/// Text limits of family / member fields — the same as the backend's zod
/// schemas (docs/04-DATA_MODELS.md), shared by the forms and the mock.
abstract final class FamilyLimits {
  /// Family name and member name: 1–60 characters.
  static const name = 60;

  /// Member designation ("company title"): up to 80 characters.
  static const designation = 80;

  /// Stored avatar URL.
  static const avatarUrl = 1024;
}
