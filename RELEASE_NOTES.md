# Release ledger

This is the source draft for mobile release notes. Keep completed changes under
`Unreleased`; the `release` skill audits them against Git before each release.

## Unreleased

- Android compiles against API 37.1 so the Dependabot android-deps bump can
  build: `core-ktx` 1.19 and Navigation Compose 2.10 (and the Lifecycle 2.11
  they pull) reject `compileSdk` 36. `targetSdk` stays 36. Also takes AGP
  9.3.2, Kotlin 2.4.10, supabase-kt 3.8.0, Ktor 3.5.2,
  kotlinx-serialization-json 1.11.0, and Firebase BOM 34.18.0.
- Remote security checks and Advisor watch no longer wait for a human Review
  deployments click on `main`. Prod credentials stay in the
  `production-security` environment (not repository secrets, not pull-request
  jobs). Clearing required reviewers on that environment is `HUMANS.md` §81;
  this change cannot live in git. Both workflows now cancel superseded runs
  via `concurrency`; that does not skip the reviewer click by itself, and
  already-waiting runs still need a reject/cancel. A later drift failure
  because 058/059 are not in production is a separate gate (`HUMANS.md` §76).
- Dark NFC arrival station on a Pi-class Linux box (`station/`, Raspberry Pi OS
  or Orange Pi/Armbian, USB CCID reader). Chip UID maps to a student; admin
  pairs/reissues on the web when `nfc_sign_in` is on. The station account may
  only call `arrival_station_tap`. Flag ships OFF; do not apply migration 059
  to production (`HUMANS.md` §77). iPhone/iPad/Android fail closed if that
  account signs in. The centre iPad kiosk stays tap-name; no Core NFC on
  `com.tava.TAVAttendance`.
- Centre kiosk is online-only: taps and overrides do not enter the pending
  queue. Wifi drop at the desk means paper, then reconcile against the website.
  Tutor roster can still queue; orange pending is device-local until the
  website agrees. Do not End Class, sign out, or hop accounts with pending, and
  do not offline-mark kids who already tapped the kiosk.
- New clients send `observed_marked_at` on offline sync. Migration 058
  compare-and-skips a delayed mutation when a newer server row already exists.
  Android now keeps JSON null in the pending queue when the device observed no
  row, matching the sync envelope. Not live in production until 058 is applied
  and those clients are installed (`HUMANS.md` §76). Device clocks remain
  untrusted.
- Empty kiosk shows “No Classes Today” only after a successful load. A failed
  load retries instead of looking like a day off. Search is admin-only; unlock
  is a long-press on the lock. Leave in-app Face ID off on the kiosk iPad.
- Staff test kit: TestFlight 1.1.3 build 8 (not App Store build 3); Guided
  Access, Singapore time, auto-lock off; don't Start Class early if On Time vs
  Late matters; dual-enrolled kids are one card that marks every session;
  informed vs no-notice Absent both count as Absent (parents never see the
  flag); website Export is a superadmin full ZIP, skip unless Edmund deletes it.
- Trimmed the agent skill library from fifteen runbooks to three (`deploy`,
  `release`, `tava-prod-drift-campaign`). Folded the manual QA scripts into
  `docs/KIOSK_ATTENDANCE.md`, setup traps into `CONTRIBUTING.md`, and a settled
  decisions list into `AGENTS.md`; deleted the rest and updated every
  cross-reference.
- Applied migration 057 to production on 2026-08-17, closing the database-level
  message NRIC/FIN guard after a clean local replay and full SQL regression run;
  verified the trigger, guarded parent-message RPC, web schema, and production
  security assertions directly against the live project.
- Restored the production dashboard by deploying current `main`; the previous
  14-day-old bundle still requested the retired `attendance_summary.excused_count`
  column. Post-deploy route, security-header, API-contract, and error-log checks
  passed.
- Traced the iOS kiosk failure to App Store build 3 using the retired direct
  `sessions` insert, which the hardened production policy correctly rejects.
  TestFlight 1.1.3 build 8 uses the guarded session RPC, and its 54 iOS tests
  pass.

## 1.1.3 — 2026-08-17

- Shipped Android `1.1.3` (`versionCode` 6) to Firebase App Distribution and
  iOS `1.1.3` (`CFBundleVersion` 8) to TestFlight. Source commit before the
  version bump: `c2abd6e`.
- Documented the approved “Every child accounted for” product direction: a
  two-month, sub-50-child September pilot of the existing core; offline
  correction ordering as a pre-pilot blocker; and the evidence-gated path to an
  authoritative expected roster, Web Accountability Board + Exception Inbox,
  handoff evidence, parent assurance, and minimal child context. Payments,
  accounting, payroll, CRM, and broad ERP scope remain excluded.
- Removed the completed dashboard mock from the live documentation tree, cleared
  shipped work from the next-build queue, corrected stale architecture paths,
  and retired merged or abandoned remote branches.
- `production-security` required reviewer is now `EdmundLimBoEn` only (self-review
  allowed). `waynetay` and `winson-lebron` were listed but not active, which left
  Remote security checks and Advisor watch waiting.
- Format `cleanup-student-storage` so the Edge Functions CI `deno fmt` gate passes
  (broken since that function landed on 2026-08-05).
- Reject NRIC/FIN in parent and staff messages on the web/Android/iOS write
  paths (notes already had this guard). The production table trigger and
  `send_parent_message` body from migration 057 are still HUMANS.md §73.
- Pin web transitive overrides to patched `brace-expansion` 5.0.9, `nanoid`
  3.3.18, and `js-yaml` 4.3.1 (`nanoid` 3.3.17 is in GHSA-2v37-7h3g-55p8).
- Refactored agent/contributor documentation around a concise change workflow:
  root `AGENTS.md` now owns durable invariants and change seams, detailed kiosk
  semantics have one domain reference, QA and port handoff procedures have one
  canonical runbook each, and volatile migration counters were removed from
  documentation. Re-verified migration 056 directly in production on 2026-08-11;
  no reapplication was required.
- Android: wire `absence_informed` through mark/sync/retrospective/roster/kiosk
  (Informed / Did not inform; Mark Rest Absent = no notice). Status enum unchanged;
  parents still never see the flag. Decode-safe optional `late_reason` on roster
  rows only (no late-reason UI yet).
- Android Students tab opens a rolling 12-month year-detail sheet (by-class
  summary + recent register, cap 50), separate from the 30-day roster profile
  sheet; tutor caption when role is not admin.
- Web: roster and sign-in board can mark Absent as informed vs no notice
  (`absence_informed`); status badges / student recent register show the three-way
  labels; CSV export includes the column. Parent surfaces unchanged.
- Web student detail (admin + mobile) uses a rolling 12-month by-class summary
  aggregated from session history (matching iOS), with a tutor caption on mobile
  when the viewer is not admin.
- Split Absent into informed vs did not inform via companion column
  `attendance_records.absence_informed` (migration 056, applied to prod
  2026-08-07). Status domain stays present/late/absent; iOS kiosk/roster can
  set and show the flag; offline sync and retrospective RPCs carry it; parents
  never see it.
- iOS Students tab rows open a year-detail sheet (by-class summary + recent
  register over a rolling 12 months), with a tutor caption when RLS scopes the
  view to classes they teach.
- Flipped root agent knowledge to `AGENTS.md` (with `CLAUDE.md` stubbing
  `@AGENTS.md`, matching `web/`); added `NEXT_BUILD_CHANGES.md` as the planned
  next-build queue. Verified 2026-08-06 staff feedback against prod/clients:
  excused/E already merged (055); pending = Not Here Yet + retrospective
  (flag ON in prod); queued informed/uninformed absent and native Students
  detail mirroring web `students/[id]`; fixed stale README “P/A/L/E” wording.
- Bridged high-priority automated coverage gaps: study-space exclusion contracts
  for staff attendance history (iOS/Android query constants + tests), migration/
  view source contracts and optional SQL for `attendance_summary` / parent
  summary, Deno unit tests for notify-parent payload validation and
  cleanup-student-storage UUID path matching (pure helpers extracted from edge
  handlers), plus removal of Finder-duplicate junk that polluted suite scans
  and Android BuildConfig compiles.
- Fixed iOS kiosk reloads for students dismissed from multiple same-day classes;
  the latest dismissal now wins instead of duplicate student keys crashing.
- Trimmed the web app by removing its compatibility query barrel, generic chart
  framework, unused public exports, and four unnecessary direct dependencies;
  mobile pages now share one request-cached profile/class mapping path, and
  Android CI now runs the platform lint task.
- Retired the legacy AltStore/development-export path, redundant Android clean
  script, duplicate iOS export plist, and obsolete Phase 2/3 RLS plan.
- Consolidated all unmarked attendance into one “Not Here Yet” state across iOS,
  Android, web, and Supabase. Clearing attendance now deletes the row through
  an actor-bound, replay-safe RPC; reports use Present, Late, and Absent only.
- Moved the web Add Student tile to the first student-grid slot and removed the
  duplicate yellow header action.
- Restored the web Users “Remove” action after the table redesign hid it
  (hover-only control with no `group` parent).
- Added staff pre-pilot readiness checklist (`docs/test-kit/PRE_PILOT_CHECKLIST.md`)
  and rewrote the staff test-kit guides (guide, 15-minute script, pre-pilot) in
  informal first-person voice: what must work before real kids, what’s simply
  not ready yet if still off, go/no-go without product-brochure tone.
- Web admin dashboard visual pass aligned to the approved dashboard mock:
  exact navy/marigold/cream hex palette, cream surface shell, sidebar
  squircle/expand motion, draft status badges (On time / Not Here Yet), Today
  paired present/late bar chart + quick actions, Analytics by-class progress
  rows + student risk bands, Students marigold Add + dashed add-card, Messages
  chat bubbles/unread marigold, Users team table + invite side card. Keeps Lato
  + Fredoka (not Elms Sans). No schema or new product features.
- Fixed `sync_attendance_test` after migration 054’s staff role gate: the offline
  sync integrity suite authenticates as seed admin, binds receipt actors to that
  principal, and uses the session-lifecycle write flag when fixture-ending a
  session.

## 1.1.2 — 2026-07-31

- Bugfixes, security fixes, and more.
- Fixed Android AttendanceService/kiosk data-source wiring after the modular
  split (retrospective session facade syntax, cross-source kiosk/roster calls)
  so release builds compile again.
- Quieted Dependabot version-update spam: monthly grouped patch/minor PRs,
  single web package manager (Bun / `bun.lock`; removed `package-lock.json` and
  npm Dependabot), ignored auto major bumps for tooling
  (TypeScript/ESLint/`@types/node`/Next/React), and enabled Dependabot security
  updates so vulnerability PRs still open immediately. CI/deploy/docs gates use
  `bun install --frozen-lockfile` + `bun audit` / `bun run test|lint|build`.
- Internal behaviour-preserving refactor: split native kiosk screens and
  security policy modules, modularize AttendanceService behind stable facades,
  split the Android student profile sheet, and turn `web/lib/queries` into a
  compatibility barrel with domain modules; added characterization tests for
  kiosk PIN/lockout policy, student-profile tab/state rules, and web
  attendance/audit pure helpers.
- Security hardening (2026-07-29 scan): parent result-slip signed URLs require a
  canonical student path prefix; bulk student import is capped at 500 rows;
  invite/login Auth errors are sanitized; admin message/audit PostgREST filters
  validate UUIDs/timestamps; migration 054 gates study-space roster, offline
  sync staff role, parent-link role, and device-token ownership; iOS kiosk PIN
  compare is constant-time; Android disables cloud backup of app data.
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
