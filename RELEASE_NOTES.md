# Release ledger

This is the source draft for mobile release notes. Keep completed changes under
`Unreleased`; the `release` skill audits them against Git before each release.

## Unreleased

- Added feature-flagged retrospective session management on iOS: authorised
  staff can create and edit past sessions, correct ended attendance online,
  and add visible students to one session without changing enrolment.
- Added a mobile-first staff web app under `/mobile/*` with role-aware class
  and student management, session start/resume/end controls, live attendance
  marking, session notes, grades, enrolments, and an admin sign-in board with
  the native app's automatic late/on-time decision.
- Native parent portal Phase 2 (iOS + Android, behind `parent_portal`): each
  child opens with Attendance / Results / Messages tabs; parents submit
  text-only result slips (pending/acknowledged), and message TAVA per child.
  No native file upload; study-space attendance stays excluded.
- Web parent portal Phase 2 (behind `parent_portal` flag): parents upload
  result slips and message the centre per child; admin gets `/messages` and
  `/result-slips` pages (reply, mark read, acknowledge slips). Migration 035
  adds the parent INSERT policies (result_slips + storage, messages),
  thread indexes, and per-parent message privacy when siblings share a child.
- Admin web `/users`: link/unlink students to parent accounts inline via the
  existing `link_parent_student`/`unlink_parent_student` RPCs (first UI for
  `parent_student_links`).
- Admin web Activity feed now resolves entity names — entries read
  "Edmund edited Class: Sec 2 Math" instead of raw table/column names, with
  friendly changed-field subtitles.
- Added atomic student creation with mandatory consent attestation across web,
  iOS, and Android; direct student inserts and consent-ledger mutations are now
  blocked.
- Hardened tutor grade access, Study Space report/export exclusion, account
  invitation privileges, and App Intent kiosk authorization.
- Removed student identifiers from push notifications, analytics error details,
  and successfully synced Android offline-attendance cache entries.
- Explicit erase/anonymise flows now delete student photos and result slips from
  Storage before removing database data; scheduled orphan cleanup remains
  tracked separately.
- Added regression coverage for kiosk App Intent authorization, analytics
  redaction, and Android offline-cache cleanup.
- Release preparation now reports changes since the prior build and requires an
  explicit user-selected marketing version before any release mutation.

## 1.1 — 2026-07-16

- Added opt-in biometric app unlock on iOS and Android, including Face ID or
  fingerprint protection for kiosk administration.
