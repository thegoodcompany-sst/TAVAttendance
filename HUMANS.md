# HUMANS.md — actions only a human can complete

Some PDPA (and related) compliance steps cannot be done in code or by an agent. They need a
person with organisational authority, legal judgement, or access to dashboards/contracts.
**The technical controls are in place; these items make the compliance real and lawful.**

Tracking key: ☐ = to do · ☑ = done. Owner: the Centre's Data Protection Officer unless noted.

---

## A. Must-do for PDPA compliance

### ☐ 1. Appoint a Data Protection Officer (DPO) — *s11(3), mandatory*
Designate a DPO and **publish a business contact** (name/role + email/phone). Then fill it into:
- `docs/pdpa/DATA_PROTECTION_NOTICE.md` (the "Data Protection Officer" line), and
- the in-app notice: update the `policy_documents` row (see §B for how to re-publish).

### ☐ 2. Legal/DPO sign-off on the governance documents
Review and approve, then mark as published (remove "DRAFT"):
- `docs/pdpa/DATA_PROTECTION_NOTICE.md`
- `docs/pdpa/DATA_RETENTION_SCHEDULE.md`
- `docs/pdpa/DATA_BREACH_RESPONSE_PLAN.md`
The 7-year retention period and the consent-for-minors approach in particular should be confirmed
with counsel.

### ☐ 3. Confirm the consent wording is legally valid for minors
We record parent/guardian consent by **admin attestation** (the Centre collects consent offline at
enrolment and an admin attests in-app). Confirm the **paper/portal consent form** parents sign
covers all purposes in the notice, and keep those signed forms on file.

### ☐ 4. Enable leaked-password protection (Supabase dashboard)
Auth → Providers → Password → enable "Leaked password protection" (HaveIBeenPwned).
*Cannot be set via SQL/MCP.* (Advisor: `auth_leaked_password_protection`.)

### ☐ 5. Verify data residency (region)
Confirm the **live Supabase project region is Singapore (ap-southeast-1)** and that backups/replicas
do not leave Singapore. Dashboard → Project Settings → General/Infrastructure.

### ☐ 6. Sign the Supabase Data Processing Addendum (DPA)
Supabase is a data intermediary. Execute their DPA and record it in the accountability file.
(Reference: https://supabase.com/legal/dpa)

---

## B. Operational follow-ups

### ☐ 7. Re-publish the in-app notice after edits
The app shows the notice from the `policy_documents` table. After editing the source doc, publish a
new version:
```sql
UPDATE policy_documents SET is_current = false WHERE doc_type='data_protection_notice';
INSERT INTO policy_documents (doc_type, version, title, body)
VALUES ('data_protection_notice', '1.1', 'TAVA Attendance — Data Protection Notice', '<new text>');
```

### ☑ 8. Retention purge job (pg_cron) — DONE
`pg_cron` was enabled and the daily job `pdpa-daily-purge` (18:20) is scheduled and active. Verify:
```sql
SELECT * FROM cron.job WHERE jobname='pdpa-daily-purge';
SELECT purge_expired_personal_data();  -- safe to run manually; returns counts
```
If the project is ever restored/migrated and pg_cron is missing, re-run `011_pdpa_compliance.sql`
or schedule the job manually.

### ☐ 9. Result-slip Storage object cleanup
`erase_student` / `anonymise_student` delete result-slip **rows**, but Storage **objects** under the
`result-slips` bucket are not deleted from SQL. Either delete objects from the app at erasure time,
or run a periodic Storage cleanup of orphaned objects (path convention: `<student_id>/<file>`).

### ☐ 10. Turn on Supabase log/security alerting
Enable log drains/alerts and review `get_advisors` (security + performance) regularly — this backs
the Data Breach Response Plan's detection step.

### ☐ 11. Maintain the breach register
Keep `docs/pdpa/DATA_BREACH_RESPONSE_PLAN.md`'s register up to date; review the plan annually.

---

## Notes
- Accepted/intentional advisor warnings: the `is_admin()/is_parent()/...` and the new
  `anonymise_student/erase_student/export_student_personal_data` SECURITY DEFINER functions are
  callable by `authenticated` **by design** — each guards with `is_admin()` (or is required by RLS).
  `rate_limit_events` has RLS on with no policy **by design** (service-role only).
- Anon key remains in old git history (`build.gradle.kts`, old `SupabaseConfig.kt`); the anon key is
  public-by-design, but rotate it via the dashboard if this repo ever goes public.
