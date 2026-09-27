/// Whether this phone lets FamilyHub show notifications (SOS alerts!).
enum NotificationStatus {
  /// Allowed (authorized or provisional).
  enabled,

  /// Blocked in the system settings.
  disabled,

  /// Not asked yet (the prompt appears after sign-in).
  notDetermined,

  /// Push is not configured in this build (no Firebase) or not supported on
  /// this platform.
  unavailable;

  /// Whether the user can change it in the phone's settings.
  bool get canOpenSettings => this != unavailable;
}
