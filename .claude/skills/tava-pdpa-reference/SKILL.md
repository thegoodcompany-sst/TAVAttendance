---
name: tava-pdpa-reference
description: Use when touching any personal data in TAVA — students, parents, photos, consent, exports, deletion/erasure, retention, the privacy notice, or anything a parent could see. Explains Singapore PDPA as implemented HERE — consent model, the erase/anonymise/export RPCs, policy_documents versioning, retention purge — and what is still legally open.
---

# TAVA PDPA Reference

TAVA handles children's personal data in Singapore, governed by the Personal
Data Protection Act (PDPA). The technical controls are built; several legal
steps remain human-gated. This skill = the implemented machinery + the rules
you must not break.

**When NOT to use this skill:** general Postgres/RLS mechanics (use
`tava-supabase-reference`); the human/legal task list itself lives in
HUMANS.md §A (don't duplicate it, update it).

## PDPA in one paragraph (as it applies here)

Organisations may collect/use/disclose personal data only with consent and
for notified purposes, must protect it, keep it no longer than needed, allow
access/correction, and report significant breaches. Students are minors →
consent comes from parents/guardians. TAVA's data controller is **Talent
Beacon** (contact in the notice); a Data Protection Officer (DPO) is legally
required but **not yet appointed** (HUMANS.md §1).

## The implemented machinery (migration 011 + docs/pdpa/)

Frozen contract: `docs/pdpa/IMPLEMENTATION_CONTRACT.md`. Key objects:

| Object | What it is |
|---|---|
| `policy_documents` | Versioned privacy-notice text shown in-app (`doc_type='data_protection_notice'`, `is_current=true`). Currently v1.1. Any authed user reads; admin writes. |
| `consent_records` | **Append-only** consent ledger. Never UPDATE a row — withdrawal = INSERT a new row with `status:'withdrawn'`. |
| `current_consent` (view) | Latest row per `(student_id, consent_type)`. |
| `correction_requests` | PDPA access/correction requests. Parent creates/reads own child; admin full. |
| `data_disclosures` | Log of exports/SAR fulfilments. Admin only. Auto-appended by the export RPC. |
| `rate_limit_events` | Backs the invite rate limiter; service-role only (RLS on, zero policies — intentional). |

### The three admin-guarded RPCs

```sql
SELECT export_student_personal_data('<student_uuid>');  -- jsonb bundle; auto-logs a data_disclosures row
SELECT anonymise_student('<student_uuid>');             -- rotates identifiers, keeps pseudonymised attendance
SELECT erase_student('<student_uuid>');                 -- hard delete + audit scrub (right to erasure)
```

Migration 038 makes caller checks explicit and routes anonymise/erase through
the trusted web service-role workflow rather than native direct execution.
Database erasure also enqueues durable cleanup for both private buckets. The
remaining production gate is Edge deployment, a dedicated Vault secret,
cron/alert activation and drain verification (HUMANS.md §65).

### Consent model (agreed, do not redesign)

**Admin attestation only.** The Centre collects signed parent consent on
paper at enrolment; an admin ticks "Parent/guardian consent obtained" when
creating/importing the student, which inserts:

```json
{ "student_id": "...", "consent_type": "data_collection", "status": "granted",
  "method": "admin_attestation", "notice_version": "<current policy version>",
  "granted_by": "<admin uid>" }
```

Student creation/import is **blocked if unticked**. A future
`method:'parent_in_app'` path is anticipated — build UI extensible to it, but
do NOT build parent-facing consent now (explicit decision: parents barely use
the app).

### Retention

`pg_cron` job `pdpa-daily-purge` (18:20 daily) calls
`purge_expired_personal_data()`. Retention period is 7 years (draft, pending
counsel sign-off — see `docs/pdpa/DATA_RETENTION_SCHEDULE.md`). `students`
has `deactivated_at`; `enrollments.unenrolled_at` is auto-stamped — these
start the retention clocks.

### The notice

Source of truth: `docs/pdpa/DATA_PROTECTION_NOTICE.md` (DRAFT v1.1 — DPO name
is a placeholder). The app renders whatever `policy_documents` row has
`is_current=true`. **Editing the doc does nothing in-app** until you
re-publish (HUMANS.md §7). In production, use only the reviewed prod-touch
protocol in `tava-run-and-operate`:

```sql
UPDATE policy_documents SET is_current = false WHERE doc_type='data_protection_notice';
INSERT INTO policy_documents (doc_type, version, title, body)
VALUES ('data_protection_notice', '1.2', 'TAVA Attendance — Data Protection Notice', '<new text>');
```

iOS shows it localized (String Catalog, en + zh-Hans; notice term 数据保护声明).

## Rules when building anything that touches personal data

1. **Study-space attendance is internal-only** — never in any parent view or report (architecture invariant #1; SEC-16d fixed a parent policy that missed it).
2. New parent-visible surface? Check the notice's stated purposes cover it; if not, the notice needs a version bump + re-publish + fresh attestation consideration → flag to the human.
3. Per-student subject-access exports route through
   `export_student_personal_data` and log the disclosure. The separate
   superadmin operational export remains a highly sensitive controlled export.
4. Consent ledger is append-only; corrections table is the only correction path.
5. Photos/result slips are private minor data: use only signed
   intent/finalisation/download workflows with server-side boundaries.
6. Web `PdpaPanel` is wired. Native erasure/anonymisation controls intentionally
   fail closed to the trusted web workflow.
7. Retained attendance after anonymisation is **pseudonymised**, not guaranteed
   anonymous; HUMANS.md §69 requires purpose/retention approval.

## What is still legally OPEN (don't claim compliance)

DPO/contact (§46), governance-doc sign-off (§47), consent wording and rollout
(§§48–50), leaked-password decision (§51), cleanup activation (§65),
credential rotation (§66), MFA (§62), and pseudonymised-retention approval
(§69). Honest status: "technical controls implemented in the repository;
production verification and legal formalisation remain."

## Provenance and maintenance

Audited 2026-07-26 (notice v1.1 remains DRAFT).
- Current notice version: `SELECT version, is_current FROM policy_documents WHERE doc_type='data_protection_notice';`
- Purge job alive: `SELECT * FROM cron.job WHERE jobname='pdpa-daily-purge';`
- Open legal items: `rg '^### [☐◐]' HUMANS.md`
