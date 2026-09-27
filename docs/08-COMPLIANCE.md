# 08 · Compliance & Privacy Checklist

> Turns the concept's compliance section ([`00-CONCEPT.md` §5](00-CONCEPT.md)) into an actionable checklist, mapped
> to concrete app and backend features.
>
> **Not legal advice.** This is an engineering checklist. Every item marked `LEGAL` and every law summary must be
> reviewed by qualified counsel in each launch country before real families use the product. Deadlines and ages quoted
> here are commonly cited values to **verify**, not guarantees.

## 0. How to read the status columns

| Status | Meaning |
|---|---|
| `DONE` | Implemented **and** verified by a test or a manual check (the final docs pass updates items to this). |
| `SPEC` | Specified in [`03-API_CONTRACT.md`](03-API_CONTRACT.md) / the guides and being built in Phase 1. Verify, then mark `DONE`. |
| `TODO` | Needed, agreed, not started. |
| `GAP` | Not specified anywhere yet. Needs a decision (usually a contract change) and an owner. Listed in §9. |
| `LEGAL` | Non-engineering work: documents, registrations, contracts, store declarations. |
| `N/A` | Does not apply to Phase 1 (with reason). |

**Strategy:** build **one global baseline** that satisfies the strictest common requirements (GDPR + DPDP + UK
Children's Code + COPPA), then handle per-country deltas (breach deadlines, registrations, local representatives,
data residency) operationally. The baseline is §3; law-specific checklists are §4–§7.

## 1. Personal data inventory (record of processing)

| Data | Whose | Where stored | Purpose | Sensitivity | Retention (Phase 1) |
|---|---|---|---|---|---|
| Name, email, password hash, locale, consent timestamp | Account holders | `users` | Account, login, communication | Normal | Until account deletion |
| Member profile: name, email, phone, DOB, gender, designation, role, avatar URL | All members incl. managed profiles (children, elders) | `members` | Family structure, age-appropriate features, consent-age checks | Normal; **children's data** | Until the member is removed or deletes their account |
| Guardian consent flag, time, consenting admin | Minors | `members` | Proof of verifiable parental consent | Compliance record | With the member record (see GAP-06) |
| Location sharing mode, last location | Members | `members.lastLocation` | Family location (only if mode `always`) | **High (location)** | Overwritten on each update (see GAP-04) |
| SOS alert, message, location trail (≤ 100 points) | Member who raised SOS | `sos_alerts` | Emergency alert to family | **High (location, safety)** | Indefinite in Phase 1 (see GAP-03) |
| Emergency card: blood group, allergies, medications, conditions, doctor, insurance, contacts, notes | Members; emergency contacts (third parties) | `emergency_cards` (health fields AES-256-GCM encrypted) | Emergency access by family | **Health data (special category)** | Until the member is removed / deletes account |
| Tasks | Members | `tasks` | Family task board | Normal | Pending tasks deleted with the member; done tasks kept |
| Ledger entries, goals | Members | `ledger_entries`, `goals` | Family finances (ledger only) | **Financial** (no account numbers) | Kept after a member leaves (keeps `memberName`) |
| Notices (text, image) | Authors | `notices`, Cloudinary | Family announcements | Normal (may contain personal content) | Until deleted by author/admin |
| Avatars and notice images | Members | Cloudinary `familyhub/<familyId>/…` | Profile pictures, notices | Normal (faces of children) | See GAP-02 |
| Device push tokens, platform, locale | Account holders | `devices` | Push notifications | Normal (device identifier) | Deleted on logout, account deletion, or when FCM reports invalid |
| Refresh token hashes, IP, user agent | Account holders | `refresh_tokens` | Session security | Normal (IP is personal data in the EU) | TTL 30 days |
| OTP hashes | Account holders | `otps` | Email verification, password reset | Normal | TTL 10 minutes |
| Server logs (request line, status, timing) | Everyone | Host logs | Operations, security | Normal (IP addresses) | Define with the hosting provider (TODO) |
| Session cache, settings | Device owner | Phone: SharedPreferences; tokens in secure storage | Offline start, preferences | Normal | Cleared on logout |

## 2. Processors (sub-processors)

| Processor | Data | Region / transfer | Status |
|---|---|---|---|
| MongoDB host (e.g. MongoDB Atlas) | All server data | Choose the region per launch market (e.g. India region for IN) | `LEGAL` DPA + region decision |
| Hosting provider for the API | All data in transit, logs | Same region as the database | `LEGAL` DPA |
| Google Firebase Cloud Messaging (+ Apple APNs) | Push token, notification title/body | Global (US) | `LEGAL` DPA / SCCs; keep push content minimal (§3 row 20) |
| Cloudinary | Images (avatars can show children) | Choose storage region if the plan allows | `LEGAL` DPA / SCCs |
| SMTP provider (SendGrid, SES, Gmail for dev only) | Email address, OTP, invitation text | Provider region | `LEGAL` DPA; **Gmail is for development only** |

No analytics, advertising or crash-reporting SDKs are included in Phase 1. Adding one requires updating this table,
the privacy policy and the store declarations first.

## 3. Global baseline controls

| # | Requirement | App (Flutter) | Backend (API) | Status |
|---|---|---|---|---|
| 1 | **Consent at signup** to privacy policy + terms, recorded | Register screen: unticked checkbox with links (`AppConfig.privacyPolicyUrl`, `termsUrl`); submit disabled until ticked | `consentAccepted` must be `true` → else `422 VALIDATION_ERROR`; store `consentAcceptedAt` | `SPEC` |
| 2 | Record **which** policy version was accepted | — | Store policy version + locale with the consent | `GAP` (GAP-07) |
| 3 | **Guardian consent for minors** (age < `consentAge(country)`) | Add/edit member: when DOB makes the person a minor (`isMinorIn(country)`), show a mandatory guardian-consent checkbox with explanation | `422 GUARDIAN_CONSENT_REQUIRED` without `guardianConsent: true`; store `guardianConsentAt`, `guardianConsentById` | `SPEC` |
| 4 | Minors cannot **self-register** without guardian consent | Register (join mode) asks DOB | No age gate on `POST /auth/register` in the contract | `GAP` (GAP-01) |
| 5 | Re-check consent when **country or DOB changes** | — | Contract silent on `PATCH /family` country change and `PATCH member` DOB change | `GAP` (GAP-05) |
| 6 | **Data minimisation** | Optional fields stay optional (phone, email for managed profiles, gender, DOB for adults); no contacts/photos access beyond the picked image | Zod schemas reject unknown fields; limits on list sizes and text lengths | `SPEC` |
| 7 | **Right of access / portability** | Settings → Privacy → "Export my data" (shares a JSON file) | `GET /me/export`: user, member, tasks, own/created ledger entries, notices authored, emergency card, SOS alerts | `SPEC` |
| 8 | Export for **managed profiles** (children without accounts) by their guardian | — | No endpoint | `GAP` (GAP-08) |
| 9 | **Right to correction** | Profile edit; admins edit managed profiles; emergency card edit | `PATCH /me`, `PATCH /family/members/:id`, `PUT …/emergency-card` | `SPEC` |
| 10 | **Right to erasure** | Settings → Privacy → "Delete account" (password confirmation, clear explanation of what is deleted and the last-admin rule) | `DELETE /me`: account + member + card + devices + tokens; last admin with others → `409 LAST_ADMIN`; only member → whole family deleted | `SPEC` |
| 11 | Erasure of **images** on Cloudinary | — | Not in contract | `GAP` (GAP-02) |
| 12 | Leave family (withdraw from shared processing) | Settings → "Leave family" | `POST /me/leave-family` (same last-admin rule) | `SPEC` |
| 13 | Admin removes a member (incl. child) → data removed | Member detail → Remove (confirm dialog) | Unlinks user, revokes tokens, removes devices, deletes pending tasks + emergency card, resolves active SOS | `SPEC` |
| 14 | **Location default OFF** | Location settings screen explains the 3 modes; default `never` | `locationSharing` default `never`; `PUT /me/location` → `403 LOCATION_SHARING_DISABLED` unless `always` | `SPEC` |
| 15 | **Visible indicator** while location is shared | Foreground-service notification (Android) / location indicator (iOS) during SOS tracking; in-app banner; "always" mode shows a persistent hint in settings/profile | `lastLocation` only serialised when mode is `always` | `SPEC` |
| 16 | Member controls their own location mode (not an admin) | Only the member can change their mode in Settings | `locationSharing` only via `PATCH /me` (self) | `SPEC` |
| 17 | **SOS disclaimer**: alerts the family, not emergency services | SOS screen shows "This alerts your family. In danger, call {number}" with the country emergency number and a call button; shown again in the first-use explanation | Push text never claims help is on the way | `SPEC` |
| 18 | **Ledger-only money** | No payment, bank, card or UPI fields anywhere; wording "record", never "pay"/"transfer" | No payment integrations; amounts only | `SPEC` |
| 19 | **Health data encrypted at rest** | Not cached unencrypted on device (if an offline copy is added, use secure storage) | AES-256-GCM for allergies, medications, conditions, insurance policy no., notes; `FIELD_ENCRYPTION_KEY` mandatory in production | `SPEC` |
| 20 | Minimal **push content** (lock screens are visible to others) | — | Push texts contain names and short titles only; never health data, amounts or notice bodies | `SPEC` (verify texts) |
| 21 | Encryption **in transit** | Production `API_BASE_URL` must be `https://` | TLS at load balancer; HSTS (helmet) | `TODO` (deploy) |
| 22 | Database encryption at rest (whole DB, backups) | — | Enable storage encryption at the DB provider (Atlas does this by default) | `TODO` (deploy) |
| 23 | Account security | Password rules, lockout message, OTP screens | bcrypt, lockout 5/15 min, rate limits, hashed tokens/OTPs, refresh rotation + reuse detection | `SPEC` |
| 24 | No enumeration | Neutral messages | `forgot-password` always `{ sent: true }`; generic `INVALID_CREDENTIALS` | `SPEC` |
| 25 | Family isolation | — | Every query scoped by `familyId`; other family → `404` | `SPEC` |
| 26 | Logs without personal data | No PII in `debugPrint` / crash logs | No bodies, tokens, emails or locations in logs | `SPEC` |
| 27 | Retention & deletion schedule | — | TTLs exist for tokens/OTPs; SOS/location/backups/logs need rules | `GAP` (GAP-03, GAP-04, GAP-10) |
| 28 | **Breach response plan** | — | See §8 (draft runbook); key-rotation tooling | `TODO` |
| 29 | Privacy policy + terms (all 15 languages), children's notice, SOS disclaimer text | Links in register, settings → about | — | `LEGAL` |
| 30 | Grievance / privacy contact (DPO where required) | Settings → About → privacy contact email | — | `LEGAL` |
| 31 | No ads, no sale of data, no behavioural tracking of children | No ads/analytics SDKs | No third-party sharing beyond processors | `SPEC` |
| 32 | Audit trail of admin actions on children's data | — | Not in Phase 1 | `GAP` (GAP-09) |
| 33 | Store declarations: Google Play **Data safety**, target audience, foreground-service (location) declaration; Apple **privacy nutrition labels**, location/notification usage strings | Manifest/Info.plist strings localized | — | `LEGAL` + `TODO` |
| 34 | DPIA (location + health + children = high risk) | — | — | `LEGAL` |

## 4. India: Digital Personal Data Protection Act, 2023 (DPDP) and DPDP Rules

Children = **under 18**. The DPDP Rules were notified in November 2025 with most obligations phasing in over roughly
18 months (confirm exact dates with counsel).

| Obligation | FamilyHub implementation | Status |
|---|---|---|
| Notice before/at consent: data collected, purpose, how to exercise rights, how to complain to the Data Protection Board | Privacy notice linked at signup; itemised in plain language | `LEGAL` |
| Notice available in English or any **Eighth Schedule language** at the user's option | App covers en + hi, bn, ta, te, mr, gu, kn, ml, pa; the privacy notice must be translated too | `LEGAL` |
| Free, specific, informed, unambiguous consent with clear affirmative action | Unticked consent checkbox (§3 row 1) | `SPEC` |
| Withdrawal of consent as easy as giving it | Delete account / leave family / location mode `never` | `SPEC` |
| **Verifiable parental consent** for children | Guardian consent by the admin parent when adding a minor (§3 row 3); self-registration gate (GAP-01) | `SPEC` + `GAP` |
| No tracking, behavioural monitoring or targeted ads directed at children | No ads/analytics; location sharing is the child's safety feature, **off by default**, visible, and SOS-only is recommended for minors | `SPEC` (review with counsel) |
| Rights: access (summary of data), correction, erasure, grievance redressal, nomination | Export, edit, delete; grievance contact; **nomination** (a person to exercise rights on death/incapacity) not built | `SPEC` + `TODO` (nomination) |
| Reasonable security safeguards (encryption, access control, logs, backups) | §3 rows 19–26; access logs retention per Rules | `SPEC` + `TODO` |
| Breach intimation to the **Data Protection Board and each affected person** (Rules: without delay, detailed report within 72 h) | Breach runbook §8 | `TODO` |
| Erase data when the purpose is served / on withdrawal | Deletion flows; retention schedule (GAP-03/04/10) | `SPEC` + `GAP` |
| Data processor contracts | DPAs (§2) | `LEGAL` |
| Cross-border transfer (allowed except to countries the government restricts) | Prefer an India database region for Indian families | `LEGAL` |
| Publish business contact of a person who answers privacy questions | About screen + privacy policy | `LEGAL` |

## 5. EU GDPR and UK GDPR (DE, ES, FR, IT, NL, PT, GB)

Age of digital consent per country (Art. 8): DE 16 · NL 16 · FR 15 · ES 14 · IT 14 · PT 13 · GB 13 (values in
`countries.dart`).

| Obligation | FamilyHub implementation | Status |
|---|---|---|
| Lawful basis per purpose: contract (account, family features), **explicit consent** for health data (Art. 9) and location | Consent checkbox covers terms/policy; emergency card screen explains health data before first save; location modes are explicit opt-in | `SPEC` + `LEGAL` (confirm bases) |
| Children (Art. 8): parental consent below the national age | Guardian consent (§3 row 3), self-registration gate (GAP-01) | `SPEC` + `GAP` |
| Transparency (Arts. 12–14) incl. for people added **by someone else** (managed profiles, emergency contacts, invitees) | Invitation email explains who added them and links the policy; emergency contacts are informed by the member (policy text) | `SPEC` + `LEGAL` |
| Access, rectification, erasure, portability (Arts. 15–17, 20) | `GET /me/export` (JSON, machine-readable), edit, `DELETE /me` | `SPEC` |
| Erasure "without undue delay" including processors | Cloudinary deletion (GAP-02); backups age out (GAP-10) | `GAP` |
| Privacy by design and by default (Art. 25) | Location off, invite code hidden from members, `lastLocation` hidden unless `always`, family isolation | `SPEC` |
| Records of processing (Art. 30) | §1 of this document is the starting point | `LEGAL` |
| Security (Art. 32) | §3 rows 19–26 | `SPEC` |
| Breach: supervisory authority within **72 h**; data subjects when high risk (Arts. 33–34) | §8 | `TODO` |
| DPIA (Art. 35): location + health + children | — | `LEGAL` |
| Processor contracts + international transfers (SCCs / adequacy) | §2 | `LEGAL` |
| EU / UK representative (Art. 27) if not established there | — | `LEGAL` |
| **UK Age Appropriate Design Code** (Children's Code): high-privacy defaults, geolocation off by default, **obvious sign to a child when location is tracked by a parent**, no nudging to lower privacy, age-appropriate explanations | Location `never` by default; tracking indicator; neutral wording in location settings; short child-friendly explanation on the location screen | `SPEC` + `TODO` (child-friendly copy) |
| ePrivacy (device storage): only strictly necessary storage | Tokens, settings and session cache only; no tracking | `SPEC` |

## 6. United States: COPPA (+ state laws)

Children = **under 13** for COPPA (US `consentAge` = 13). The amended COPPA Rule (2025) adds written security and
retention requirements; confirm the compliance date with counsel.

| Obligation | FamilyHub implementation | Status |
|---|---|---|
| Direct notice to parents + **verifiable parental consent** before collecting a child's personal information | Parent (admin) adds the child and confirms guardian consent; the child cannot self-register (GAP-01). Counsel to confirm the consent method is sufficient ("VPC" methods) | `SPEC` + `GAP` + `LEGAL` |
| Parents can review, delete, and refuse further collection | Admin can view/edit/remove the child's profile; export for managed profiles missing (GAP-08) | `SPEC` + `GAP` |
| Collect only what is reasonably necessary | Child profile: name, DOB, optional gender/avatar/phone | `SPEC` |
| Reasonable security + **written information security program** | §3 + security doc (TODO) | `TODO` |
| Written **data retention policy**; delete when no longer needed | GAP-03/04/10 | `GAP` |
| Separate consent before disclosing children's data to third parties | No third-party disclosure beyond processors | `SPEC` |
| Precise geolocation of a child is personal information | Off by default; only with the parent's knowledge; visible to the child | `SPEC` |
| State privacy laws (e.g. California CCPA/CPRA, others): notice at collection, access/delete, no sale/sharing, opt-in for minors' data sale | No sale/sharing; access/delete built | `SPEC` + `LEGAL` |
| Breach notification: state laws, deadlines vary by state | §8 | `TODO` |

## 7. Other countries in `countries.dart`

Baseline §3 covers most obligations. The table lists the extra points to check. Breach deadlines are commonly cited
values; **verify** before launch.

| Country | Law | Child / consent notes | Breach notification (verify) | Extra obligations to check |
|---|---|---|---|---|
| BR | LGPD | Children < 12: specific consent of a parent; adolescents: best interest | ANPD + data subjects, 3 working days (ANPD regulation) | DPO (encarregado) contact; international transfer clauses |
| CA | PIPEDA (+ Quebec Law 25, Alberta/BC PIPA) | Meaningful consent; Quebec < 14 parental consent | Privacy Commissioner + individuals "as soon as feasible" when real risk of significant harm; keep breach records 24 months | Privacy officer; Quebec: privacy impact assessment for transfers outside Quebec |
| AU | Privacy Act 1988 (APPs) | Capacity assessed case by case; Children's Online Privacy Code in development | Notifiable Data Breaches scheme: assess within 30 days, notify OAIC + individuals as soon as practicable | APP privacy policy; cross-border disclosure (APP 8) |
| NZ | Privacy Act 2020 | No fixed age | Privacy Commissioner + individuals as soon as practicable (serious harm) | Cross-border disclosure (IPP 12) |
| SG | PDPA | < 13: parental consent (PDPC guidance) | PDPC within 3 calendar days after assessing a notifiable breach | Data Protection Officer required |
| MY | PDPA 2010 (amended 2024) | Parental consent for minors | Commissioner within 72 h; individuals without undue delay | DPO appointment; data portability |
| LK | PDPA 2022 (phased) | Parental consent for children | Per Data Protection Authority rules | DPO; cross-border rules |
| ZA | POPIA | Child < 18: competent person (parent) consent | Information Regulator + data subjects as soon as reasonably possible | Register the Information Officer with the Regulator |
| NG | NDPA 2023 | Parental consent for children | NDPC within 72 h | DPO; registration if "data controller of major importance" |
| KE | Data Protection Act 2019 | Parental consent for children | ODPC within 72 h | Registration with ODPC (thresholds apply) |
| AE | UAE PDPL (Federal Decree-Law 45/2021) | Conservative 18 | Notify the Data Office on becoming aware (executive regulations) | Cross-border transfer rules; free-zone laws (DIFC, ADGM) differ |
| SA | PDPL | Guardian for those lacking capacity | SDAIA within 72 h | Registration with SDAIA; strict cross-border transfer rules (data residency) |
| QA | PDPPL (Law 13/2016) | Special protection for children's data | NCGAA guidance: 72 h | Children-related processing rules |
| ID | PDP Law (UU 27/2022) | Parental consent for children | Within 3 × 24 h to data subjects and the authority | DPO for large-scale monitoring |
| PH | Data Privacy Act 2012 | Minors: parental consent | NPC within 72 h | Registration with NPC above thresholds; DPO |
| MX | LFPDPPP (2025) | Parental consent for minors | Inform data subjects without delay | Privacy notice (aviso de privacidad) format |
| NP | Privacy Act 2018 | Parental consent for minors | Not clearly defined | Local counsel review |
| BD | Personal Data Protection Ordinance | Parental consent for children | Per new authority's rules | Data localisation provisions to check |
| PK | No comprehensive data protection law yet (PECA 2016 is a cybercrime law) | Conservative 18 | — | Track the pending Personal Data Protection Bill |

## 8. Breach response plan (draft runbook, `TODO`)

1. **Detect & record**: open an incident record (time found, reporter, systems, data types).
2. **Contain** (first hour):
   - Rotate `JWT_ACCESS_SECRET` → invalidates all access tokens immediately.
   - Revoke all refresh tokens (`revokeAllUserTokens` for affected users, or a bulk script for everyone). → `TODO`
     script `scripts/revoke-all-sessions.js`.
   - Rotate Cloudinary / SMTP / Firebase credentials if exposed.
   - If `FIELD_ENCRYPTION_KEY` is exposed: introduce an `enc:v2` key and re-encrypt emergency cards. → `TODO`
     script `scripts/rotate-field-key.js` (the `enc:v1:` prefix was designed for this).
3. **Assess** (within 24 h): which families, which data (health? location? children?), likelihood of harm.
4. **Notify** per the deadlines in §4–§7 (72 h is the most common; SG 3 days after assessment; BR 3 working days).
   Prepare templates for the regulator and for families in all 15 languages. → `TODO`
5. **Recover & learn**: fix the root cause, post-mortem, update this checklist.

Owner, on-call contact and regulator contact list: `LEGAL` / `TODO`.

## 9. Open gaps (need a decision)

| ID | Gap | Proposal | Needs change in |
|---|---|---|---|
| GAP-01 | A minor can self-register with an invite code (`mode: "join"`), bypassing guardian consent. | Backend rejects `join` registrations where age < `consentAge(family.country)` with `422 GUARDIAN_CONSENT_REQUIRED`, **unless** it links to an existing member pre-added by an admin with `guardianConsent: true` (same email). App shows "Ask your parent to add you first". | `03-API_CONTRACT.md` §4, auth service, register screen |
| GAP-02 | Avatars and notice images stay on Cloudinary after account/member/notice deletion. | On deletion, destroy Cloudinary assets by public id (URL → public id); family deletion removes the `familyhub/<familyId>` folder. | contract §5/§6/§9, `services/cloudinary.js` |
| GAP-03 | No retention rule for SOS alerts and trails. | Delete `trail` 30 days after an alert is resolved/expired; keep the alert summary 12 months (TTL or nightly job). | contract §10, SosAlert model |
| GAP-04 | `lastLocation` keeps the last value after a member switches away from `always`. | Clear `lastLocation` whenever `locationSharing` changes to `never` or `sos_only`. | contract §5, me service |
| GAP-05 | Changing the family country (consent age) or a member's DOB can create a minor without guardian consent. | On `PATCH /family` country change or `PATCH member` DOB change, require `guardianConsent` for affected members (return `422 GUARDIAN_CONSENT_REQUIRED` with the member ids in `details`). | contract §6 |
| GAP-06 | Guardian consent is not re-confirmed when a consenting admin leaves. | Keep the record (who/when) as evidence; no re-consent needed. Document in the policy. | Policy only |
| GAP-07 | Consent record has no policy version. | Store `consentVersion` and `consentLocale` on the user; bump the version when the policy changes and ask again. | contract §4, User model, register screen |
| GAP-08 | No export for managed profiles (children without accounts). | `GET /family/members/:id/export` (admin), same shape as `/me/export`. | contract §6 |
| GAP-09 | No audit log of admin actions on children's data. | Append-only `auditLogs` collection (who, what, when) for member edits/removals and guardian consent. Phase 2. | contract, new model |
| GAP-10 | Retention for backups and server logs is undefined. | Backups 30 days rolling; logs 30–90 days; document in the privacy policy. | Ops + policy |
| GAP-11 | No way for an admin to delete the whole family while other members exist. | `DELETE /family` (all admins must confirm, or owner + 7-day grace period). Phase 2. | contract §6 |
| GAP-12 | Emergency contacts (third parties) are entered without their knowledge. | Policy text + in-app hint "Let them know you added them". | Copy + policy |

When a gap is resolved, update the contract first, then set the related rows in §3 to `SPEC`.
