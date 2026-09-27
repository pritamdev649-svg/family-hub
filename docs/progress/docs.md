# Progress · docs (technical writer / project planner)

Owner files: `README.md`, `docs/README.md`, `docs/01-PRODUCT_SCOPE.md`, `docs/02-ARCHITECTURE.md`,
`docs/07-I18N_AND_COUNTRIES.md`, `docs/08-COMPLIANCE.md`, `docs/09-SETUP_AND_RUN.md`, `docs/TASKS.md`.

## Built

- [x] DOC-01 Root `README.md`: overview, module table, repo layout, mock-mode quick start (3 commands), full-stack quick start, checks, doc links, principles
- [x] DOC-02 `docs/README.md`: index of all docs (00–09 incl. `04-DATA_MODELS.md`, TASKS, progress/) with audience, one-liners and precedence rules
- [x] DOC-03 `01-PRODUCT_SCOPE.md`: roles, Phase 1 feature scope table (in / explicitly not in), changes vs the concept with rationale, non-functional requirements, pilot exit criteria, Phase 2–4 epics, permanent non-goals
- [x] DOC-04 `02-ARCHITECTURE.md`: 10 Mermaid diagrams (system, request lifecycle, register/verify, single-flight refresh, push, SOS live location, upload, i18n flow, ER model, deployment); token table; push type table; location modes; offline behaviour; mock mode; roles/permissions matrix; data-protection controls
- [x] DOC-05 `07-I18N_AND_COUNTRIES.md`: 15-language table (script, RTL, native digits and grouping verified against intl 0.20.2 data), text-source table, locale resolution, ARB fragment workflow (`tool/l10n.dart`, lock, duplicate detection), backend i18n files, add-a-language steps (app + backend), 28-country table (matches `countries.dart` / `countries.js`), review notes, add-a-country steps, plural categories (verified against intl plural rules), RTL/script rules, formatting rules (matches `Fmt` and `Validators.parseAmount`), timezone rules
- [x] DOC-06 `08-COMPLIANCE.md`: status legend, personal-data inventory, processors, 34-row global baseline checklist, DPDP / GDPR+UK Children's Code / COPPA checklists, 19 other countries table, breach runbook draft, 12 open gaps with proposals
- [x] DOC-07 `09-SETUP_AND_RUN.md`: prerequisites, mock mode + demo accounts, dart-define keys, backend (dev:memory, local MongoDB, Docker, Atlas), env var table, device networking (emulator, simulator, LAN, adb reverse), Firebase step by step (flutterfire, APNs, service account), Cloudinary, SMTP (Gmail app password, SendGrid), 25-row troubleshooting table
- [x] DOC-08 `TASKS.md`: 16 modules, 249 Phase 1 tasks (unique IDs, 281 items in total with later phases) and [API]/[App]/[Mock]/[Test]/[Ops]/[Doc]/[Legal] tags, all unchecked; Later phases (P2-01…P4-06) and cross-cutting X-01…X-07

## Pending

- [ ] DOC-09 Final pass: tick `TASKS.md` from `docs/progress/*.md`, move `08-COMPLIANCE.md` rows from `SPEC` to `DONE` once verified, fix drift (only one progress report, `b-models.md`, existed when this was written)
- [ ] DOC-10…DOC-13 Legal documents, store declarations, final breach runbook, pilot guide (need product owner / counsel input)
- [ ] Re-check `09-SETUP_AND_RUN.md` once `config/dev.example.json`, `scripts/seed.js` and the `dev:memory` npm script exist (demo accounts on the real backend and seed re-run behaviour are described as expected, not yet verified)

## Decisions made (documented in the files)

- Preferred l10n command is `dart run tool/l10n.dart` (merge + gen-l10n under a lock); `tool/merge_arb.dart && flutter gen-l10n` from `05-FLUTTER_GUIDE.md` is documented as the equivalent two-step form. Both tools exist.
- Compliance statuses use `DONE / SPEC / TODO / GAP / LEGAL / N/A`; contract-specified items are `SPEC` until verified.
- Global-baseline strategy: build to the strictest common rules (GDPR + DPDP + UK Children's Code + COPPA), handle country deltas operationally.
- Law details, breach deadlines, emergency numbers and consent ages are marked "verify with counsel"; review notes list the numbers in `countries.dart` that are police-only or otherwise worth checking (BR, LK, NP, PK, SG, AE, SA, ZA, CA-Quebec, AU/NZ).
- Phase 1 scope explicitly pulls forward multiple savings goals and the admin/member permission split (with rationale).

## Known issues / risks

- **GAP-01 (important):** the contract has no age gate on `POST /auth/register` `mode: "join"`, so a minor can self-register without guardian consent. Proposal in `08-COMPLIANCE.md` §9 needs a contract change.
- Other open gaps GAP-02…GAP-12 (Cloudinary deletion, SOS/location retention, re-consent on country/DOB change, consent version, managed-profile export, audit log, backup/log retention, family deletion, emergency-contact notice).
- `family_hub_app/lib/core/config/app_config.dart` comment says `GET /uploads/signature`; the contract says `POST`.
- `family_hub_backend/package.json` has no `dev:memory` script yet (the script file exists); docs give `node scripts/dev-memory.js` as a fallback.
- `family_hub_app/config/` (dev.json / dev.example.json) does not exist yet; docs tell users to copy the example file.
- Android main `AndroidManifest.xml` lacks the `INTERNET` permission (only debug/profile have it): release builds would have no network. Tracked as FF-24 and in troubleshooting.
- Mermaid diagrams could not be rendered locally (no mermaid CLI installed, no packages added); they were checked by a script for headers, declared participants, balanced blocks and forbidden characters.
