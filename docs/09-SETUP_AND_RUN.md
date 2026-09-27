# 09 · Setup & Run

> From zero to a running app: mock mode (no server), local backend, a real device, and the optional cloud services
> (Firebase push, Cloudinary images, SMTP email). Architecture background: [`02-ARCHITECTURE.md`](02-ARCHITECTURE.md).

## 1. Prerequisites

| Tool | Version | Needed for | Check |
|---|---|---|---|
| Flutter SDK | 3.38.x (Dart 3.10) | App | `flutter --version`, `flutter doctor` |
| Android Studio + Android SDK, an emulator image | recent; JDK 17 (bundled with Android Studio) | Android | `flutter doctor` |
| Xcode + CocoaPods (macOS only) | Xcode 16+; iOS deployment target 13.0 | iOS | `xcodebuild -version`, `pod --version` |
| Node.js | ≥ 20.11 (developed on 25) | Backend | `node --version` |
| MongoDB | 7 or 8, **optional** (see `dev:memory`) | Backend | `mongosh --version` |
| Firebase CLI + FlutterFire CLI | latest, optional | Push notifications | `firebase --version`, `flutterfire --version` |
| A Cloudinary account | free tier, optional | Image uploads | — |
| An SMTP account | optional | Real emails (otherwise printed to the console) | — |

Everything marked optional can be skipped: the app has a full **mock mode**, the backend can run on an **in-memory
MongoDB**, emails are printed to the console, and push/uploads degrade gracefully.

## 2. Run the app in mock mode (no backend)

```bash
cd family_hub_app
flutter pub get
flutter run --dart-define-from-file=config/dev.json
```

- `config/dev.json` holds the build-time settings (`--dart-define`s). If it does not exist yet, copy
  `config/dev.example.json` to `config/dev.json`. With `API_BASE_URL` empty, the app uses the **in-memory mock
  backend**. `flutter run` without any define also runs in mock mode.
- Mock data is seeded on every start and **reset when the app restarts**.

**Demo accounts (mock mode)**

| Email | Password | Who |
|---|---|---|
| `demo@familyhub.app` | `demo1234` | Amit, admin, "Head of Family" (email verified) |
| `priya@familyhub.app` | `demo1234` | Priya, admin, "Finance Head" |

- Demo family: **Sharma Family** (India, INR, Asia/Kolkata), invite code **`DEMO2345`**. Members: Amit, Priya,
  Aarav (teen), Anaya (child, managed profile), Kamla (grandmother, managed profile).
- Every OTP (email verification, password reset) is **`123456`** in mock mode.
- Register a new family, or join the demo family with `DEMO2345`, to test onboarding.

### Build-time settings (`config/*.json`)

| Key | Example | Meaning |
|---|---|---|
| `API_BASE_URL` | `http://10.0.2.2:4000/api/v1` | Backend URL including `/api/v1`. Empty → mock mode. |
| `USE_MOCK_API` | `false` | `true` forces mock mode even when `API_BASE_URL` is set. |
| `APP_ENV` | `dev` | Free-form environment label (`dev`, `staging`, `prod`). |
| `CLOUDINARY_CLOUD_NAME` | `demo` | Only for **unsigned** uploads (dev shortcut, §7). |
| `CLOUDINARY_UPLOAD_PRESET` | `familyhub_unsigned` | Only for unsigned uploads. Leave empty for signed uploads (recommended). |
| `PRIVACY_POLICY_URL` | `https://familyhub.app/privacy` | Link shown at signup and in Settings → About. |
| `TERMS_URL` | `https://familyhub.app/terms` | Link shown at signup and in Settings → About. |

Keep one file per environment (`config/dev.json`, `config/staging.json`, `config/prod.json`) and never put secrets in
them: everything in a dart-define is readable from the built app.

## 3. Run the backend

```bash
cd family_hub_backend
npm install
cp .env.example .env        # defaults work for local development
```

### Option A: no MongoDB installed (in-memory database)

```bash
npm run dev:memory
# if the script alias is missing in your checkout: node scripts/dev-memory.js
```

- Starts an in-memory MongoDB (the first run downloads a MongoDB binary, roughly 100 MB, into a cache), runs
  `scripts/seed.js` if it exists, then starts the API. Data lives only as long as the process.
- `DEV_MEMORY_DB_PORT=27018 npm run dev:memory` pins the database port so you can connect MongoDB Compass or `mongosh`.

### Option B: local MongoDB

Install and start MongoDB with one of:

```bash
# macOS (Homebrew)
brew tap mongodb/brew && brew install mongodb-community
brew services start mongodb-community

# Docker (any OS)
docker run -d --name familyhub-mongo -p 27017:27017 mongo:8
```

Or use a free MongoDB Atlas cluster and put its connection string in `MONGODB_URI`. Then:

```bash
npm run seed    # demo family + demo accounts (see the header of scripts/seed.js for re-run behaviour)
npm run dev     # API with auto-restart on file changes (node --watch)
```

### Check it works

```bash
curl http://localhost:4000/api/v1/health
# {"success":true,"data":{"status":"ok","db":"up","version":"1.0.0"}}
```

### Backend environment variables (`.env`)

| Variable | Default | Notes |
|---|---|---|
| `NODE_ENV` | `development` | `production` makes `JWT_ACCESS_SECRET` (≥ 32 chars) and `FIELD_ENCRYPTION_KEY` mandatory. |
| `PORT` | `4000` | |
| `CORS_ORIGINS` | `*` | Comma-separated list in production. |
| `APP_NAME` | `FamilyHub` | Used in emails. |
| `MONGODB_URI` | `mongodb://127.0.0.1:27017/familyhub` | |
| `JWT_ACCESS_SECRET` | dev-only fallback outside production | Generate: `node -e "console.log(require('crypto').randomBytes(48).toString('base64url'))"` |
| `ACCESS_TOKEN_TTL_SECONDS` | `900` | 15 minutes. |
| `REFRESH_TOKEN_TTL_DAYS` | `30` | |
| `FIELD_ENCRYPTION_KEY` | empty (dev key derived from the JWT secret) | 32 bytes, base64: `node -e "console.log(require('crypto').randomBytes(32).toString('base64'))"`. **Never change it after data exists** without a re-encryption script (see [`08-COMPLIANCE.md` §8](08-COMPLIANCE.md)). |
| `SMTP_HOST`, `SMTP_PORT`, `SMTP_SECURE`, `SMTP_USER`, `SMTP_PASS`, `MAIL_FROM` | empty → emails printed to console | §8 |
| `FIREBASE_SERVICE_ACCOUNT_PATH` / `FIREBASE_SERVICE_ACCOUNT_BASE64` | empty → push disabled | §6 |
| `CLOUDINARY_CLOUD_NAME`, `CLOUDINARY_API_KEY`, `CLOUDINARY_API_SECRET` | empty → upload signing disabled | §7 |

**Demo accounts on the real backend:** after `npm run seed` (or `npm run dev:memory`, which seeds automatically) the
demo family and logins from §2 are expected to exist too. OTPs on the real backend are **random**: without SMTP they
are printed in the API console output together with the rest of the email.

### Backend quality checks

```bash
npm test         # node:test + supertest on an in-memory MongoDB
npm run check    # syntax check of every source file
```

## 4. Connect the app to your backend

Create (or edit) `family_hub_app/config/dev.json` and set `API_BASE_URL`:

| Where the app runs | `API_BASE_URL` |
|---|---|
| Android emulator | `http://10.0.2.2:4000/api/v1` (10.0.2.2 is the host machine) |
| iOS simulator | `http://localhost:4000/api/v1` |
| Physical device on the same Wi-Fi | `http://<your computer's LAN IP>:4000/api/v1`. macOS: `ipconfig getifaddr en0`. Windows: `ipconfig`. Linux: `hostname -I`. |
| Physical Android device over USB | Run `adb reverse tcp:4000 tcp:4000`, then use `http://localhost:4000/api/v1`. |
| Deployed backend | `https://api.your-domain.com/api/v1` (always HTTPS in production) |

Then run `flutter run --dart-define-from-file=config/dev.json` again (dart-defines need a **full restart**, not a hot
reload). Log in with the demo account, or register (the OTP appears in the backend console when SMTP is not set).

## 5. Quality checks for the app

```bash
cd family_hub_app
dart run tool/l10n.dart   # after editing any l10n_parts/*.arb (merge + flutter gen-l10n)
flutter analyze           # must report no issues
flutter test
```

## 6. Firebase (push notifications)

Without Firebase, everything works except push. Set it up once per Firebase project (e.g. one for dev, one for prod).

1. **Create a project** at <https://console.firebase.google.com> → *Add project* (Google Analytics is not needed).
2. **Install the CLIs**
   ```bash
   npm install -g firebase-tools
   firebase login
   dart pub global activate flutterfire_cli     # make sure ~/.pub-cache/bin is on your PATH
   ```
3. **Connect the app** (from `family_hub_app/`):
   ```bash
   flutterfire configure --project=<your-project-id> --platforms=android,ios \
     --android-package-name=com.familyhub.family_hub --ios-bundle-id=com.familyhub.familyHub
   ```
   This registers both apps and writes `lib/firebase_options.dart` (replacing the stub),
   `android/app/google-services.json` and `ios/Runner/GoogleService-Info.plist`, and adds the Google Services Gradle
   plugin. Re-run it whenever you change the bundle id or package name.
4. **iOS: APNs key** (push to iPhones goes through Apple):
   1. Apple Developer account → *Certificates, Identifiers & Profiles* → *Keys* → **+** → enable
      *Apple Push Notifications service (APNs)* → download the `.p8` file (only downloadable once) and note the Key ID
      and your Team ID.
   2. Firebase console → *Project settings* → *Cloud Messaging* → *Apple app configuration* → upload the `.p8`
      with Key ID and Team ID.
   3. Xcode → open `ios/Runner.xcworkspace` → target *Runner* → *Signing & Capabilities*: set your team, add
      **Push Notifications** and **Background Modes** (tick *Remote notifications*, and *Location updates* for SOS
      live tracking).
   4. Test on a **real iPhone**; simulator support for remote push is limited.
5. **Android**: nothing extra. Android 13+ asks for the notification permission at runtime (the app does this).
   The app creates the channels `sos_alerts` (high importance) and `general`.
6. **Backend service account**: Firebase console → *Project settings* → *Service accounts* → *Generate new private
   key*. Save it as `family_hub_backend/firebase-service-account.json` (git-ignored) and keep
   `FIREBASE_SERVICE_ACCOUNT_PATH=./firebase-service-account.json`. On a PaaS without files, put the base64 instead:
   ```bash
   base64 -i firebase-service-account.json | tr -d '\n'   # → FIREBASE_SERVICE_ACCOUNT_BASE64
   ```
7. **Verify**: log in on two devices with two family members, assign a task from one to the other → the assignee gets
   a `task_assigned` push; tap it → the task opens. Registered tokens are in the `devices` collection
   (`mongosh familyhub --eval 'db.devices.find()'`).

## 7. Cloudinary (image uploads)

1. Create a free account at <https://cloudinary.com>. Dashboard → *API Keys*: copy **Cloud name**, **API key** and
   **API secret**.
2. Backend `.env`:
   ```
   CLOUDINARY_CLOUD_NAME=<cloud name>
   CLOUDINARY_API_KEY=<api key>
   CLOUDINARY_API_SECRET=<api secret>
   ```
3. Restart the API. The app now uses **signed uploads**: it asks `POST /uploads/signature`, then uploads directly to
   Cloudinary. The secret never leaves the backend, and files land in `familyhub/<familyId>/avatars|notices`.
4. Recommended Cloudinary settings: restrict allowed formats (jpg, png, webp, heic) and maximum file size in
   *Settings → Upload*; enable automatic format/quality delivery.
5. **Optional dev shortcut (not for production):** create an *unsigned* upload preset in *Settings → Upload → Upload
   presets*, then set `CLOUDINARY_CLOUD_NAME` and `CLOUDINARY_UPLOAD_PRESET` in `config/dev.json`. This lets mock
   mode upload real images. Anyone who extracts the preset from the app can upload to your account, so never ship it.

Without any Cloudinary config, mock mode stores the **local file path**, while the real backend answers signature
requests with an error, so image pickers show a localized error instead of uploading.

## 8. Email (SMTP)

Without `SMTP_HOST`, every email (OTP, reset, invitation) is **printed to the API console**. For real emails:

**Gmail (development only, about 500 emails/day):**
1. Turn on 2-Step Verification for the Google account.
2. Google Account → *Security* → *App passwords* → create one (16 characters).
3. `.env`:
   ```
   SMTP_HOST=smtp.gmail.com
   SMTP_PORT=465
   SMTP_SECURE=true
   SMTP_USER=you@gmail.com
   SMTP_PASS=<16-char app password, no spaces>
   MAIL_FROM="FamilyHub <you@gmail.com>"
   ```

**SendGrid (or any transactional provider) for staging/production:**
1. Create an API key with *Mail Send* permission and verify a sender or, better, authenticate your domain
   (SPF + DKIM) so OTP emails do not land in spam.
2. `.env`:
   ```
   SMTP_HOST=smtp.sendgrid.net
   SMTP_PORT=587
   SMTP_SECURE=false          # STARTTLS on 587
   SMTP_USER=apikey           # literally the word "apikey"
   SMTP_PASS=<SendGrid API key>
   MAIL_FROM="FamilyHub <no-reply@your-domain.com>"
   ```
Amazon SES, Mailgun, Brevo and Postmark work the same way with their SMTP credentials.

## 9. Troubleshooting

| Symptom | Fix |
|---|---|
| App shows demo data although you set `API_BASE_URL` | dart-defines are read at build time: stop the app and run `flutter run --dart-define-from-file=config/dev.json` again. Check `USE_MOCK_API` is not `true`. |
| `NETWORK_ERROR` / timeouts from the Android emulator | Use `10.0.2.2`, not `localhost`. Check the API is running (`curl localhost:4000/api/v1/health` on the host). |
| Physical device cannot reach the API | Same Wi-Fi? Correct LAN IP? Allow Node through the OS firewall (macOS asks on first start). Or use `adb reverse` over USB. |
| Release Android build cannot reach the network | The `INTERNET` permission must be in `android/app/src/main/AndroidManifest.xml` (the template only puts it in debug/profile). |
| API exits with `Invalid environment configuration` | Fix the variable named in the message in `.env` (e.g. `JWT_ACCESS_SECRET` must be ≥ 32 chars). |
| API exits with `FIELD_ENCRYPTION_KEY is required in production` | Generate a 32-byte base64 key (§3) or run with `NODE_ENV=development`. |
| `MongooseServerSelectionError` / `ECONNREFUSED 127.0.0.1:27017` | MongoDB is not running: start it (§3 Option B) or use `npm run dev:memory`. |
| `npm run dev:memory` is slow or fails the first time | It downloads a MongoDB binary once; check the internet connection/proxy, then retry. |
| `npm run dev:memory` says "Missing script" | Run `node scripts/dev-memory.js` directly. |
| `EADDRINUSE :4000` | Another API is running. Stop it or set `PORT=4001` (and update `API_BASE_URL`). |
| No OTP email arrives | Without SMTP, the OTP is in the API console. With SMTP: check spam, the `MAIL_FROM` sender verification, and the API log for SMTP errors. Resend is limited to once per 60 s. |
| `429 TOO_MANY_REQUESTS` on login | 5 wrong passwords in 15 minutes lock the email; wait the time shown (`retryAfterSeconds`). |
| Logged out unexpectedly on every device | A refresh token was reused (e.g. restored backup or two clients sharing tokens), which revokes all sessions by design. Log in again. |
| Push not received | Firebase configured on **both** sides? Device token registered (`devices` collection)? iOS: APNs key uploaded, Push capability added, real device. Android 13+: notification permission granted. Check the API log for FCM errors. |
| Push works but tapping does nothing | The `data.route` must be one of the routes in the contract (§13); check the app log for the route received. |
| Firebase init error on start | `lib/firebase_options.dart` is still the stub or does not match the bundle id. Re-run `flutterfire configure` (§6). The app keeps working without push. |
| Image upload fails | Backend Cloudinary variables set? Clock correct (signatures expire)? Only `res.cloudinary.com` URLs are accepted by the API. |
| SOS sends without location | The member's location mode is `never`, or the OS permission is denied / location services are off. Check Settings → Location. |
| Strings show as keys or English after adding one | Run `dart run tool/l10n.dart`, then do a full restart. Missing translations fall back to English. |
| `l10n: another run holds the lock` | Another merge is running; the tool waits. A stale `.l10n.lock` directory from a crashed run is removed automatically after a timeout. |
| `flutter gen-l10n` duplicate key error | Two fragments define the same key. The tool prints both files; rename one key (keys are prefixed per feature). |
| Arabic layout looks mirrored wrongly | Use `EdgeInsetsDirectional` / `start`/`end`; see [`07-I18N_AND_COUNTRIES.md` §8](07-I18N_AND_COUNTRIES.md). |
| iOS build: CocoaPods errors | `cd ios && pod repo update && pod install`, then `flutter clean && flutter pub get`. |
