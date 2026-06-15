# TAVA Attendance — Improvement Findings

Multi-perspective audit. Perspectives repeated until no new findings could be produced.

> **2026-06-15:** Implemented findings removed. The fixes landed in `supabase/migrations/010_audit_fixes.sql` and across the iOS / Android / web platforms. Removed IDs: SEC-01, SEC-02, SEC-03, SEC-04, SEC-06, SEC-08, SEC-10, PERF-01, PERF-02, PERF-03, PERF-05, MAINT-01, MAINT-02, MAINT-03, MAINT-08, MAINT-10, MAINT-12, QA-01, QA-02, QA-03, QA-07, UX-05, A11Y-01, A11Y-03, A11Y-04, A11Y-06, SP-03, SP-04, SP-05, SP-06, SP-07. The items below remain open.

---

## Security Auditor

### SEC-05 `handleNewUser` trigger accepts any role from invite metadata (MEDIUM)
**File:** `supabase/migrations/001_schema.sql:26–35`

The trigger inserts `COALESCE(NEW.raw_user_meta_data->>'role', 'tutor')` into `profiles.role`. The `profiles` table enforces `CHECK (role IN ('admin', 'tutor', 'parent'))`, which prevents invalid values, but an admin who calls `inviteUserByEmail` and passes `data: { role: 'admin' }` will create a new admin row. This is the intended flow, but it means any person with access to the Supabase service-role key (e.g., a compromised backend) can mint admin accounts by crafting an invite. Consider adding a DB-level guard: refuse the trigger's insert if the calling `auth.uid()` itself is not already an admin (for initial bootstrap, allow if the `profiles` table is empty).

### SEC-07 `result-slips` Storage bucket is never created (MEDIUM)
**File:** `iOS/…/Services/AttendanceService.swift:384`

`uploadResultSlip` calls `db.storage.from("result-slips")`. No migration creates this bucket. On a fresh database, uploads fail at runtime with an opaque "bucket not found" error. Fix: add a `supabase storage create result-slips` command to the setup docs, or create it in a migration/seed file.

### SEC-09 No rate limiting on the invite server action (LOW)
**File:** `web/app/actions/invite.ts`

`inviteUser` verifies the caller is an admin but has no rate limit. A compromised admin account could enumerate thousands of email addresses as Supabase invite calls. Fix: add a server-side rate limit (e.g., `upstash/ratelimit` or a simple DB-backed counter) or rely on Supabase Auth's built-in invite rate limit if it is configured.

---

## Performance Engineer

### PERF-04 iOS `RosterView` re-fetches the entire roster after every single attendance mark
**File:** `iOS/…/Views/Session/RosterView.swift:270`

After `markAttendance` succeeds online, the code calls `fetchRoster(sessionId:)` to refresh. For a 40-student class this is a full round-trip and full list rebuild on every button tap. The optimistic `localStatus` dictionary already provides correct UI state. Fix: only call `fetchRoster` on initial load or explicit pull-to-refresh; trust the optimistic update until the view is closed.

### PERF-06 Web `getRosterForDate` loads all enrollments and records without a row cap
**File:** `web/lib/queries.ts:15–75`

The query selects `attendance_records(...)` and `enrollments!inner(...)` as nested arrays. PostgREST's `max_rows = 1000` cap in `config.toml` applies to the top-level query (sessions), not nested relations. On a busy day with many sessions, the full nested payload can be very large. Fix: consider a dedicated Postgres function that returns the pre-aggregated map, or add explicit limits per session.

### PERF-07 `ExportView` eagerly loads all students regardless of export trigger
**File:** `iOS/…/Views/Admin/ExportView.swift:115–117`

On view load, both `fetchMyClasses` and `fetchAllStudents` are called in parallel. `fetchAllStudents` is only needed to build a `studentMap` lookup at export time. For a large student list this is an unnecessary up-front fetch. Fix: move `fetchAllStudents` inside `export()`, or derive student names from the joined session/attendance data in the PostgREST query.

---

## Maintainer

### MAINT-04 `enrollments.unenrolled_at` is never populated (DEAD COLUMN)
**File:** `supabase/migrations/001_schema.sql:100`

`unenrollStudent` sets `is_active = false` but never writes `unenrolled_at`. The column exists in the schema and is part of the model expectation, but carries no data. Either remove the column or populate it in the service layer.

### MAINT-05 `class_tutor_assignments.assigned_until` is never set by any UI (DEAD COLUMN)
**File:** `iOS/…/Services/AttendanceService.swift:92–102`

`assignTutor` upserts without setting `assigned_until`. The RLS policy for `tutor_owns_class` uses `AND (assigned_until IS NULL OR assigned_until >= CURRENT_DATE)` — which works because `assigned_until` is always NULL. But the column is documentation debt. Either remove it or expose it in `TutorAssignmentView`.

### MAINT-06 `ExportRecord` struct in ExportView.swift is dead code
**File:** `iOS/…/Views/Admin/ExportView.swift:10–32`

`ExportRecord` defines a struct with a nested `ExportSession` that includes `sessionDate`. However, `export()` calls `fetchAttendanceForExport` which returns `[AttendanceRecord]`, not `[ExportRecord]`. `ExportRecord` is never decoded and never referenced. As a result, the CSV "Date" column falls back to deriving the date from `markedAt` (an acknowledged workaround in the comment) rather than the true session date. Fix: either use `ExportRecord` in the service call, or delete the dead struct.

### MAINT-07 iOS `ExportView` has two inconsistent error-state variables
**File:** `iOS/…/Views/Admin/ExportView.swift:47–48`

`errorMessage: String?` is used by `export()`, and `error: AppError?` is used by the `.task` loader. Both can be set simultaneously, or one can mask the other. The `.errorAlert(error: $error)` modifier handles the AppError; a separate `Section { Text(err).foregroundStyle(.red) }` handles `errorMessage`. Fix: unify to a single `AppError?` and use `.errorAlert` consistently.

### MAINT-09 `sub_tutor_id` added in both migration 005 and 006 (SCHEMA DRIFT)
**Files:** `supabase/migrations/005_sprint_features.sql:18`, `supabase/migrations/006_session_end.sql:11`

Migration 005 adds `sub_tutor_id` to `sessions`; migration 006 also adds it with `IF NOT EXISTS`. The comment in 006 says it's adding "columns missing from the live DB" — suggesting the live database diverged from the migration history. Idempotency saves correctness, but this indicates the migrations were applied out of order or partially on production. Worth documenting the discrepancy and confirming the live DB matches the full migration sequence.

### MAINT-11 `sync_attendance` silently skips records for ended sessions with no explanation
**File:** `supabase/migrations/003_functions_triggers.sql:155–165`

The `enforce_attendance_on_open_session` trigger fires on `BEFORE INSERT OR UPDATE`. When `sync_attendance` attempts to upsert a record for an ended session, the trigger raises an exception, which the function catches as "not found" and increments `skipped`. The caller only receives `{"synced": N, "skipped": M}` with no indication that records were rejected for an ended session vs. legitimately skipped because they were older. Fix: return a third field, e.g. `"blocked_ended_session": K`, or log these rejections to a separate table.

### MAINT-13 `profiles: read own or admin` breaks `fetchTutors()` when called by a tutor
**File:** `supabase/migrations/004_security_fixes.sql:28–33`

After migration 004, authenticated tutors can only SELECT their own profile row. `AttendanceService.fetchTutors()` queries `profiles WHERE role = 'tutor'` — when called by a non-admin, RLS will return only the caller's own row. This is likely fine because tutor-assignment screens are admin-only, but it is a latent bug: any future screen that allows tutors to view peer profiles (e.g. a substitute-tutor selector) will silently return an incomplete list with no error.

---

## QA Engineer

### QA-04 Export CSV date is wrong for offline-synced records
**File:** `iOS/…/Views/Admin/ExportView.swift:168–175`

The comment explicitly acknowledges this: "markedAt used as proxy for session date". A student marked offline at 8pm who syncs the next morning will appear in the export under the sync date, not the session date. The `ExportRecord` struct (dead code, see MAINT-06) has a `sessionDate` field from the PostgREST join that would fix this. Fix: either use `ExportRecord` and decode the joined `session_date`, or add `session_date` to the `fetchAttendanceForExport` select and include it in a separate `AttendanceExportRecord` type.

### QA-05 `fetchStudentAttendanceHistory` filters by `marked_at` rather than `session_date`
**File:** `iOS/…/Services/AttendanceService.swift:272–288`

The `since` parameter filters `attendance_records.marked_at`. An offline record marked during a session three weeks ago but synced today would correctly fall within a "since 30 days" window. However, a record synced five weeks ago for a session that was last week (backward clock correction) would be excluded. The semantically correct filter for "sessions in the last 30 days" is `sessions.session_date`. Fix: add a PostgREST nested filter on `session_date` or use a SECURITY DEFINER function that joins on session date.

### QA-06 PIN migration clears the PIN for any format that is not plaintext-4-digit or `v1:` prefixed
**File:** `iOS/…/Views/Kiosk/GlobalKioskView.swift:134–139`

If a device somehow stores a PIN in a third format (e.g., a partial write, a corrupted string, or a format introduced by a future migration), the migration path clears `storedPIN` to `""`. This silently removes kiosk security without notifying the admin. The next screen shows "No PIN set — kiosk is always in admin mode". Fix: at minimum, log a warning or show a one-time alert that the PIN was reset.

### QA-08 `StudentProfileView.attendanceRate` uses only `present + late` in numerator
**File:** `iOS/…/Views/Session/StudentProfileView.swift:39–41`

```swift
var attendanceRate: Double {
    guard !history.isEmpty else { return 0 }
    return Double(presentCount + lateCount) / Double(history.count)
}
```

`excused` records are excluded from the numerator but included in the denominator. An excused student's rate is penalised even though "excused" implies a valid reason. The `attendance_summary` view in Postgres includes `excused` in the attendance percentage. This inconsistency means the profile view and the web dashboard show different attendance rates for the same student. Fix: align both to the same formula, or document the intentional difference.

---

## End User

### UX-01 No auto-refresh on the iOS kiosk
**File:** `iOS/…/Views/Kiosk/GlobalKioskView.swift:106`

The kiosk has `.refreshable` (pull-to-refresh) and a single `.task` load, but no periodic auto-refresh. If the kiosk is left idle while other admin devices mark students via the roster view, the kiosk display becomes stale. Students who have already been marked still appear as unsigned. The web dashboard auto-refreshes every 30 seconds; the kiosk should too. Fix: add a `Timer.publish(every: 30, ...)` in `.onAppear` that calls `await load()`.

### UX-02 No search or filter on the kiosk grid
**File:** `iOS/…/Views/Kiosk/GlobalKioskView.swift`

For a centre with 80+ students, finding a specific student requires scrolling through the entire grid. No search bar or alphabetical jump bar is provided. Fix: add a `@State private var searchText = ""` + `searchable(text: $searchText)` modifier that filters `entries` by `fullName.localizedCaseInsensitiveContains`.

### UX-03 Bulk actions have no confirmation dialog
**File:** `iOS/…/Views/Kiosk/GlobalKioskView.swift:266–283`

Selecting 50 students and tapping "Absent" applies the status to all of them immediately with no undo path. A mis-tap on the action bar could incorrectly mark the entire class absent. Fix: add a `confirmationDialog` before `applyBulkAction` that names the action and count (e.g. "Mark 50 students as Absent?").

### UX-04 "Absent" has no student-facing undo path
**File:** `iOS/…/Views/Kiosk/GlobalKioskView.swift:524–529`

`canTap` returns `false` for absent cards in non-admin mode. A student who was accidentally marked absent cannot tap their own card to sign in — only an admin with the PIN can override. The red card is permanent from the student's perspective. A reasonable escape hatch would be to allow a tap on an absent card to require a brief confirmation (e.g., "Are you here? Tap to sign in") that a nearby teacher could approve.

### UX-06 `result_slips.subject` is hard-coded to Math/English only
**File:** `supabase/migrations/005_sprint_features.sql:54`

`CHECK (subject IS NULL OR subject IN ('Math', 'English'))` prevents any other subject. This cannot be extended without a migration. For a tutoring centre that covers Physics, Chemistry, or Languages, this is a product limitation. Fix: remove the CHECK constraint and enforce the allowed values in application code where they can be updated without a database migration.

### UX-07 "Not Here" vs "Absent" distinction is unexplained in the UI
**File:** `iOS/…/Views/Kiosk/GlobalKioskView.swift:247–248`

Two grey-ish states ("Not Here" = excused, and "Absent" = absent) appear in the action bar. Their functional difference (student can still sign in after "Not Here"; cannot after "Absent") is not communicated. Most centre staff would have to be trained out-of-band. Fix: add a tooltip or subtitle on first use, or present a brief info sheet when the user first encounters the distinction.

---

## New Contributor

### CONTRIB-01 README setup instructions are outdated
**File:** `README.md:50–56`

Step 3 says: "Edit Core/SupabaseManager.swift with your Supabase URL + anon key". This is wrong. Credentials are loaded from `Config.xcconfig` via `Info.plist`. A contributor following the README would not find where to enter credentials and would hit the `fatalError` at runtime. Fix: update to reference `Config.xcconfig.example` → `Config.xcconfig` with the actual keys, and include the equivalent steps for Android (`secrets.properties.example`) and Web (`.env.local.example`).

### CONTRIB-02 README does not mention Android or Web platforms
**File:** `README.md`

The README describes iOS + Supabase only. A developer cloning the repository and looking at the directory listing would see `Andriod/` and `web/` with no documentation. There is no mention of how to run the Android app or the Next.js dashboard. Fix: add a "Platforms" section with brief setup steps for each, and cross-reference `Andriod/PORTING_NOTES.md` (pending creation).

### CONTRIB-03 No CI/CD pipeline
**File:** (none — missing)

There are no GitHub Actions workflows or other CI configuration. Every push to `main` ships unvalidated code. There is no automated Swift build, Android Gradle check, Next.js `lint`/`build`, or migration syntax check. Fix: add at minimum a GitHub Actions workflow that runs `next build`, `./gradlew build`, and `supabase db lint`.

### CONTRIB-04 No CONTRIBUTING.md or development setup guide
**File:** (none — missing)

Newcomers must piece together setup from CLAUDE.md (agent instructions), README.md (partial, outdated), and scattered comments. There is no single document covering: local Supabase startup, iOS project setup, Android secrets, web `.env.local`, and the local testing checklist. Fix: create `CONTRIBUTING.md` that consolidates these steps.

### CONTRIB-05 The `Andriod` directory misspelling affects tooling reliability
**File:** (directory name)

The Android project lives in `Andriod/` (misspelled). This is documented in CLAUDE.md but catch-all glob patterns like `Android/**`, CI steps referencing "Android", and documentation generators will silently miss the directory. Fix: rename to `Android/` with a `git mv` and update all references. The one-time rename is lower friction than perpetually working around the typo.

### CONTRIB-06 `Andriod/.gitignore` and `Andriod/app/build.gradle.kts` are unstaged modified
**File:** (git status)

The working tree shows `M Andriod/.gitignore` and ` M Andriod/app/build.gradle.kts` (staged and unstaged). Any developer who pulls `main` after this state is committed would get a dirty tree. These changes should be committed (or stashed) before the branch is shared.

---

## Documentation Reviewer

### DOC-01 Phase 2/3 tables have no plan for RLS when implemented
**File:** `supabase/migrations/002_rls.sql:274–287`

All Phase 2/3 tables are locked to `admin only`. When these features are implemented, each table will need carefully considered RLS policies (e.g., parents reading their child's result slips, both parties in a message thread reading the message). None of this is documented anywhere. Fix: add a `PHASE_RLS_PLAN.md` or inline comments in `002_rls.sql` describing the intended policies for each phase-2/3 table.

### DOC-02 `recurrence_rule` accepts arbitrary text with no documented format or validation
**File:** `iOS/…/Models/Models.swift:31`, `supabase/migrations/005_sprint_features.sql:14`

The column comment says "RFC 5545 RRULE, e.g. FREQ=WEEKLY;BYDAY=MO" but no DB constraint enforces this. An admin entering "weekly on Monday" instead of "FREQ=WEEKLY;BYDAY=MO" would store a string that no RRULE parser can interpret. Fix: either add a CHECK constraint that validates the format (a regex for basic RRULE patterns), or add client-side validation and document the expected format in the ClassFormView.

### DOC-03 `CLAUDE.md` mentions `PORTING_NOTES.md` which does not exist
**File:** `CLAUDE.md` (iOS → Android file mapping section)

CLAUDE.md says "see Andriod/PORTING_NOTES.md for the mapping once it exists". The file does not exist. The mapping is currently only in CLAUDE.md itself. Fix: create `Andriod/PORTING_NOTES.md` with the table already written in CLAUDE.md.

### DOC-04 No documentation on Storage bucket configuration
**File:** (none — missing)

The `result-slips` Storage bucket is referenced in code but never created in migrations or documented in setup guides. The Supabase Dashboard setup, bucket permissions, and file size/type limits are not described anywhere. Fix: add a setup step in `CONTRIBUTING.md` covering `supabase storage create result-slips --public false` and the required RLS policy for the bucket.

### DOC-05 `session:sessions!inner(session_date, class_id)` join syntax in `fetchAttendanceForExport` is undocumented
**File:** `iOS/…/Services/AttendanceService.swift:458`

CLAUDE.md documents the FK join syntax for `fetchStudentAttendanceHistory` but not for the export query. A contributor modifying the export query without understanding PostgREST's `!inner` modifier could inadvertently change it to a LEFT JOIN and include sessions with no attendance. Add an inline comment referencing the PostgREST documentation.

---

## Accessibility Reviewer

### A11Y-02 Status colour is the only differentiator for the unsigned/excused states
**File:** `iOS/…/Views/Kiosk/GlobalKioskView.swift:478–497`

Both `nil` (unsigned) and `.excused` (not here) render with `Color(.tertiaryLabel)` and a grey icon. Only the icon shape differs (`person.circle` vs `person.badge.minus`). Users with low vision or colour blindness cannot distinguish these without reading the status label, which is absent for the `nil` state. Fix: show a text label below the icon for all states (including unsigned), or add distinct background patterns.

### A11Y-05 Web dashboard avatar initials have no `aria-label`
**File:** `web/app/(admin)/overview/page.tsx:7–18`

`<Avatar name={student.fullName} size="sm" />` renders the student's initials in a coloured circle. Without an `aria-label` on the container, screen readers announce the initials (e.g., "JD") rather than the full name. Fix: add `aria-label={student.fullName}` to the Avatar's root element.

---

## Product Manager

### PROD-01 Parent role is active in auth but has zero UI
**File:** `web/app/(admin)/users/invite-form.tsx`, `iOS/…/Core/AuthManager.swift`

Parents can be invited, create passwords, and authenticate, but encounter a blank experience: the iOS app shows no parent-specific tab (no parent view wired in `ContentView`), and the web dashboard blocks non-admin access. Parents are an active user role in the database but a ghost role in the product. Either remove the parent invite option until the feature is ready, or add a minimal "your attendance history is being prepared" placeholder screen to avoid confusing parents who accept their invite.

### PROD-02 No push notifications to parents for late/absent markings
**File:** `README.md:103`

The README roadmap lists push notifications as a near-term improvement. With the dismissal feature shipping (tracking whether students leave safely), the absence of parent notification is a safety gap: a parent who expects their child is dismissed doesn't know if the child was marked absent instead. The `messages` table exists but is unused.

### PROD-03 No "mark all unmarked as absent" end-of-class action
**File:** `README.md:104`

Noted in the roadmap but absent from the product. At class end, a tutor must manually find and mark each unmarked student. For a 40-student class where 35 attended, the tutor must individually mark 5 students absent instead of tapping once. Fix: add a "Mark all unmarked as Absent" toolbar button in `RosterView`, guarded by a confirmation dialog.

### PROD-04 No student photos on kiosk cards
**File:** `README.md:101`

All kiosk cards are identical in structure (icon, name, status). For students with similar names, there is no way to confirm the right card is tapped without a photo. The README notes this as a near-term improvement. The `students` table has no `avatar_url` column yet.

### PROD-05 `attendance_pct` calculation in the view and in `StudentProfileView` are inconsistent
**Files:** `supabase/migrations/007_security_invoker_view.sql:18–24`, `iOS/…/Views/Session/StudentProfileView.swift:39–41`

The `attendance_summary` view uses `COUNT(*) FILTER (WHERE s.status IN ('present','late','excused'))` — excused counts toward attendance. `StudentProfileView.attendanceRate` uses `(presentCount + lateCount) / total` — excused counts against attendance. The web dashboard and iOS profile view will show different rates for the same student. Document the intended definition and harmonise.

---

## DevOps Engineer

### DEVOPS-01 No database rollback scripts
**File:** `supabase/migrations/`

Nine migration files exist with no corresponding down migrations. If `009_security_hardening.sql` breaks a production query, reverting requires writing manual SQL under pressure. Fix: create `009_security_hardening_down.sql` for each migration, or use a migration framework that supports reversible migrations.

### DEVOPS-02 Android release builds disable minification with no ProGuard rules
**Files:** `Andriod/app/build.gradle.kts:50–54`

`isMinifyEnabled = false` and the default empty `proguard-rules.pro` mean release APKs include all class names, method names, and string constants in plain text. This makes reverse engineering trivial and increases APK size. Fix: enable `isMinifyEnabled = true` and add ProGuard rules to keep Supabase SDK serialisation annotations (`@SerialName`, `@Serializable`).

### DEVOPS-03 Web `.env.local` is in the repository working tree
**File:** `web/.env.local`

The file exists on disk and contains production Supabase credentials. It is gitignored within `web/`, but its presence in the working tree is one accidental `git add .` from being committed. Fix: add `web/.env.local` to the root `.gitignore` as a second line of defence, and add a pre-commit hook that rejects files containing `SUPABASE_ANON_KEY=` or `SUPABASE_SERVICE_ROLE_KEY=`.

### DEVOPS-04 No health check or uptime monitoring for the web dashboard or Supabase project
**File:** (none — missing)

There is no documented monitoring strategy. If the Next.js deployment on Vercel goes down or Supabase has an outage, the team would know only when a user reports it. Fix: set up Vercel's built-in health checks and subscribe to the Supabase status page, or add a simple external ping monitor (e.g., UptimeRobot).

### DEVOPS-05 `supabase/config.toml` does not configure `[auth]` settings
**File:** `supabase/config.toml`

No `[auth]` section is present, so local development uses Supabase's defaults. The production project may have different settings (e.g., JWT expiry, email templates, allowed OAuth providers). Discrepancies between local and production auth behaviour can cause hard-to-reproduce bugs. Fix: document the production auth settings and mirror them in `config.toml`.

---

## Second Pass — Findings Not Captured Above

### SP-01 `class_tutor_assignments` RLS allows tutors to read their own assignment but `fetchTutorAssignments` is admin-only anyway (LATENT)
**File:** `iOS/…/Views/Admin/TutorAssignmentView.swift`

The RLS policy `"class_tutor_assignments: tutor reads own"` grants tutors SELECT on rows where `tutor_id = auth.uid()`. The UI that calls `fetchTutorAssignments` is only accessible to admins. If a future tutor-facing feature queries this table, a tutor can see which classes they are assigned to but not other tutors' assignments — which is the correct behaviour. This is fine, but worth noting that the policy was written in anticipation of a feature that doesn't exist yet.

### SP-02 `sync_attendance` may conflict on `client_mutation_id` UNIQUE constraint before reaching the session/student conflict
**File:** `supabase/migrations/003_functions_triggers.sql:137–162`

`attendance_records` has two UNIQUE constraints: `(session_id, student_id)` and `client_mutation_id`. The `ON CONFLICT (session_id, student_id) DO UPDATE` clause handles the first. If two offline devices create attendance records for the same student/session but with different `client_mutation_id` values, the second sync attempt will insert a new row, hit the `client_mutation_id` UNIQUE constraint on the already-updated row's new value, and fail with an unhandled exception (not the expected conflict resolution path). This is an unlikely edge case but a data integrity gap. Fix: add `ON CONFLICT (client_mutation_id) DO NOTHING` as a second conflict target, or use `ON CONFLICT ON CONSTRAINT ... DO UPDATE`.

### SP-08 The web dashboard shows "absent / excused" merged in one section with no per-category count
**File:** `web/app/(admin)/overview/page.tsx:61`

```tsx
const other = roster.filter(s => s.status === 'absent' || s.status === 'excused')
```

Absent and excused students are combined in one section labelled "Absent / Excused" without separate counts or visual distinction. An admin scanning the dashboard cannot quickly see how many are formally absent vs. excused. Fix: separate into two sections, or add `StatusBadge` colouring to distinguish within the combined list (already partially done via `StatusBadge`).

### SP-09 `result_slips` lacks a size or type constraint on `file_path` / Storage upload
**File:** `iOS/…/Services/AttendanceService.swift:384–386`

```swift
try await db.storage.from("result-slips")
    .upload(path: path, file: fileData, options: .init(contentType: mime, upsert: false))
```

No maximum file size is enforced client-side. A user could upload a 100MB video as a "result slip". Supabase Storage defaults to 50MB per file, but this limit is not documented or surfaced to the user. Fix: add a client-side file size check (e.g., 10MB) and show an error before attempting the upload.

### SP-10 iOS `ResumeSession` uses a custom `Encodable` to send `null` — fragile pattern
**File:** `iOS/…/Services/AttendanceService.swift:153–165`

The `Patch` struct has a custom `encode(to:)` that explicitly encodes `nil` for `ended_at`. This works around the Supabase Swift SDK's behaviour of skipping nil values (which would produce an empty patch, leaving `ended_at` unchanged). If the SDK changes this behaviour in a future version, `resumeSession` would silently stop clearing `ended_at`. Fix: switch to passing a raw dictionary (`["ended_at": NSNull()]`) or check whether the SDK now supports an explicit nil-encoding option.

---

*End of IMPROVEMENTS.md — implemented findings removed 2026-06-15; remaining items are open.*
