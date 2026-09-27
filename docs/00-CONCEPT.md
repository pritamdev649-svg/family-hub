# 00 · Concept (original brief from the product owner)

> Kept verbatim as the product source of truth. Engineering scope decisions live in `01-PRODUCT_SCOPE.md`.

## Family Management App — Concept Document & MVP Roadmap

### 1. Concept Overview
The idea is to build software that structures a family the way a private limited company is structured — with defined roles, shared responsibility, centralized accounts, and tracked growth. Instead of family life running informally, this system brings organizational discipline: clear responsibilities, financial transparency, health tracking, and structured communication.
Parents/head of family act as the primary admin (like a CEO/manager), with other members reporting in — similar to how a manager oversees a team.

### 2. Core Modules

**Roles & Responsibility Module**
- Each member gets a role with age-appropriate duties (kids: study/chores, teens: skill-building, parents: oversight)
- Task assignment and completion tracking, similar to a company task board
- Monthly family check-ins to review progress (structured, not punitive)

**Centralized Accounts Module**
- Shared family ledger for income, expenses, and savings goals
- Full visibility for parents; limited view for kids (their allowance, spending)
- Goal-based savings tracking (e.g., vacation fund, education fund)

**Health & Nutrition Module**
- Basic health metrics per member (height/weight over time, appointment reminders)
- Nutrition guidance and meal planning based on age and activity level
- Vaccination and medicine reminders

**Growth & Development Module**
- Education tracking for kids (grades, skills, extracurriculars)
- Personal goals for adults (fitness, career, learning)
- A family dashboard showing everyone's growth at a glance

**Communication & Governance Layer**
- Scheduled family 'board meetings' with logged decisions
- Notice board for announcements
- A structured 'family concern' log for raising issues to parents

**Documents & Records Vault**
- Secure digital locker per member for important documents, organized by category:
  - Identity (Aadhaar, PAN, passport, birth certificates)
  - Property & Assets (property deeds, registry papers, rent agreements, vehicle RC, insurance)
  - Financial (insurance policies, loan documents, investment statements)
  - Education (certificates, marksheets, degrees)
  - Medical (prescriptions, reports, insurance claims)
  - Legal (wills, agreements)
- Expiry/renewal reminders (passport expiry, property tax due dates, insurance renewal)
- Ownership-aware access: jointly-owned documents visible to all stakeholders; personal ID docs visible only to that member + admin
- Search across all family documents by category, member, or tag

**Family Feed / Moments**
- Any member can post a photo with a title and short description, visible to the family group
- Comments/reactions from other members (lightweight — likes/hearts, not a full social network)
- Doubles as a running family photo/memory album over time

**Suggestions Box**
- Members can submit suggestions to the family or directly to admin/parents (distinct in tone from the "family concern" log — suggestions, not complaints)
- Optional upvoting so popular suggestions surface naturally
- Admin can mark suggestions "under review" / "approved" / "declined"

**Requests Module**
- Peer-to-peer asks between members (e.g. "can someone pick up milk," "help with homework," "can I borrow the car")
- Distinct from admin-assigned tasks — this is member-to-member
- Request status: open → accepted → done

**SOS / Emergency Alert**
- One-tap SOS trigger — minimal friction by design
- Instantly notifies all family members with sender's live location
- Live tracking window (e.g. location updates every few seconds for 10–15 minutes) rather than a single static pin
- Location sharing default OFF, with explicit member-controlled toggle: "always share," "share only during SOS," "never share"
- Visible indicator to the member themselves when their location is being shared/tracked (prevents this from feeling like silent surveillance)
- Cancel/"I'm okay" button to handle false alarms
- Positioned clearly as "alert my family," not a replacement for calling emergency services (112 etc.)

**Emergency Quick-Access Card**
- Always-accessible per-member card: blood group, allergies, key medications, doctor's contact, insurance policy number
- Designed so someone else can pull it up quickly in an emergency without digging through the app

**Shared Family Calendar**
- Unified calendar pulling from other modules: birthdays, school events, health appointments, family meetings, document renewal/expiry dates
- Acts as the single top-level view tying all modules together

**Household Logistics — Shopping & Inventory**
- Shared grocery/household list anyone can add to
- Simple running inventory ("running low on X")

**Domestic Help / Staff Management**
- Track schedule, monthly payment, attendance/leave, and contact info for household help (cook, maid, driver, etc.)
- Particularly relevant for Indian households — a differentiated feature vs. generic family apps

**Family Chat / Sub-Groups**
- Family-wide message thread, plus optional sub-groups (e.g. "parents only," "siblings")
- Larger build — positioned as a later "nice to have" rather than a core early feature

### 3. Design Principles for Multi-Generational Use
- Regional language support (not just English/Hindi)
- Large-text / simplified mode for elderly members
- Voice input for logging things, for members who don't want to type
- Works reasonably well on low-end phones and limited data — a real constraint for much of the target market in India
- (Added by product owner:) Must work in **multiple countries** and **multiple languages**.

### 4. MVP Roadmap (Phased Build)

**Phase 1 — Core Structure (MVP)** — the minimum needed to prove the concept and get a family using it daily.
- Family setup: parent(s) as admin, add members with roles/ages
- Task/chore assignment with due dates and completion tracking
- Centralized shared ledger: income, expenses, one savings goal
- Simple dashboard showing each member's pending tasks and goal progress
- Basic notice board for family announcements
- SOS / Emergency Alert (one-tap, live location, cancel option)
- Emergency Quick-Access Card per member

**Phase 2 — Accountability, Money & Engagement**
- Sub-wallets per member with parent-set spending limits
- Multiple savings goals with progress visualization
- Monthly family review — auto-generated summary of tasks done/missed
- Recurring expense tracking (bills, subscriptions) with reminders
- Basic permission tiers (what kids see vs. what parents see)
- Documents & Records Vault (start metadata-only)
- Family Feed / Moments
- Suggestions Box
- Requests Module
- Household Logistics — Shopping & Inventory

**Phase 3 — Health, Growth & Unified View**
- Health profile per member: height/weight logs, doctor visit reminders
- Nutrition guidance: weekly meal plans based on age/activity
- Education/skill tracking for kids (grades, courses, extracurriculars)
- Personal growth goals for adults (fitness, learning, career)
- Vaccination/medicine schedule reminders
- Shared Family Calendar (unifies tasks, health, documents, meetings)
- Domestic Help / Staff Management
- Full document storage in the Vault

**Phase 4 — Governance & Polish**
- Structured family meeting scheduler with logged decisions
- 'Family concern' log for raising issues privately to parents
- Notifications/reminders across all modules (single feed)
- Exportable family reports (monthly PDF summary)
- Family Chat / Sub-Groups
- Multi-family support if turned into a product for clients

### 5. Compliance Considerations (summary — full checklist in `08-COMPLIANCE.md`)
- DPDP Act (India, 2023): explicit consent; verifiable parental consent for under-18s; access/correct/delete rights.
- Health data: encrypt/separate; wellness guidance only, never medical advice.
- Money: ledger only in MVP — never hold or move real money; later only via licensed providers (Razorpay/Cashfree).
- Documents/IDs: metadata-only first; DigiLocker integration preferred over self-hosting.
- Location/SOS: default OFF, member-controlled, always-visible indicator, SOS ≠ emergency services.
- Children: guardian is consenting party; data minimisation; retention/deletion policy.
- General: privacy policy & terms before launch; encryption in transit & at rest; breach plan; GDPR if outside India.

### 6. Recommended Next Step
Build Phase 1 as a ledger/tracker (no real money movement) and pilot it with a small group of families before layering in payments, full document storage, or multi-family scaling.
