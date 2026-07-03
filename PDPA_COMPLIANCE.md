# TAVA Attendance — Singapore PDPA Gap Analysis

**Date:** 2026-06-15
**Scope:** Whole codebase (iOS, Android, web) + Supabase schema/RLS, assessed against the Personal Data Protection Act 2012 (PDPA), as amended (incl. the mandatory Data Breach Notification regime in force since 1 Feb 2021).
**Reference:** https://sso.agc.gov.sg/Act/PDPA2012

> ⚠️ **Not legal advice.** This is an engineering gap analysis to help the centre and its appointed Data Protection Officer (DPO) prioritise work. Final compliance positions (especially consent for minors, retention periods, and the data-protection notice wording) should be confirmed with a qualified Singapore privacy lawyer / the PDPC guidelines.

---

## 1. Why this app is squarely in PDPA scope

The platform is operated by an organisation (a tuition centre) and collects, uses, stores and discloses **personal data** about identifiable individuals in Singapore. It therefore attracts the full set of Data Protection Provisions (Parts 3–6B of the Act).

**Critically, the primary data subjects are minors.** Most "students" are school-age children (`year_of_study` values like *"Sec 2"*, *"JC1"*). The PDPC's *Advisory Guidelines on the PDPA for NRIC and other National Identification Numbers* and the guidance on minors mean consent generally must be obtained from a **parent/legal guardian** for younger children, and data minimisation expectations are heightened. This raises the baseline for nearly every obligation below.

### Personal data inventory (what is held, and where)

| Data | Personal data? | Location | Sensitivity |
|---|---|---|---|
| Student full name, date of birth, school, year of study | Yes (minors) | `students` (`001_schema.sql:39-52`) | High (children) |
| Free-text `students.notes` | Potentially sensitive (could contain medical/behavioural/NRIC) | `students.notes` | High — uncontrolled |
| Parent / tutor / admin name, phone | Yes | `profiles` (`001_schema.sql:13-20`) | Medium |
| Parent ↔ child relationship | Yes | `parent_student_links` | Medium |
| Attendance records, late reasons, notes | Yes (behavioural data on minors) | `attendance_records`, `sessions.notes` | Medium–High |
| Exam result slips (scores + uploaded files) | Yes (educational records on minors) | `result_slips` + Storage `result-slips` | High |
| Pick-up / "safely home" tracking | Yes (location/safeguarding of minors) | `dismissals` | High |
| Direct messages | Yes (free-text content) | `messages` | Medium |
| Food poll responses (can imply dietary/health) | Potentially sensitive | `food_poll_responses` | Medium |
| Full row snapshots of all the above, kept forever | Yes — copies of all PII | `audit_log.old_data` / `new_data` (JSONB) | High |
| Pending attendance cached on device | Yes | iOS `PendingAttendanceStore` (UserDefaults) | Medium |

---

## 2. What is already in good shape

The recent security hardening covers much of the **Protection Obligation (s24)**:

- **Row-Level Security** across all tables with role-scoped policies (`002_rls.sql`). Parents see only their children; tutors only their assigned classes.
- **Profile reads correctly scoped** — the earlier "any authenticated user can read all profiles" hole was closed in `004_security_fixes.sql:30-35` (`read own or admin`). ✅ (No action needed; previously a real cross-tenant leak.)
- **Encryption** at rest (AES-256) and in transit (TLS) via Supabase; **SG region** intended for data residency (`supabase/README.md`).
- **Hashed kiosk PIN** (`v1:` prefix), credentials moved out of source into gitignored config, `search_path` pinned on all functions, audit triggers on key tables (`010_audit_fixes.sql`).
- **Audit trail** exists (`audit_log`) — a useful foundation for breach investigation and the access obligation.

These materially reduce s24 risk. The gaps below are mostly in the **rights, governance, and lifecycle** obligations, which the codebase does not address at all.

---

## 3. Findings by PDPA obligation

Severity: **HIGH** = likely non-compliant, act first · **MEDIUM** = gap with real exposure · **LOW** = hygiene/verification.
Many HIGH items are *procedural* (a policy/notice/process), not code — but they are the cheapest, highest-impact fixes.

### 3.1 Notification Obligation — s20  ·  **HIGH**

**PDPA-N1 (HIGH):** There is **no data-protection notice / privacy policy anywhere** in any of the three apps or the web dashboard. A repo-wide search for `privacy|consent|pdpa|data protection` returns only two README lines. The Act requires that individuals be informed of the **purposes** for which their data is collected, used and disclosed, on or before collection.
→ *Publish a Data Protection Notice; surface it at every collection point (web sign-in/onboarding, kiosk, parent app) and link it from a persistent "Privacy" entry.*

### 3.2 Consent Obligation — s13–17  ·  **HIGH**

**PDPA-C1 (HIGH):** **No consent is captured at any collection point.** Students are created via manual entry and **bulk CSV import** (`iOS/.../Views/Admin/StudentImportView.swift`) with no record that the parent/guardian consented to the centre holding the child's data. For minors, consent must generally come from a parent/guardian. There is no `consent` table, timestamp, version, or proof.
→ *Add a consent capture + ledger (who consented, for what purpose, when, which notice version). For bulk import, require attestation that consent was obtained offline, and store it.*

**PDPA-C2 (MEDIUM):** **No withdrawal-of-consent mechanism (s16).** Individuals must be able to withdraw consent, and the organisation must then stop collecting/using/disclosing (subject to legal retention). There is no UI or backend path for this.

**PDPA-C3 (LOW):** If any phone/email is later used for class reminders or marketing, the **Do Not Call** provisions and separate marketing consent apply. Not currently triggered (no outbound messaging implemented), but design messaging features (`messages` table) with this in mind.

### 3.3 Purpose Limitation Obligation — s18  ·  **MEDIUM**

**PDPA-P1 (MEDIUM):** Free-text fields (`students.notes`, `sessions.notes`, `attendance_records.notes`) are unconstrained. `supabase/README.md` *advises* against storing NRIC but nothing enforces it, and staff can paste medical/behavioural/identifier data that exceeds the collection purpose. Collecting more than is reasonably needed breaches data minimisation.
→ *Add field guidance/validation, a "no NRIC / no sensitive identifiers" warning at input, and consider lightweight server-side pattern detection for NRIC-like strings.*

### 3.4 Access & Correction Obligation — s21–22  ·  **MEDIUM**

**PDPA-A1 (MEDIUM):** **No correction workflow.** Parents have *read-only* RLS on their children (`002_rls.sql`); they cannot request or make corrections, and there is no admin-facing correction-request queue. The Act requires correcting errors/omissions on request.

**PDPA-A2 (MEDIUM):** **No data-access (subject access request) export.** There is an admin CSV *attendance* export (`ExportView.swift`) but no way to produce *all personal data held about one individual* on request, as s21 contemplates.

**PDPA-A3 (LOW):** Access requests must, on request, also reveal **to whom** data was disclosed in the past year. `audit_log` captures `changed_by` but there is no disclosure log or report.

### 3.5 Accuracy Obligation — s23  ·  **LOW**

**PDPA-AC1 (LOW):** `date_of_birth`, `school`, `year_of_study` are free-text with no validation, and offline sync has documented clock-skew caveats (`CLAUDE.md`, MAINT/QA findings). Low risk, but accuracy of children's records should be reasonably assured before being used in decisions.

### 3.6 Protection Obligation — s24  ·  **MEDIUM** (mostly addressed)

**PDPA-PR1 (MEDIUM):** **`result-slips` Storage bucket is never created and its access policy is undefined** (carryover SEC-07; `AttendanceService.swift` `uploadResultSlip`). Exam results are personal data about minors; an unconfigured or public bucket would be a serious disclosure risk. *Create the bucket private, add Storage RLS scoped like the table.*

**PDPA-PR2 (MEDIUM):** **Leaked-password protection (HaveIBeenPwned) is still disabled** (Supabase Auth dashboard toggle; see memory `project_security_posture`). Weak admin credentials guard access to all children's data.

**PDPA-PR3 (LOW):** **No rate limiting on the invite action** (carryover SEC-09; `web/app/actions/invite.ts`) — a compromised admin could enumerate emails.

**PDPA-PR4 (LOW):** Phase 2/3 tables (`messages`, `result_slips`, `dismissals`, …) are currently admin-only by RLS — fine for now, but **must get correctly-scoped parent/tutor policies before those features ship**, or they will either break or over-expose.

### 3.7 Retention Limitation Obligation — s25  ·  **HIGH**

**PDPA-R1 (HIGH):** **No retention policy and no deletion/anonymisation of personal data, ever.** Students are only *soft-deleted* (`is_active = false`); `unenrolled_at` is never even populated (MAINT-04). There is **no hard-delete or anonymisation path** for a child's PII once they leave the centre. Data must not be kept "longer than is necessary."
→ *Define retention periods per data class; build a purge/anonymisation job and an admin "erase student" action.*

**PDPA-R2 (HIGH):** **`audit_log` retains full PII snapshots indefinitely.** `audit_trigger_func` writes `to_jsonb(OLD)`/`to_jsonb(NEW)` for students, attendance, profiles, classes, enrollments (`003_functions_triggers.sql:10-27`, `010_audit_fixes.sql`). Even if a student row is deleted, **a complete copy of their personal data survives forever in `audit_log`**, defeating any retention/erasure. *Add audit-log retention (e.g. time-boxed purge) and ensure erasure also scrubs audit snapshots, balanced against legitimate audit needs.*

**PDPA-R3 (LOW):** `PendingAttendanceStore` persists pending records in plaintext `UserDefaults` on device with no TTL beyond successful sync. Minor, but device-side PII should be cleared promptly and ideally not stored in `UserDefaults`.

### 3.8 Transfer Limitation Obligation — s26  ·  **LOW** (verify)

**PDPA-T1 (LOW):** Data residency in **Singapore (ap-southeast-1)** is *documented as intended* (`supabase/README.md`) but is an account/project setting, not enforced by code. *Verify the live Supabase project region and any read-replica/backup region; document it.*

**PDPA-T2 (LOW):** Supabase (on AWS) is a **data intermediary / sub-processor**. The centre needs a Data Processing Agreement and assurance of comparable protection for any data processed/stored. *Record this in the accountability documentation.*

### 3.9 Data Breach Notification Obligation — s26A–26E  ·  **HIGH** (procedural)

**PDPA-B1 (HIGH):** **No breach detection, alerting, or response plan.** Since 1 Feb 2021, notifiable breaches (significant scale ≥ 500 individuals, or significant harm — which a children's-data leak would likely be) must be reported to the PDPC (and affected individuals) without undue delay. The `audit_log` is a good forensic base but there is no monitoring, no documented runbook, and no contact/escalation path.
→ *Write a Data Breach Response Plan (assessment criteria, 72-hour-class timelines, PDPC + parent notification templates), and add basic anomaly alerting.*

### 3.10 Accountability Obligation — s11–12 (incl. DPO s11(3))  ·  **HIGH** (procedural)

**PDPA-G1 (HIGH):** **No Data Protection Officer designated and no published DPO business contact**, which is a baseline statutory requirement. No internal data-protection policies/practices are documented in the repo.
→ *Appoint a DPO, publish the contact in the notice, and document internal handling policies (the deliverables in §4 largely satisfy this).*

---

## 4. Prioritised remediation roadmap

**Tier 0 — Governance (days, no/low code; clears 3 HIGH procedural gaps)**
1. Appoint & publish a **DPO** contact (PDPA-G1).
2. Draft & publish a **Data Protection Notice / privacy policy** covering purposes, retention, contact, minors' parental consent (PDPA-N1).
3. Write a **Data Breach Response Plan** (PDPA-B1) and a **Retention Schedule** (feeds R1/R2).
4. Verify Supabase **region** and record the sub-processor/DPA (PDPA-T1, T2).
5. Flip on **leaked-password protection** in Supabase Auth (PDPA-PR2).

**Tier 1 — Highest-risk code (weeks)**
6. **Consent capture + ledger** at all collection points incl. bulk import, with minors/parental-consent model (PDPA-C1) and **withdrawal** path (PDPA-C2).
7. **Retention/erasure**: per-class retention, a purge/anonymisation job, an admin "erase student" action, and **audit-log retention** so erasure is real (PDPA-R1, R2).
8. **Lock down `result-slips` Storage** as a private bucket with scoped policies before the feature ships (PDPA-PR1).

**Tier 2 — Rights & minimisation (weeks)**
9. **Subject access export** (all data about one individual) + **correction-request workflow** for parents (PDPA-A1, A2, A3).
10. **Input minimisation**: NRIC/sensitive-data warnings & validation on free-text notes (PDPA-P1).
11. Correctly-scoped RLS for Phase 2/3 tables before launch; device-side PII hygiene; invite rate-limit; accuracy validation (PDPA-PR3, PR4, R3, AC1).

---

## 4b. Remediation status (2026-06-15)

Implementation was carried out after this audit. Current state:

- **Backend (done & applied to live DB):** migration `011_pdpa_compliance.sql` — consent ledger, policy-document store (notice seeded), retention stamping + `anonymise_student`/`erase_student`/`purge_expired_personal_data` (daily pg_cron job active), audit-log scrub/purge, NRIC-in-notes rejection, subject-access export + disclosure log, correction-requests table, `result-slips` private bucket + scoped storage RLS, parent-read RLS for Phase 2/3 tables, and `rate_limit_events`. Advisors clean except intentional items (see `HUMANS.md`).
- **Apps (built & compiling):** iOS, Android and web each implement the app-layer UI against `docs/pdpa/IMPLEMENTATION_CONTRACT.md` (privacy-notice screen, consent attestation gate, view/withdraw, erase/anonymise, subject-access export, correction queue, NRIC warnings, result-slip path; + invite rate-limit on web; + device-cache hygiene on mobile). **Compile-verified 2026-06-15:** web `tsc --noEmit` clean, Android `clean compileDebugKotlin` SUCCESSFUL, iOS `xcodebuild` BUILD SUCCEEDED. Not yet runtime/QA-tested.
- **Governance (drafted, need sign-off):** `docs/pdpa/DATA_PROTECTION_NOTICE.md`, `DATA_RETENTION_SCHEDULE.md`, `DATA_BREACH_RESPONSE_PLAN.md`.
- **Human-only (open):** appoint DPO, legal sign-off, leaked-password toggle, region/DPA verification — tracked in **`HUMANS.md`**.

| Finding | Status |
|---|---|
| N1 notice | Backend store + draft done; needs DPO contact + sign-off (HUMANS §A1/A2) |
| C1/C2 consent | Backend done; app gates in progress |
| P1 minimisation | NRIC rejection live; app warnings in progress |
| A1/A2/A3 access & correction | Backend done; app UI in progress |
| AC1 accuracy | Open (low) — input validation in app pass |
| PR1 result-slips bucket | Done (private + scoped) |
| PR2 leaked-password | Open — human toggle (HUMANS §A4) |
| PR3 invite rate-limit | Backend table done; web wiring in progress |
| PR4 Phase 2/3 RLS | Done (parent-read baseline added) |
| R1/R2 retention/erasure | Done (jobs + cron + audit scrub) |
| R3 device cache | Mobile hygiene in progress |
| T1/T2 transfer | Open — human verify (HUMANS §A5/A6) |
| B1 breach plan | Drafted; needs ownership (HUMANS §A2) |
| G1 accountability/DPO | Open — human (HUMANS §A1) |

## 5. Finding index

| ID | Obligation | Severity | One-line |
|---|---|---|---|
| PDPA-N1 | Notification (s20) | HIGH | No privacy notice anywhere |
| PDPA-C1 | Consent (s13–17) | HIGH | No consent captured (esp. minors / bulk import) |
| PDPA-C2 | Consent (s16) | MEDIUM | No consent-withdrawal path |
| PDPA-C3 | Consent / DNC | LOW | Plan messaging features for marketing consent/DNC |
| PDPA-P1 | Purpose Limitation (s18) | MEDIUM | Unconstrained free-text notes (NRIC/sensitive risk) |
| PDPA-A1 | Access & Correction (s22) | MEDIUM | No correction workflow |
| PDPA-A2 | Access (s21) | MEDIUM | No per-individual data-access export |
| PDPA-A3 | Access (s21) | LOW | No disclosure log/report |
| PDPA-AC1 | Accuracy (s23) | LOW | No validation on DOB/school; clock-skew |
| PDPA-PR1 | Protection (s24) | MEDIUM | `result-slips` bucket uncreated/unscoped |
| PDPA-PR2 | Protection (s24) | MEDIUM | Leaked-password protection disabled |
| PDPA-PR3 | Protection (s24) | LOW | No invite rate limiting |
| PDPA-PR4 | Protection (s24) | LOW | Phase 2/3 RLS not yet parent/tutor-scoped |
| PDPA-R1 | Retention (s25) | HIGH | No retention policy / no erasure of student PII |
| PDPA-R2 | Retention (s25) | HIGH | `audit_log` keeps PII snapshots forever |
| PDPA-R3 | Retention (s25) | LOW | Device-cached PII in plaintext UserDefaults |
| PDPA-T1 | Transfer (s26) | LOW | Verify SG region in live project |
| PDPA-T2 | Transfer (s26) | LOW | Document Supabase sub-processor/DPA |
| PDPA-B1 | Breach Notification (s26A–E) | HIGH | No breach detection/response plan |
| PDPA-G1 | Accountability (s11–12) | HIGH | No DPO / no documented policies |

---

*Generated as an engineering gap analysis. Confirm legal positions with the centre's DPO / Singapore privacy counsel before relying on it.*
