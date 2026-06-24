# TAVA Attendance — Improvement Findings

Multi-perspective audit. Perspectives repeated until no new findings could be produced.

> **2026-06-15:** First wave implemented and removed (see `010_audit_fixes.sql`).
>
> **2026-06-24:** Second wave implemented. Fixes landed in
> `supabase/migrations/012_feature_flags.sql`, `013_audit_fixes.sql`,
> `014_feature_tables.sql` (+ down scripts), the `notify-parent` edge function, and
> across iOS / Android / web. The four large roadmap items (parent portal, push
> notifications, student photos) ship behind **`feature_flags`** rows that default
> OFF. Closed this wave:
> SEC-05, SEC-07 (bucket already existed; docs added), PERF-04, PERF-06, PERF-07,
> MAINT-04, MAINT-05, MAINT-06, MAINT-07, MAINT-09, MAINT-11, MAINT-13, QA-04, QA-05,
> QA-06, QA-08, UX-01, UX-02, UX-03, UX-04, UX-06, UX-07, A11Y-02, A11Y-05,
> CONTRIB-01, CONTRIB-02, CONTRIB-03, CONTRIB-04, CONTRIB-05, DOC-01, DOC-02, DOC-03,
> DOC-04, DOC-05, PROD-01, PROD-02, PROD-03, PROD-04, PROD-05, DEVOPS-01, DEVOPS-02,
> DEVOPS-03, DEVOPS-04, SP-02, SP-08, SP-09, SP-10.
>
> Already resolved before this wave: SEC-09 (invite rate limit), DEVOPS-05
> (`[auth]` present in `config.toml`).

---

## Remaining / informational

### SP-01 `class_tutor_assignments` tutor-read policy anticipates an unbuilt feature (LATENT)
**File:** `supabase/migrations/002_rls.sql`

The policy granting tutors SELECT on their own assignment rows is correct and
harmless, but no tutor-facing UI uses it yet. No action needed; documented so a
future tutor feature reuses it rather than adding a parallel policy.

### CONTRIB-06 / repo hygiene — human decisions required
- Untracked `iOS/TAVAttendance 2.xcodeproj/` appears to be a Finder duplicate of the
  real project. A human should confirm and delete it before committing (tracked in
  `HUMANS.md`).

### Android UI parity follow-ups
The flag-gated features (PROD-01/02/04) and several kiosk UX items (UX-01/02/03/04/07,
A11Y-02) are ported on Android at the data/service layer; their Compose UI is listed
as a follow-up in `Android/PORTING_NOTES.md`. iOS and web carry the full UI.

### Operational follow-ups (see HUMANS.md)
- Flip `feature_flags` rows when each feature is ready.
- Provide real APNs / FCM credentials for `notify-parent` before enabling
  `push_notifications`.
- Mirror/verify production Supabase `[auth]` settings (DEVOPS-05 verification).
- Set up the external uptime monitor (DEVOPS-04).

---

*Second wave implemented 2026-06-24.*
