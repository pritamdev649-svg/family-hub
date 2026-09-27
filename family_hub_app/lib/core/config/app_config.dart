/// Build-time configuration, passed with `--dart-define` or
/// `--dart-define-from-file=config/dev.json` (see config/dev.example.json).
class AppConfig {
  AppConfig._();

  /// Base URL of the Node/MongoDB REST API, e.g. `https://api.familyhub.app/api/v1`.
  /// When empty the app runs against the in-memory mock backend.
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// Force the mock backend even when [apiBaseUrl] is set.
  static const _forceMock = bool.fromEnvironment('USE_MOCK_API');

  static bool get useMockApi => _forceMock || apiBaseUrl.isEmpty;

  /// Cloudinary cloud name. Only needed for unsigned uploads; for signed
  /// uploads the backend returns it together with the signature.
  static const cloudinaryCloudName = String.fromEnvironment(
    'CLOUDINARY_CLOUD_NAME',
  );

  /// Optional unsigned upload preset. Leave empty to use signed uploads via
  /// `POST /uploads/signature` (recommended for production).
  static const cloudinaryUploadPreset = String.fromEnvironment(
    'CLOUDINARY_UPLOAD_PRESET',
  );

  static bool get useUnsignedCloudinary =>
      cloudinaryCloudName.isNotEmpty && cloudinaryUploadPreset.isNotEmpty;

  static const environment = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'dev',
  );

  static const privacyPolicyUrl = String.fromEnvironment(
    'PRIVACY_POLICY_URL',
    defaultValue: 'https://familyhub.app/privacy',
  );
  static const termsUrl = String.fromEnvironment(
    'TERMS_URL',
    defaultValue: 'https://familyhub.app/terms',
  );

  static const connectTimeout = Duration(seconds: 15);
  static const receiveTimeout = Duration(seconds: 20);

  /// How long an SOS keeps streaming live location.
  static const sosTrackingWindow = Duration(minutes: 15);

  /// Minimum gap between two SOS location uploads (saves data & battery).
  static const sosLocationInterval = Duration(seconds: 5);

  /// Countdown before an SOS is sent, so an accidental tap can be cancelled.
  static const sosCountdownSeconds = 3;
}
