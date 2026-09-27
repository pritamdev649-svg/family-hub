# FamilyHub documentation

Start with **00** for the idea, **01** for what is being built now, **02** for how it fits together, and **09** to
run it. Engineers: **03** plus **05** (app) or **06** (backend) are binding.

| # | Document | Audience | One-line description |
|---|---|---|---|
| 00 | [Concept](00-CONCEPT.md) | Everyone | The product owner's original brief: modules, design principles, phased roadmap (kept verbatim). |
| 01 | [Product scope](01-PRODUCT_SCOPE.md) | Everyone | What is in the Phase 1 MVP, what moved and why, non-functional requirements, pilot exit criteria, later phases. |
| 02 | [Architecture](02-ARCHITECTURE.md) | Engineers | System diagram and the auth, push, SOS live-location, upload, i18n, offline and mock-mode flows; security model. |
| 03 | [API contract](03-API_CONTRACT.md) | Engineers (**binding**) | Every endpoint, payload, enum and error code. App, mock backend and API all implement it. |
| 04 | [Data models](04-DATA_MODELS.md) | Backend engineers | MongoDB collections, fields, limits and indexes (Mongoose 9). |
| 05 | [Flutter guide](05-FLUTTER_GUIDE.md) | App engineers (**binding**) | Folder structure, design tokens, shared widgets, state, l10n, networking, routing, public APIs. |
| 06 | [Backend guide](06-BACKEND_GUIDE.md) | Backend engineers (**binding**) | Layering, shared services, models, i18n, tests. |
| 07 | [i18n & countries](07-I18N_AND_COUNTRIES.md) | Engineers, translators | 15 languages, ARB fragment workflow, adding a language/country, country table, formatting and timezone rules. |
| 08 | [Compliance](08-COMPLIANCE.md) | Product, engineers, counsel | Data inventory and per-law checklists (DPDP, GDPR/UK GDPR, COPPA, others) mapped to features, with status and open gaps. |
| 09 | [Setup & run](09-SETUP_AND_RUN.md) | Engineers, testers | Prerequisites, mock mode, backend, device networking, Firebase, Cloudinary, SMTP, demo accounts, troubleshooting. |
| — | [Tasks](TASKS.md) | Everyone | Module-wise master task list (app + backend) with IDs, and later-phase epics. |
| — | [`progress/`](progress/) | Project lead | One report per engineer/agent (`<label>.md`): what was built, what is pending, known issues. Used to tick [TASKS.md](TASKS.md). |

## Precedence when documents disagree

1. `03-API_CONTRACT.md` (change it first, then the code on both sides).
2. `05-FLUTTER_GUIDE.md` / `06-BACKEND_GUIDE.md` for conventions.
3. The code.
4. Everything else (01, 02, 04, 07, 08, 09). Fix these descriptive docs when they drift.

## Conventions for docs

- Plain English, short sentences; tables for anything that is a list of facts.
- Diagrams in Mermaid so they render on GitHub and stay editable.
- File references are relative to the repo root (`family_hub_app/...`, `family_hub_backend/...`).
- Compliance statuses use `DONE / SPEC / TODO / GAP / LEGAL / N/A` (defined in [08](08-COMPLIANCE.md#0-how-to-read-the-status-columns)).
