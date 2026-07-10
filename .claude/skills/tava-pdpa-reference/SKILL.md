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
SELECT anonymise_student('<student_uuid>');             -- redacts PII, KEEPS anonymous attendance rows
SELECT erase_student('<student_uuid>');                 -- hard delete + audit scrub (right to erasure)
```

All three are SECURITY DEFINER with an `is_admin()` guard. **Known gap:**
they delete result-slip **rows** but cannot delete Storage **objects**
(`result-slips` bucket, path `<student_id>/<file>`) — HUMANS.md §9. If you
build erasure UI, handle Storage from the app layer.

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
re-publish (HUMANS.md §7). On prod, run this via the prod-touch protocol in
`tava-run-and-operate` (Supabase MCP, SQL recorded):

```sql
UPDATE policy_documents SET is_current = false WHERE doc_type='data_protection_notice';
INSERT INTO policy_documents (doc_type, version, title, body)
VALUES ('data_protection_notice', '1.2', 'TAVA Attendance — Data Protection Notice', '<new text>');
```

iOS shows it localized (String Catalog, en + zh-Hans; notice term 数据保护声明).

## Rules when building anything that touches personal data

1. **Study-space attendance is internal-only** — never in any parent view or report (architecture invariant #1; SEC-16d fixed a parent policy that missed it).
2. New parent-visible surface? Check the notice's stated purposes cover it; if not, the notice needs a version bump + re-publish + fresh attestation consideration → flag to the human.
3. Exports of personal data must route through `export_student_personal_data` (it logs the disclosure). Don't hand-roll SELECT dumps.
4. Consent ledger is append-only; corrections table is the only correction path.
5. Photos (`student-photos` bucket) are personal data of minors: private bucket, signed URLs only, 5 MB client-side cap, admin-only write (on prod since 2026-07-09).
6. Web `PdpaPanel` (`web/app/(admin)/students/[id]/pdpa-panel.tsx`) is the built-but-unwired admin UI for consent/erasure/export — decision pending (HUMANS.md §29). Don't delete it; don't wire it without that decision.

## What is still legally OPEN (don't claim compliance)

DPO appointment (§1), legal sign-off on the three governance docs (§2),
consent-wording validation for minors (§3), leaked-password protection toggle
(§4), Singapore data-residency verification (§5), Supabase DPA signature
(§6), breach-plan alerting (§10/§11). The honest status line is: "technical
controls in place; legal formalisation pending."

## Provenance and maintenance

Current as of 2026-07-09 (notice v1.1 DRAFT; gap analysis in
`PDPA_COMPLIANCE.md`, audited 2026-06-15).
- Current notice version: `SELECT version, is_current FROM policy_documents WHERE doc_type='data_protection_notice';`
- Purge job alive: `SELECT * FROM cron.job WHERE jobname='pdpa-daily-purge';`
- Open legal items: `grep '^### ☐' HUMANS.md | head -8`
