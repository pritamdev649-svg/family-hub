/// Build information and static links shown by the settings screens.
///
/// There is no `package_info_plus` in this project, so the version comes
/// from `--dart-define`s (set them in CI together with `--build-name` /
/// `--build-number`):
///
/// ```sh
/// flutter build apk --build-name=1.2.0 --build-number=7 \
///   --dart-define=APP_VERSION=1.2.0 --dart-define=APP_BUILD_NUMBER=7
/// ```
///
/// The defaults mirror `version: 1.0.0+1` in `pubspec.yaml`.
abstract final class AppInfo {
  /// Marketing version (`x.y.z`).
  static const version = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '1.0.0',
  );

  /// Build number (may be empty).
  static const buildNumber = String.fromEnvironment(
    'APP_BUILD_NUMBER',
    defaultValue: '1',
  );

  /// Address for privacy / data-protection questions (grievance officer /
  /// DPO contact, docs/08-COMPLIANCE.md §3 row 30).
  static const privacyContactEmail = String.fromEnvironment(
    'PRIVACY_CONTACT_EMAIL',
    defaultValue: 'privacy@familyhub.app',
  );

  /// `1.0.0 (1)`, or just the version without a build number.
  static String get displayVersion => formatVersion(version, buildNumber);

  /// Formats a version / build pair for display (blank parts are dropped).
  static String formatVersion(String version, String buildNumber) {
    final v = version.trim();
    final b = buildNumber.trim();
    if (v.isEmpty) return b;
    return b.isEmpty ? v : '$v ($b)';
  }
}
