# Release ledger

This is the source draft for mobile release notes. Keep completed changes under
`Unreleased`; the `release` skill audits them against Git before each release.

## Unreleased

- Restored the Android student-management entry point for consent status,
  subject-access export, and other PDPA data controls.
- Refreshed supported Android, iOS, and web dependencies, including AGP 9.3
  with built-in Kotlin, Supabase Swift 2.53, Next 16.2.12, and React 19.2.8;
  synchronized npm/Bun locks and retained incompatible ESLint 10/TypeScript 7
  upgrades for a later toolchain release.
- Fixed local/CI seed replay across the Singapore-midnight boundary by deriving
  the sample session date in the same timezone as session lifecycle guards.
- Redesigned the web admin Today dashboard as a compact, card-free daily
  attendance register while preserving the existing TAVA type and colour system.
- Encrypted pending attendance queues with per-install Keychain/Keystore
  AES-GCM keys on iOS and Android, including verified migration from the former
  plaintext account-owned envelope and tamper-detection tests; removed Android
  biometric context-cast and nullable date/document/session crash paths.
- Rotated the production App Review admin password and synchronized the new
  credential to App Store Connect without storing it in the repository.
- Made Android kiosk PIN throttling atomic and fail closed for every caller,
  with accurate lockout UI/tests; pull-request CI now runs web security
  regressions, and production-secret workflows declare the reviewer-gated
  environment that operators must protect before merge.
- Patched the web dashboard's Next.js and transitive dependency advisories;
  Android auth sessions and PKCE verifiers now migrate from plaintext
  SharedPreferences into Android Keystore-backed AES-GCM storage. Audited and
  refreshed all operational runbooks against the current migrations, CI,
  release paths and security boundaries; staff guidance no longer promises
  infallible offline sync, and the breach plan now has evidence-preserving
  containment and current PDPC notification criteria.
- Restored superadmin feature-flag updates behind the database RLS boundary and
  added regression coverage for ordinary-admin no-op writes; refreshed
  vulnerable transitive web dependencies used by CI/build tooling.
- Added a superadmin-only dashboard export that downloads a full operational
  data snapshot as a ZIP of CSV files, while excluding internal Study Space
  attendance and private file contents.

- Closed database authorization gaps around future tutor assignments,
  substitute tutors, attendance rosters/actor timestamps, historical edits,
  delayed offline replays, parent safe-column RPCs, account-role escalation,
  messages/result slips, atomic correction review, and feature-flagged writes;
  rotated identifiers during student pseudonymisation while documenting that
  retained session chronology is not guaranteed anonymous.
- Made current-session creation, start/end, notes, class discovery, and roster
  access shaped/server-timed. Ended sessions cannot reopen, and explicit
  capabilities keep recent substitute history read-only without dead controls;
  native student-profile loads are identity-bound and result-slip controls are
  limited to parents/admins.
- Locked down private uploads with canonical paths, server-side size/MIME
  limits, rate-limited signed-upload intents, content signatures, atomic
  finalization, server-minted downloads, service-role-only erasure, a race-safe
  pre/post Storage sweep, and a durable retry/intent cleanup worker; native
  erasure now fails closed to the trusted web path.
- Hardened kiosk mode against navigation, restart, background, context-menu,
  PIN-reset, and Siri/Shortcuts bypasses; sensitive native screens no longer
  appear in screenshots or app-switcher previews.
- Added exact-origin web security headers, stronger account password defaults,
  dedicated-secret push validation, clean dependency audits, redacted
  current-tree/staged credential scanning, and pinned/least-privilege CI with
  Edge checks, migration/SQL regressions, and explicit production
  privilege/RLS/Storage assertions.
- Bounded analytics ingestion and parent device registration behind database
  RPCs; capped per-user volume/fan-out and isolated APNs/FCM setup, transport
  failures, timeouts, and stale-token cleanup.
- Bound native pending attendance to the originating account, purged unsafe
  legacy/mixed queues, cleared on sign-out, and rechecked ownership before sync.

## 1.1.1 — 2026-07-21

- Added feature-flagged retrospective session management on iOS and Android: authorised
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
- Explicit erase/anonymise flows delete student photos and result slips from
  Storage; migration 038 later added durable retries for scheduled retention.
- Added regression coverage for kiosk App Intent authorization, analytics
  redaction, and Android offline-cache cleanup.
- Release preparation now reports changes since the prior build and requires an
  explicit user-selected marketing version before any release mutation.

## 1.1 — 2026-07-16

- Added opt-in biometric app unlock on iOS and Android, including Face ID or
  fingerprint protection for kiosk administration.
