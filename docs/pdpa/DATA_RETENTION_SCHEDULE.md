# TAVA Attendance — Data Retention Schedule

> **DRAFT — requires DPO sign-off.** Implements the PDPA Retention Limitation Obligation (s25).

## Policy
Personal data is retained only as long as necessary for the purposes in the Data Protection Notice
and to satisfy legal record-keeping obligations. The Centre's retention period for student-related
personal data is **7 years after the student leaves** (no active enrolment), aligned with the
general 7-year business/financial record-keeping expectation in Singapore (IRAS / Companies Act).

## Retention by data class

| Data | Retention | Mechanism |
|---|---|---|
| Student profile (name, DOB, school, notes) | 7 years after leaving | Auto-anonymised by scheduled job |
| Attendance records | Retained as **anonymous** statistics after the 7-year point | Notes stripped; student row redacted; counts preserved |
| Exam result slips (+ files) | Deleted at the 7-year point (or on erasure request) | `anonymise_student` / `erase_student` |
| Consent records | Deleted with the student record | Cascade / anonymise |
| Correction requests | Deleted with the student record | Cascade / anonymise |
| Audit log (`audit_log`) | 7 years, then purged | Scheduled job + erasure scrub |
| Pending attendance cache (device) | Cleared immediately after successful sync | App-side store cleanup |

## How it is enforced (technical)
- "Left the Centre" = `students.is_active = false` with no active enrolment; the date is taken from
  `students.deactivated_at` (auto-stamped) or the latest `enrollments.unenrolled_at`.
- `purge_expired_personal_data()` runs **daily at 18:20** via pg_cron job `pdpa-daily-purge`. It:
  - anonymises students whose leaving date is > 7 years ago (via `_anonymise_student`), and
  - deletes `audit_log` rows older than 7 years.
- **On-demand erasure** (e.g. a valid erasure request): an admin uses the in-app "Erase student"
  action → `erase_student()` (hard delete + audit scrub) or "Anonymise" → `anonymise_student()`.
- Anonymisation redacts `full_name` to `'Redacted Student'`, nulls DOB/school/year/notes, strips
  attendance notes, deletes result slips/consent/correction rows, and scrubs the student's PII from
  `audit_log`. Audit suppression (`app.suppress_audit`) prevents re-writing PII during the operation.

## Operational notes
- Verify the cron job is active: `SELECT * FROM cron.job WHERE jobname='pdpa-daily-purge';`
- Storage objects for result slips are deleted at the DB row level; if Storage objects can be
  orphaned, schedule a Storage cleanup (see HUMANS.md).
- Review this schedule annually with the DPO.

_Last updated: 2026-06-15 (draft)._
