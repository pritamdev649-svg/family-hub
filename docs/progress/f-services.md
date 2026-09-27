# f-services: platform services (push, uploads, location) and native config

Owner: `f-services`. Scope: `family_hub_app/lib/core/services/**`, `lib/firebase_options.dart`,
`android/**`, `ios/**`, `l10n_parts/services.arb`, `config/dev.example.json`, `test/core/services/**`.

## Built

### Dart services (`lib/core/services/`)
- [x] `push_notification_service.dart`: `PushNotificationService` + `pushNotificationServiceProvider`
  - [x] `init()` is idempotent and never throws. It is a no-op while `Firebase.apps` is empty, and it does not cache that no-op, so it still works if Firebase starts later.
  - [x] `routeTaps` is a broadcast stream of routes that have passed `AppRoutes.sanitizeLocation`. Taps from FCM system notifications (`onMessageOpenedApp`), from local notifications, and the tap that cold-started the app (`getInitialMessage` / `getNotificationAppLaunchDetails`) all go here. If nobody is listening yet, the route is held until the first listener subscribes.
  - [x] Foreground messages: Android shows them with flutter_local_notifications 22 (named-param API) on channel `sos_alerts` (for `type == sos`) or `general`. iOS uses `setForegroundNotificationPresentationOptions`.
  - [x] Channel `sos_alerts`: max importance, alarm audio usage, a long vibration pattern and public lock-screen visibility. Channel `general`: high importance. Channel names come from `services*` ARB keys and are re-labelled when the language changes.
  - [x] The route comes from `data.route`. If that is missing or unsafe, it is built from `type` + `id` (`/sos/alert/:id`, `/tasks/:id`, `/notices`, `/money`, `/members/:id`).
  - [x] `registerDevice({locale})` asks for permission, turns FCM auto-init on, waits for the APNs token on iOS, then calls `POST /me/devices {token, platform, locale}` through `MeRepository`. Concurrent calls share one request, and every call is time-boxed and never throws. `onTokenRefresh` re-registers only while the user is signed in.
  - [x] Locale: the provider reads `resolvedLocaleProvider`, so pushes use the app language. When the language changes it re-labels the channels and re-registers the token.
  - [x] `unregisterDevice()` waits for any in-flight registration, calls `DELETE /me/devices/:token` (best effort, time-boxed), then turns auto-init off and deletes the local FCM token.
  - [x] `currentToken()` returns the token, for `POST /auth/logout {deviceToken}`.
  - [x] Pushes that arrive in the foreground or are tapped call `markChanged(...)` with the matching `DataScope`s, so lists refresh straight away (`scopesForType`).
  - [x] Notification ids are stable per resource (FNV hash), so "SOS resolved" replaces the SOS alert and task updates replace each other.
  - [x] Top-level `firebaseMessagingBackgroundHandler` (`@pragma('vm:entry-point')`). The OS displays notification messages itself; the handler shows data-only messages on Android as a defensive fallback.
- [x] `push_platform.dart`: testable seams `PushMessaging` (production: `FirebasePushMessaging`) and `LocalNotifier` (production: `AndroidLocalNotifier`), plus `PushChannelIds`, `PushTypes` and `PushChannelLabels`.
- [x] `cloudinary_service.dart`: `CloudinaryService.uploadImage(XFile, {folder, onProgress, cancelToken})` + `cloudinaryServiceProvider`, `enum UploadFolder { avatars, notices }`
  - [x] Uses its own `Dio` with no auth or locale interceptors, so the bearer token never reaches Cloudinary.
  - [x] Signed upload by default: calls `apiClient.post('/uploads/signature', body: {folder})`, then sends exactly the signed params (`api_key, timestamp, signature, folder, file`).
  - [x] Unsigned upload when `AppConfig.useUnsignedCloudinary`, with folder `familyhub/<folder>`.
  - [x] Mock mode with no Cloudinary config returns the local file path, with progress `0 → 1`.
  - [x] Progress callback: 0, then 0..0.99 from the send progress, then 1.0 once the URL is known.
  - [x] Size limit of 10 MB (`FILE_TOO_LARGE`). Only an absolute `https` `secure_url` is accepted. Path-less / web XFiles are uploaded from bytes.
  - [x] Every error is an `ApiException`: `UPLOAD_FAILED`, `FILE_TOO_LARGE`, `TOO_MANY_REQUESTS` (Cloudinary 420/429, keeps `Retry-After`), or `NETWORK_ERROR` / `TIMEOUT` / `CANCELLED` via `ApiException.fromDio`. A Cloudinary 401 deliberately maps to `UPLOAD_FAILED`, never `UNAUTHORIZED`, which would sign the user out.
- [x] `location_service.dart`: `LocationService` + `locationServiceProvider`, `LocationPermissionState`, `GeoFix` (`toJson()` matches the `{lat,lng,accuracy?}` API body; `toGeoPoint()`), `LocationUnavailableException`, `LocationPlatform` seam
  - [x] `ensurePermission({background})` checks service disabled, then denied, then prompts, and also handles deniedForever. Concurrent calls share one prompt; plugin errors map to `denied`. While-in-use permission is enough for background SOS tracking, so the app never asks for "Always" (privacy by default).
  - [x] `checkPermission()` checks without ever prompting.
  - [x] `currentFix({timeout})` never prompts and never throws. It waits for a fresh fix (default 12 s), then falls back to the last known position (flagged `isLastKnown`).
  - [x] `track(...)`: Android uses `AndroidSettings` + `ForegroundNotificationConfig` (ongoing notification, wake lock, `ic_stat_notification`). iOS uses `AppleSettings(allowBackgroundLocationUpdates: true, showBackgroundLocationIndicator: true, pauseLocationUpdatesAutomatically: false)`. `distanceFilter` is 5 m and the Android interval is `AppConfig.sosLocationInterval`. Missing permission emits one error and closes the stream. Errors during tracking (e.g. GPS switched off) are forwarded without closing the stream. Pause, resume and cancel are handled.
  - [x] `openSettings()` opens location settings when GPS is off, otherwise the app settings.
- [x] `services_l10n.dart`: `servicesL10n([Locale])` for code without a context (channels, background isolate), plus the `LocationPermissionState.message(l10n)` / `.actionLabel(l10n)` extension for SOS and settings screens.
- [x] `lib/firebase_options.dart`: stub `DefaultFirebaseOptions.currentPlatform` throws `UnsupportedError('Run flutterfire configure ...')`. **`flutterfire configure` overwrites this file**, which is expected.
- [x] `l10n_parts/services.arb` (prefix `services`): channel names and descriptions, live-location notification texts, location-permission messages and buttons, upload errors.

### Android (`android/`)
- [x] `app/build.gradle.kts`
  - [x] Core library desugaring (`isCoreLibraryDesugaringEnabled = true` + `desugar_jdk_libs:2.1.4`) and `multiDexEnabled`.
  - [x] `minSdk = maxOf(flutter.minSdkVersion, 24)`. flutter_local_notifications 22 needs 24.
  - [x] Optional release signing from `android/key.properties`, falling back to the debug key.
- [x] `AndroidManifest.xml`
  - [x] Label `FamilyHub`.
  - [x] Permissions: INTERNET, POST_NOTIFICATIONS, VIBRATE, ACCESS_FINE/COARSE_LOCATION, FOREGROUND_SERVICE, FOREGROUND_SERVICE_LOCATION, WAKE_LOCK. There is **no** CAMERA permission and **no** ACCESS_BACKGROUND_LOCATION.
  - [x] Location hardware features marked optional.
  - [x] FCM meta-data: default channel `general`, default icon and colour, `firebase_messaging_auto_init_enabled=false`.
  - [x] `<queries>` for tel (VIEW/DIAL), sms, mailto (VIEW/SENDTO), https, geo, Custom Tabs, plus PROCESS_TEXT.
  - [x] `localeConfig` covering all 15 languages.
- [x] `res/drawable/ic_stat_notification.xml` (monochrome status-bar icon), `res/values/colors.xml` (`notification_color`), `res/raw/keep.xml` (keeps resources that are looked up by name), `res/xml/locales_config.xml`.
- [x] `src/debug/AndroidManifest.xml`: `usesCleartextTraffic="true"` **debug builds only**, so the app can reach `http://10.0.2.2:3000/api/v1`.

### iOS (`ios/`)
- [x] `Runner/Info.plist`
  - [x] `CFBundleDisplayName` and `CFBundleName` set to `FamilyHub`.
  - [x] `CFBundleLocalizations` for the 15 languages.
  - [x] Usage strings for location (when-in-use + always), camera and photo library.
  - [x] `UIBackgroundModes`: fetch, location, remote-notification.
  - [x] `LSApplicationQueriesSchemes`: tel, sms, mailto, https, comgooglemaps.
  - [x] `FirebaseMessagingAutoInitEnabled=false`.
  - [x] ATS `NSAllowsLocalNetworking` (local dev API over http only; ATS stays on otherwise).
- [x] `Podfile`: `platform :ios, '15.0'` (Firebase iOS SDK 12), and pods below 15.0 are raised to it.
- [x] `Runner/AppDelegate.swift`: sets the `UNUserNotificationCenter` delegate and `FlutterLocalNotificationsPlugin.setPluginRegistrantCallback`, as the flutter_local_notifications README requires (classic, non-UIScene lifecycle).
- [x] `Runner/Runner.entitlements`: `aps-environment = development`. It is wired into `project.pbxproj` via `CODE_SIGN_ENTITLEMENTS` for Debug, Release and Profile, and has a file reference.
- [x] `IPHONEOS_DEPLOYMENT_TARGET = 15.0` in `project.pbxproj` and `Flutter/AppFrameworkInfo.plist`.

### Config
- [x] `config/dev.example.json`: comment-free JSON, see the README note below.

### Tests (`test/core/services/`): 62 tests
- [x] `location_service_test.dart`: GeoFix parsing and JSON, the permission flow (service off, prompt, deniedForever, single-flight, plugin errors), `currentFix` timeout and last-known fallback, `track` settings on Android and iOS, error forwarding, cancel before start, `openSettings`.
- [x] `cloudinary_service_test.dart`: exact signed fields and no Authorization header, unsigned preset, mock local path, size limit, incomplete signature, signature errors passed through, Cloudinary 401 is not UNAUTHORIZED, rate limit + Retry-After, non-https URL, transport error mapping, in-memory XFile.
- [x] `push_notification_service_test.dart`: every call is a no-op without Firebase, init on Android and iOS, foreground display and channel choice, tap and cold-start routes (with buffering), unsafe routes rejected, registration (platform, locale, explicit and unsupported locale), token refresh while signed in and signed out, API failures never throw, `updateLocale` re-registration, unregister, `routeFromData`, `channelFor`, notification ids, `scopesForType`.

## README note: `config/dev.example.json`

```bash
cd family_hub_app
cp config/dev.example.json config/dev.json      # keep dev.json out of git
flutter run --dart-define-from-file=config/dev.json
```

| Key | Meaning |
|---|---|
| `API_BASE_URL` | e.g. `http://10.0.2.2:3000/api/v1` (Android emulator → host) or `http://localhost:3000/api/v1` (iOS simulator). Empty = in-memory mock backend. Plain http works only in debug builds (Android) / for local-network hosts (iOS). |
| `USE_MOCK_API` | `true` forces the mock backend even when `API_BASE_URL` is set. |
| `CLOUDINARY_CLOUD_NAME` + `CLOUDINARY_UPLOAD_PRESET` | Both set = **unsigned** uploads straight to Cloudinary. Leave empty in production: uploads are then signed by the backend (`POST /uploads/signature`). In mock mode without them, picked images stay as local file paths. |
| `APP_ENV` | `dev` / `staging` / `prod` (informational, `AppConfig.environment`). |

Push notifications: run `dart pub global activate flutterfire_cli && flutterfire configure` in `family_hub_app/`. It replaces `lib/firebase_options.dart` and adds `google-services.json`, `GoogleService-Info.plist` and the google-services Gradle plugin. Without it the app runs without push.

For iOS push you also need a **paid** Apple team with the Push Notifications capability on the App ID, and an APNs key uploaded to Firebase.

## Pending / known issues
- [ ] `flutter build apk` / `flutter test` in the real tree fail for now. The cause is other agents' unfinished files (`lib/features/*/data/*_mock_handlers.dart`, `backgroundSyncProvider`, `SosStatusBanner`), which `core_providers.dart` → `mock_registry.dart` pulls into every import graph. My tests were run in a scratch copy with empty stubs for those handlers: 62/62 pass. Android Gradle config, manifest merge and resource linking were verified with `processDebugResources` / `processReleaseResources` (Dart compile skipped).
- [ ] Not run: `pod install` / `flutter build ios` (needs the complete Dart tree plus pod downloads). `AppDelegate.swift` passes `swiftc -parse`, all plists pass `plutil -lint`, and `xcodebuild -showBuildSettings` shows the entitlements and the 15.0 target.
- [ ] Free (personal) Apple teams cannot sign the `aps-environment` entitlement. If device builds must use one, remove `CODE_SIGN_ENTITLEMENTS` from the Runner target, which disables iOS push.
- [ ] The SOS channel does not bypass Do Not Disturb. That would need `ACCESS_NOTIFICATION_POLICY` plus a user grant; it is left out on purpose. It does use `AudioAttributesUsage.alarm`, so it sounds even in silent mode on most devices.
- [ ] The Android per-app language system setting (`localeConfig`) changes the device locale Flutter sees. It only takes effect while the in-app language is "system default".
- [ ] iOS: an alert's background location tracking relies on while-in-use permission and the blue indicator. If the OS kills the app, tracking stops. That is expected for SOS; the 15-minute window is enforced by the server.
