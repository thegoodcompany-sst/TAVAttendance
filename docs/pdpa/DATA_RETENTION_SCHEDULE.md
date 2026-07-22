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
| Student profile (name, DOB, school, notes) | 7 years after leaving | Auto-pseudonymised by scheduled job, subject to DPO approval |
| Attendance records | Session-linked facts retained under a rotated pseudonymous identity after the 7-year point | Notes/actors stripped; still treat as potentially personal data in small cohorts |
| Exam result slips and student photos | Deleted on explicit or scheduled erasure | Migration 038 queues every prefix; the trusted web flow sweeps immediately and `cleanup-student-storage` retries scheduled work; expired signed-upload intents/abandoned objects are also removed; see HUMANS.md §9 |
| Consent records | Deleted with the student record | Cascade / pseudonymise |
| Correction requests | Deleted with the student record | Cascade / pseudonymise |
| Audit log (`audit_log`) | 7 years, then purged | Scheduled job + erasure scrub |
| Pending attendance cache (device) | Cleared immediately after successful sync | App-side store cleanup |

## How it is enforced (technical)
- "Left the Centre" = `students.is_active = false` with no active enrolment; the date is taken from
  `students.deactivated_at` (auto-stamped) or the latest `enrollments.unenrolled_at`.
- `purge_expired_personal_data()` runs **daily at 18:20** via pg_cron job `pdpa-daily-purge`. It:
  - pseudonymises students whose leaving date is > 7 years ago (via the legacy-named `_anonymise_student`), and
  - deletes `audit_log` rows older than 7 years.
- **On-demand erasure** (e.g. a valid erasure request): the trusted web action
  sweeps both private buckets, invokes a service-role-only database wrapper,
  and sweeps again after upload authorization has disappeared. Native clients
  direct administrators to this workflow.
- Pseudonymisation rotates the student and attendance identifiers, retains an
  inactive `Redacted Student` identity and session-level attendance chronology,
  nulls profile/free-text/actor data, deletes linked operational rows, and
  scrubs PII from `audit_log`. It is not guaranteed anonymous; use hard erasure
  when the approved outcome requires removal of reasonably linkable history.
- Every database path first writes `student_storage_cleanup_queue`. The
  `cleanup-student-storage` Edge worker recursively deletes private objects and
  removes the queue row only after both prefixes are empty.
- Parent result uploads have a durable, two-hour-fifteen-minute intent. The
  worker lease-claims expired intents, deletes the exact object path, then
  removes the intent; atomic finalization wins the same lock and consumes live
  intents so cleanup cannot create a dangling result row.

## Operational notes
- Verify both cron jobs are active: `pdpa-daily-purge` and
  `student-storage-cleanup`. Alert on cleanup-queue rows and expired upload
  intents older than 30 minutes
  (HUMANS.md §9).
- Review this schedule annually with the DPO.

_Last updated: 2026-07-21 (draft; pseudonymisation wording requires DPO sign-off)._
