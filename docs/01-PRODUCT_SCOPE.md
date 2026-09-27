# 01 · Product Scope

> What is in the **current build (Phase 1 MVP)**, what is deliberately **left for later phases**, and why.
> Product source of truth: [`00-CONCEPT.md`](00-CONCEPT.md). API source of truth: [`03-API_CONTRACT.md`](03-API_CONTRACT.md).
> Task-level breakdown and progress: [`TASKS.md`](TASKS.md).

## 1. Product in one paragraph

FamilyHub runs a family the way a small company is run. One or more parents are **admins** (the "management"),
everyone else is a **member** with a free-text **designation** ("Chief Study Officer", "Finance Head"). Admins assign
tasks, keep a shared ledger with savings goals, and post notices. Every member has an emergency card and a one-tap
SOS that alerts the rest of the family with live location. The app is built for **many countries and many languages**
from day one, and for multi-generational use: kids, parents and grandparents, on low-end phones.

## 2. Who uses it (Phase 1 roles)

| Role | Who | Can do |
|---|---|---|
| **Admin** | Parent / head of family. The family creator is the first admin. There can be several admins. | Everything: manage family settings and invite code, add/edit/remove members, assign tasks to anyone, see the whole ledger, manage savings goals, pin notices, resolve anyone's SOS, edit anyone's emergency card. |
| **Member (with account)** | Teen, adult child, spouse, grandparent with a phone. Joins with the family invite code. | Own tasks (create for self, complete/reopen own), own ledger entries and personal summary, contribute to goals, post notices, trigger SOS, edit own profile and emergency card. |
| **Managed profile (no account)** | Young child or elder without a phone, added by an admin (`hasAccount=false`). | Nothing directly. An admin manages the profile (tasks, emergency card). If an admin later adds an email, that person can register with the invite code and is **linked** to the existing profile. |

Minors: when a member is younger than the country's digital age of consent (`consentAge`, see
[`07-I18N_AND_COUNTRIES.md`](07-I18N_AND_COUNTRIES.md)), an admin must confirm **guardian consent** when adding them.

## 3. Phase 1: the current build

### 3.1 Feature scope

| # | Module | In the build | Explicitly **not** in Phase 1 |
|---|---|---|---|
| 1 | **Accounts & auth** | Email + password sign-up, **6-digit email OTP** verification, login with lockout (5 failures / 15 min), forgot/reset password by OTP, change password, JWT access token (15 min) + **rotating** refresh token (30 days), logout per device. | Phone/SMS OTP, social login (Google/Apple), passkeys, 2FA, web app. |
| 2 | **Family setup & roles** | Create a family (name, country, currency, timezone) or join one with an 8-character invite code. Admin/member roles, designations, several admins, "last admin" protection, invite-code rotation, managed profiles, guardian consent for minors, leave family, remove member. | Several families per user, family-level delete by admin (a family is deleted when its last member deletes their account), custom permission tiers. |
| 3 | **Tasks / chores** | Title, description, assignee, due date, category (study, chore, skill, health, errand, other), priority, complete/reopen, filters (mine / member / status / overdue / today / week), push on assign and on completion. | Recurring tasks, sub-tasks, rewards/points, monthly auto review, attachments. |
| 4 | **Ledger & savings goals** | Income/expense entries with fixed categories, per-member attribution, monthly summary by category (admin: family; member: personal), **multiple** savings goals with progress, contributions (recorded as `savings` expense), "goal achieved" push. **Ledger only: no real money moves.** | Sub-wallets and spending limits, recurring bills, budgets, bank sync, payments, multi-currency within one family, receipts. |
| 5 | **Dashboard** | One screen: active SOS, my pending tasks, each member's pending/overdue/completed-this-week counts, active goals, latest notices, this month's summary. | Charts over time, monthly PDF report, growth tracking. |
| 6 | **Notice board** | Post notices with an optional image, admins pin notices, push to the family. | Comments, reactions, read receipts, scheduled notices, polls. |
| 7 | **SOS / emergency alert** | One-tap SOS with a 3 s cancel countdown, high-priority push to all family members, **live location for 15 min** (update every ≥ 5 s, trail of the last 100 points), "I'm okay" / resolve (safe, false alarm, helped), history, the country emergency number shown next to the button. Location sharing is **off by default**, with three modes: never, only during SOS, always. The member always sees an indicator while their location is shared. | Contacting emergency services, SMS fallback to non-app contacts, fall/crash detection, geofences, continuous background tracking in "always" mode (in Phase 1, "always" refreshes the location when the app is opened or resumed). |
| 8 | **Emergency quick-access card** | Per member: blood group, allergies, medications, conditions, doctor, insurance, up to 5 emergency contacts, notes. One tap to call. Sensitive fields are **encrypted at rest**. | Lock-screen widget, medical ID export, QR card, full health records. |
| 9 | **Settings & privacy** | Profile and avatar, language (15), theme (light/dark/system), text size (up to 1.4×), location sharing mode, change password, **export my data** (JSON), **delete my account**, leave family, about/legal links. | Notification preferences per type, "simplified mode" UI, voice input. |
| 10 | **Push notifications** | Firebase Cloud Messaging for Android and iOS, localized per recipient, tapping a notification opens the right screen (also from a cold start), invalid tokens are cleaned up. Separate Android channel for SOS. | In-app notification feed, email digests, quiet hours. |
| 11 | **Uploads** | Avatars and notice images uploaded **directly** from the app to Cloudinary with a backend-signed request (resized to max 1600 px). | Documents/PDFs, video, the Documents Vault. |
| 12 | **Internationalisation** | 15 UI languages: `en hi bn ta te mr gu kn ml pa ar es fr pt de`, including Arabic RTL. Server error messages, push and email are localized too. 28 countries with currency, emergency number and consent age. Locale-aware money, date and number formats. | Voice UI, per-member regional calendars (Hijri, Vikram Samvat, etc.), transliteration. |
| 13 | **Mock mode** | The app runs fully offline against an in-memory mock backend with seeded demo data (for demos, UI work and store screenshots). | — |

### 3.2 What changed compared with the concept's Phase 1, and why

| Change | Rationale |
|---|---|
| **Multiple savings goals** instead of "one savings goal" (concept moved multiple goals to Phase 2) | Supporting a list of goals costs the same as one in the data model and API, and the concept's own examples ("vacation fund, education fund") already run side by side. Phase 2 keeps the richer *visualisation* (charts, history). |
| **Two-tier permissions** (admin / member) are in Phase 1 (concept lists "basic permission tiers" in Phase 2) | The concept's Phase 1 already requires "full visibility for parents; limited view for kids" for the ledger. The simplest correct way is the admin/member split enforced by the backend. Finer-grained tiers (custom roles, per-module visibility) stay in Phase 2. |
| **Email OTP auth, push, uploads** were added | These are infrastructure needed to make the Phase 1 features usable: the SOS feature needs push, the notice board and profiles need images, and a family app needs verified emails for invitations and password reset. |
| **15 languages + 28 countries** from day one | The product owner requires multiple countries and languages. Building i18n in from the start costs far less than retrofitting it later (layout, RTL, formatting, server messages). |
| **Export / delete my data, guardian consent, location off by default** | Compliance requirements (DPDP, GDPR, COPPA and others, see [`08-COMPLIANCE.md`](08-COMPLIANCE.md)). They are cheap to build now and very expensive to add after launch. |
| **Polling instead of WebSockets** for SOS (5 s on the alert screen, 15 s for the global SOS banner) | Push delivers the alert itself. Polling for the live location is simple, works behind every proxy and mobile network, scales for small families, and needs no extra infrastructure. It can be replaced later without an API change for the sender side. |
| **"Always share" location refreshes only on app open/resume** | Continuous background tracking needs extra OS permissions ("Always" on iOS, background location on Android), store policy declarations and battery work. It is also the most surveillance-like behaviour. The SOS live window gets real-time tracking through a foreground service, which is the core safety value. |

### 3.3 Non-functional requirements (Phase 1)

- **Low-end phones & data:** image uploads resized (max width 1600, quality 80), cached network images, paginated lists
  (20 per page), JSON-only API with gzip compression, no heavy SDKs (no analytics or ads SDKs).
- **Multi-generational:** text scales up to 1.4× without clipping, minimum 48 dp tap targets, screen-reader labels on
  icon buttons, plain wording, one clear primary action per screen.
- **Resilience:** the app opens with the last cached session when offline, shows an offline banner, and every screen
  has loading, error (with retry), empty and data states.
- **Privacy by default:** location off, `lastLocation` only visible when the member chose "always", invite code only
  visible to admins, health fields encrypted, other families' data returns 404 (never 403).
- **Security:** hashed refresh tokens and OTPs, bcrypt passwords, login lockout, per-IP rate limits, no stack traces or
  personal data in API errors or logs.

### 3.4 Pilot exit criteria (from the concept's "recommended next step")

Phase 1 is "done" when a small pilot group of families can, for 4 weeks without developer help:

1. Create a family, invite members and add managed profiles for kids/elders, in their own language.
2. Assign and complete tasks every day, with push notifications arriving.
3. Record the month's income/expenses and contribute to at least one goal.
4. Trigger a test SOS that everyone receives, see live location, and resolve it.
5. Open anyone's emergency card within two taps from the home screen.
6. Export their data and delete an account without support tickets.

## 4. Later phases

Items come from the concept roadmap. Epics with IDs are tracked in [`TASKS.md`](TASKS.md#later-phases).

### Phase 2: accountability, money & engagement

| Epic | Notes / prerequisite |
|---|---|
| Sub-wallets per member with parent-set spending limits | Still **ledger-only**. Real money only through a licensed provider (e.g. Razorpay / Cashfree in India) after a regulatory review. |
| Savings goal visualisation (history charts, projections) | Builds on Phase 1 multiple goals. |
| Monthly family review (auto summary of tasks done/missed, spending) | Needs a scheduled job runner (cron/queue) on the backend. |
| Recurring expenses (bills, subscriptions) with reminders | Needs scheduled jobs + reminder push type. |
| Fine-grained permission tiers | Custom roles, per-module visibility. |
| Documents & Records Vault (**metadata only**) | Category, owner(s), expiry date, reminders. No file storage yet; DigiLocker integration preferred in India. |
| Family Feed / Moments | Photo posts with reactions. Reuses Cloudinary upload flow. |
| Suggestions Box | Upvotes, admin status (under review / approved / declined). |
| Requests module (peer-to-peer asks) | open → accepted → done. |
| Household logistics: shopping list & inventory | Shared list, "running low" flags. |

### Phase 3: health, growth & unified view

| Epic | Notes / prerequisite |
|---|---|
| Health profile (height/weight logs, doctor visit reminders) | Health data: encrypted fields, separate consent, **wellness only, never medical advice**. |
| Nutrition guidance / weekly meal plans | Content licensing and dietary disclaimers per country. |
| Education & skill tracking for kids | Grades, courses, extracurriculars. |
| Personal growth goals for adults | Fitness, learning, career. |
| Vaccination & medicine reminders | Country-specific schedules; not medical advice. |
| Shared family calendar | Unifies tasks, health, documents, meetings, birthdays. |
| Domestic help / staff management | Schedule, pay (ledger), attendance, contacts. Strong differentiator for Indian households. |
| Full document storage in the Vault | Encrypted object storage, per-document access control, DigiLocker where possible. |

### Phase 4: governance & polish

| Epic | Notes / prerequisite |
|---|---|
| Family meeting scheduler with logged decisions | |
| "Family concern" log (private issues raised to parents) | Needs careful child-safety design. |
| Unified notification feed across modules | Replaces per-type push only. |
| Exportable monthly family report (PDF) | Server-side rendering, localized fonts for all scripts. |
| Family chat / sub-groups | Largest build; consider real-time infrastructure then. |
| Multi-family support (product for clients) | Tenant model beyond one family per user. |

### Cross-cutting items planned after Phase 1

- Large-text **simplified mode** for elderly members (Phase 1 only scales text) and **voice input** (Phase 1 relies
  on the OS keyboard dictation).
- Offline write queue (Phase 1 needs a connection for changes).
- Real-time channel (WebSocket/SSE) if polling costs grow.
- Background location for "always share" (only if users ask for it, with store policy review).
- Admin web console, analytics (privacy-preserving), crash reporting.

## 5. Out of scope permanently (unless the product owner decides otherwise)

- Holding, moving or investing real money inside FamilyHub (always via licensed partners).
- Medical diagnosis or advice (wellness information only).
- Contacting emergency services on the user's behalf. SOS alerts the **family**; the app shows the local emergency
  number so the user can call it themselves.
- Covert tracking of any member. Location sharing is always visible to the person being located.
