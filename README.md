# FamilyHub

**Run your family like a well-organised company.** Parents are the admins, every member has a role and a
designation, and the family shares one task board, one ledger with savings goals, one notice board, and an SOS
button that alerts everyone with live location. Built for many countries and many languages from day one.

| Module | What it does (Phase 1 MVP) |
|---|---|
| Family & roles | Create a family or join with an invite code; admins and members; managed profiles for kids and elders; guardian consent for minors |
| Tasks | Assign chores, study and errands with due dates; complete/reopen; push notifications |
| Ledger & goals | Income/expense ledger (record only, no real money moves), monthly summaries, savings goals with contributions |
| Dashboard | Everyone's pending tasks, goals, notices, this month's money and any active SOS on one screen |
| Notice board | Family announcements with images; admins pin |
| SOS | One tap alerts the whole family with 15 minutes of live location; "I'm okay" to resolve; local emergency number always shown |
| Emergency card | Blood group, allergies, medications, doctor, insurance and contacts per member; health fields encrypted |
| Settings & privacy | 15 languages, dark mode, large text, location sharing off by default, data export, account deletion |

Languages: English, हिन्दी, বাংলা, தமிழ், తెలుగు, मराठी, ગુજરાતી, ಕನ್ನಡ, മലയാളം, ਪੰਜਾਬੀ, العربية, Español, Français, Português, Deutsch.
Countries: 28, each with its currency, emergency number and age of digital consent.

## Repository layout

```
FamilyHub/
├── README.md                  ← you are here
├── docs/                      specifications, guides, task list, progress reports (start with docs/README.md)
├── family_hub_app/            Flutter app (Android + iOS), package `family_hub`
│   ├── lib/core/              config, design tokens, shared widgets, networking, mock backend, router, services
│   ├── lib/shared/            cross-feature models, repositories, session
│   ├── lib/features/<name>/   auth, family, tasks, ledger, notices, emergency_card, sos, settings, dashboard, home
│   ├── lib/l10n/              ARB translations (app_en.arb is generated from l10n_parts/)
│   ├── l10n_parts/            English strings, one fragment per feature
│   ├── tool/                  l10n merge tooling
│   ├── config/                build-time settings for --dart-define-from-file
│   └── test/
└── family_hub_backend/        Node.js REST API (Express 5, MongoDB/Mongoose 9, Zod 4)
    ├── src/                   app.js, server.js, config/, lib/, middleware/, models/, modules/<module>/, services/, i18n/
    ├── scripts/               seed.js, dev-memory.js, check-syntax.js
    ├── tests/                 node:test + supertest + in-memory MongoDB
    └── .env.example
```

## Quick start: the app in mock mode (no server needed)

```bash
cd family_hub_app
flutter pub get
flutter run --dart-define-from-file=config/dev.json
```

If `config/dev.json` is missing, copy `config/dev.example.json` first (or just run `flutter run`: with no
`API_BASE_URL` the app always uses its built-in mock backend).
Log in with **`demo@familyhub.app` / `demo1234`**. Every OTP in mock mode is **`123456`**. The demo family's invite
code is **`DEMO2345`**.

## Full stack (app + local API)

```bash
# terminal 1: API on http://localhost:4000 with an in-memory MongoDB and demo data
cd family_hub_backend
npm install
cp .env.example .env
npm run dev:memory            # or, with a local MongoDB: npm run seed && npm run dev

# terminal 2: app pointed at the API
cd family_hub_app
# set API_BASE_URL in config/dev.json:
#   Android emulator  http://10.0.2.2:4000/api/v1
#   iOS simulator     http://localhost:4000/api/v1
#   real device       http://<your LAN IP>:4000/api/v1
flutter run --dart-define-from-file=config/dev.json
```

Push notifications (Firebase), image uploads (Cloudinary) and real emails (SMTP) are optional; see
[`docs/09-SETUP_AND_RUN.md`](docs/09-SETUP_AND_RUN.md).

## Checks

```bash
(cd family_hub_app && flutter analyze && flutter test)
(cd family_hub_backend && npm test && npm run check)
```

## Documentation

| Doc | Read it for |
|---|---|
| [docs/README.md](docs/README.md) | Index of all documents |
| [00 · Concept](docs/00-CONCEPT.md) | The product owner's original brief and roadmap |
| [01 · Product scope](docs/01-PRODUCT_SCOPE.md) | What is in Phase 1, what comes later, and why |
| [02 · Architecture](docs/02-ARCHITECTURE.md) | System diagram, auth/push/SOS/upload flows, security model |
| [03 · API contract](docs/03-API_CONTRACT.md) | **The** source of truth for every endpoint |
| [04 · Data models](docs/04-DATA_MODELS.md) | MongoDB collections, fields, indexes |
| [05 · Flutter guide](docs/05-FLUTTER_GUIDE.md) | Binding app conventions |
| [06 · Backend guide](docs/06-BACKEND_GUIDE.md) | Binding backend conventions |
| [07 · i18n & countries](docs/07-I18N_AND_COUNTRIES.md) | Languages, countries, formatting, timezones |
| [08 · Compliance](docs/08-COMPLIANCE.md) | Privacy law checklists (DPDP, GDPR, COPPA…) mapped to features |
| [09 · Setup & run](docs/09-SETUP_AND_RUN.md) | Installing, running, Firebase/Cloudinary/SMTP, troubleshooting |
| [Tasks](docs/TASKS.md) | Module-wise master task list and later-phase epics |

## Principles

- **One contract.** The app, its mock backend and the API all implement `docs/03-API_CONTRACT.md`.
- **Privacy by default.** Location sharing is off until the member turns it on, and they always see when it is on.
  Health fields are encrypted. Another family's data is never visible.
- **Ledger, not a bank.** FamilyHub records money; it never holds or moves it.
- **SOS alerts the family.** It does not replace calling the local emergency number, which the app always shows.
