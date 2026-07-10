# CLAUDE.md — Agent knowledge for TAVA Attendance

Things that cannot be derived by reading the codebase. Read this before writing any code.

---

## Skill library (start here)

`.claude/skills/tava-*` (13 skills, authored 2026-07-09) is the expanded, task-routed version
of this file — load the matching skill before working: `tava-change-control` (before any change),
`tava-debugging-playbook` (anything misbehaves), `tava-prod-drift-campaign` (prod migrations —
the top open problem), `tava-failure-archaeology` (before proposing a fix), plus references for
architecture, Supabase, PDPA, config/flags, build, operations, QA, docs, and roadmap. This file
stays the compact source of truth; the skills carry the runbooks.

## Migrations

Prod Supabase (`zgikcbsxzjgbigywxbbj`) was reconciled with the migration files on **2026-07-09**
(drift campaign; HUMANS.md §14/§30) and is tracked by the CI drift detector — as of
**2026-07-10** prod matches migrations 001–022. **Never edit an
existing migration; every schema fix ships as a new numbered one**, and apply it to prod BEFORE
deploying app code that references it. Verify prod state with queries, never by reading files:
`.claude/skills/tava-prod-drift-campaign` keeps the drift-prevention protocol.

## Architecture decisions worth knowing

### The kiosk iPad must be signed in as an admin account
`fetchKioskEntries` calls `fetchMyClasses()` which issues `SELECT * FROM classes WHERE is_active = TRUE`.  
The RLS policy for tutors filters to `tutor_owns_class(classes.id)` — so a tutor-logged-in iPad would only see their own assigned classes, making the global kiosk useless.  
**Operational rule: the kiosk iPad (Sign In tab) should always be logged into an admin account.**

### `schedule_time` is a Postgres `TIME` column, not TEXT
The schema stores `schedule_time TIME`. PostgREST returns `TIME` columns as strings in `"HH:mm:ss"` format (e.g., `"20:00:00"`), not `"HH:mm"`.  
The iOS auto-late logic in `AttendanceService.markKioskSignIn` splits on `":"` and takes indices 0 and 1, so both formats work. ClassFormView accepts free text (e.g. `"20:00"`), which Postgres coerces to the TIME type on insert. Do not change the parsing logic to assume exactly two components.

### `fetchStudentAttendanceHistory` depends on PostgREST FK inference
The query uses the alias syntax: `session:sessions(session_date, class:classes(name))`.  
PostgREST resolves this via the FK chain: `attendance_records.session_id → sessions.id` and `sessions.class_id → classes.id`.  
If either FK is ever renamed or the column renamed, update the select string in `AttendanceService.fetchStudentAttendanceHistory` to match.

### `fetchKioskEntries` creates sessions as a side effect (day-aware as of migration 015)
Every time the kiosk tab loads, `getOrCreateSession` is called for every active class **scheduled for today**, so today's session rows exist in Postgres from the moment the kiosk is opened, even if no one has attended yet. This is intentional (so the roster is ready before class starts) but be aware when querying session counts.
As of migration 015 the kiosk filters classes to today via `AttendanceService.classMeetsToday` (iOS): a class matches when its `recurrence_rule` BYDAY contains today's 2-letter code, **or** its `schedule_day` equals today's English weekday, **or** it has neither set (ad-hoc → always shown). TAVA tuition is Mon (Math) + Thu (English/Reading), so opening the kiosk on any other day shows "No Classes Today" rather than creating phantom sessions. `fetchMyClasses` also excludes the Study Space class (`is_study_space = TRUE`).

### Offline sync idempotency
`PendingAttendanceStore` persists pending records in UserDefaults. The `sync_attendance` Postgres function uses `ON CONFLICT ... WHERE marked_at <= EXCLUDED.marked_at` — a more recent server record will NOT be overwritten by an older offline record. Device clock accuracy matters; if a device's clock is badly wrong, sync may silently skip its records. As of migration 013 the function returns `{synced, skipped, blocked_ended_session}` — `blocked_ended_session` counts records rejected because their session had already ended (distinct from `skipped`, which means a newer server record won), and a second `ON CONFLICT (client_mutation_id) DO NOTHING` path prevents an unhandled unique-violation.

### Feature flags
The `feature_flags` table (migration 012) gates in-progress features; flags ship OFF. Read it via `FeatureFlagStore` (iOS, `Services/FeatureFlags.swift`), `FeatureFlags` (Android), or `getFeatureFlags()` (web, `lib/feature-flags.ts`). Current keys: `parent_portal` (PROD-01), `push_notifications` (PROD-02), `student_photos` (PROD-04), `study_space_tracking` (migration 015 — see below), `test_mode` (migration 020 — kiosk shows all classes regardless of weekday, web analytics shows all days; seeded ON only for demo day 2026-07-11, normally OFF — see below). Flipping a flag is admin-only (RLS); the web toggle UI (`web/app/(admin)/feature-flags/`) is superadmin-only and renders every row generically, so seeding a new flag row makes its toggle appear automatically. The parent portal needs no new RLS — parent read policies for `students`/`attendance_records` already exist in `002_rls.sql`.

### Study Space tracking (`study_space_tracking`, migration 015) — INTERNAL ONLY
TAVA also runs an open drop-in study space (Mon–Fri 12–6pm) separate from tuition. This feature lets staff record who is in that room. It is modelled as a **single flagged class** (`classes.is_study_space = TRUE`, fixed UUID `57000000-0000-0000-0000-000000000001`) so it reuses the sessions/attendance_records/offline stack. Roster = **all active students** (not enrollment-based, via the `get_study_space_roster` RPC). Status is **Present / Not Here (`excused`) only** — no late/absent, no auto-late. Marked on the **iPad kiosk** (`StudySpaceView`, reached from the kiosk header when the flag is on); no web marking UI.

**INVARIANT — study-space attendance is internal reference ONLY and must NEVER appear in any report, report card, or parent view.** Enforced by excluding `classes.is_study_space = TRUE` at the source: the `attendance_summary` view and `get_roster_for_date` RPC (migration 015), plus `fetchMyClasses` (hides the class from the kiosk/class list/export picker), iOS `fetchStudentAttendanceHistory`, and the web queries `getTodaySessions` / `getDailyAttendance` / `getStudentRecentRecords`. **Any new report / report-card / parent query MUST filter `classes.is_study_space = FALSE`.**

### `test_mode` (migration 020) — demo/testing on non-tuition days
When ON: `fetchKioskEntries` (iOS) skips the `classMeetsToday` day filter so every
active class appears on the kiosk, and the web analytics (`getDailyAttendance`,
`getMonthlyAttendanceDrops`) include all days. When OFF: web analytics filter to
tuition days (Mon/Thu, `isTuitionDay` in `web/lib/date.ts`) so test/demo sessions on
other days stay invisible. `attendance_summary` (the view) is deliberately NOT
filtered — after any test-mode session, the demo-day rows must be **deleted**
(HUMANS.md §37) or they permanently skew attendance percentages. iOS loads flags once
at sign-in — relaunch the app after flipping.

---

## Kiosk admin mode

| State | Behaviour |
|---|---|
| No PIN configured | Always in admin mode (suitable for demos and testing) |
| PIN configured, kiosk locked | Student-facing mode; tab bar hidden; only sign-in grid shown |
| PIN configured, unlocked | Admin mode; gear icon visible; `isAdminUnlocked = true` |

Admin mode persists until the kiosk is re-locked (gear → Lock Kiosk Now). It does NOT persist across app restarts — `isAdminUnlocked` is a `@State` var, not persisted.

### Kiosk status semantics

| Kiosk shows | DB row | Card colour | Tappable? |
|---|---|---|---|
| Unsigned | `attendance_records` row absent or `nil` status | Grey (default) | Yes → auto sign-in |
| On Time | `.present` | Green | No (admin: tap to override) |
| Late | `.late` | Orange | No (admin: tap to mark On Time) |
| Late + reason | `.late` + `late_reason IS NOT NULL` | Orange + `info.circle.fill` glyph | Admin: tap glyph to see reason |
| Not Here | `.excused` | Grey (default) | Yes → student can still sign in |
| Absent | `.absent` | Red | No (admin context-menu only) |
| Dismissed | `.present` or `.late` + row in `dismissals` table | Purple | No (admin: long-press → Undo Dismissal) |

**"Not Here" vs "Absent" vs "Dismissed"**:
- **Not Here** (excused): soft undo — card goes grey, student can tap to sign in again.
- **Absent**: hard admin mark (red, context-menu only). Cannot be undone by the student.
- **Dismissed**: student was physically present (attendance row unchanged, counts toward attendance %) but has been signed out early by admin. Stored in the `dismissals` table, not `attendance_records`. Purple card with a secondary label showing the original On Time / Late status underneath.

### Status aggregation across multiple sessions
When a student is enrolled in more than one class today, `KioskEntry.status` is the "worst" status across all their sessions: `late > present > absent > excused`. The merge logic is in `AttendanceService.worstStatus(_:_:)`.

---

## Dead code

`KioskView.swift` — a single-class kiosk view — was removed (it was not wired to any navigation path and predated the global kiosk). If a per-class kiosk mode is needed later, it can be recreated from `GlobalKioskView.swift` as a reference.

---

## Phase 2/3 tables (created, not yet implemented)

These tables exist in Postgres and have RLS enabled (admin-only until implemented):

| Table | Purpose | Status |
|---|---|---|
| `result_slips` | Exam score slips uploaded by parents | Schema only |
| `messages` | Centre ↔ parent direct messages | Schema only |
| `awards` | Attendance/punctuality awards | Schema only |
| `dismissals` | Student pick-up & "safely home" tracking | Kiosk marking LIVE (purple card, admin long-press); "safely home" confirmation not built |
| `food_polls` | Event food ordering by centre | Schema only |
| `food_poll_responses` | Student/parent responses | Schema only |

The `attendance_summary` **view** is live and queryable — it aggregates attendance % per student per class. Good starting point for an admin analytics screen.

---

## User management

Admins invite users from the web dashboard (`web/app/(admin)/users/` + the
`invite` server action — email + role; the invitee lands on the set-password page).
The Supabase Dashboard (**Authentication → Users → Invite User** with metadata
`{ "full_name": "Wayne Tan", "role": "tutor" }`) remains the manual fallback.
The `handle_new_user` trigger auto-creates the `profiles` row. The `role` field must be one of `admin`, `tutor`, or `parent` — checked at the DB level.

To link a parent to their child(ren), insert into `parent_student_links` (still no UI —
a common first ask when the parent role is activated):
```sql
INSERT INTO parent_student_links (parent_id, student_id)
VALUES ('<parent_auth_uuid>', '<student_uuid>');
```

---

## Testing procedures

Automated coverage exists for the riskiest pure logic only: iOS `TAVAttendanceTests`
(auto-late `signInStatus` parsing + `worstStatus` merge), Android `DayAwareKioskTest`, and
`supabase/tests/sync_attendance_test.sql` (offline-sync idempotency — plain SQL asserts,
runs in one transaction and rolls back, safe against any environment). Everything else is
manual. Manual testing checklist:

### Kiosk sign-in flow
1. Log in as admin, open Sign In tab.
2. Ensure at least one class has a `schedule_time` set in the past (e.g., 08:00 if it's afternoon).
3. Tap a student → card should go **orange** (Late) if class time has passed, **green** (On Time) if not.
4. Long-press a green card → context menu should offer "Mark as Late" and "Mark as Not Here".
5. Tap "Mark as Late" → card turns orange.
6. Long-press an orange card → context menu should offer "Mark as Not Here".
7. Tap "Mark as Not Here" → card returns to grey, student name is still listed but card is tappable again.
8. Tap the grey card → should auto-sign-in again (late or on time based on time).

### Admin mode
1. Set a PIN via gear → Kiosk Settings → Set PIN → Lock Kiosk Now.
2. Tap the lock icon, enter PIN → "ADMIN" badge should appear in the header.
3. Sign in a student (gets marked Late). Tap the orange card → should change to On Time (green).
4. Long-press any signed-in card → context menu should include "Mark as Absent" (red, destructive).
5. Lock the kiosk again → ADMIN badge disappears; absent/late overrides are no longer available by tap.

### Teacher roster
1. Log in as a tutor, go to Classes → pick a class → Start Today's Class.
2. Mark one student as Present. Confirm "Marked HH:MM AM/PM" appears under their name.
3. Tap a student row → Student Profile sheet should open with recent attendance history.
4. Turn off Wi-Fi. Mark a student. Orange dot should appear next to their name.
5. Turn Wi-Fi back on. Orange dot should clear (sync happened automatically).

### Student profile history
- The `fetchStudentAttendanceHistory` query uses a PostgREST join. If the sheet shows a blank list with no error, check the Supabase logs for a PostgREST 400 — the FK join string may be mismatched.

---

## Running tests

| Platform | Command | Working directory |
|---|---|---|
| iOS | `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project TAVAttendance.xcodeproj -scheme TAVAttendance -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO` (scheme name from `project.yml`; project is XcodeGen-managed — run `xcodegen generate` first if `.xcodeproj` is stale) | `iOS/` |
| Android | `./gradlew testDebugUnitTest` (includes `DayAwareKioskTest`) — JDK 21 installed (`temurin@21`), unblocking the AGP `jlink` transform that failed under JDK 26 | `Android/` |
| Web | `npm run build` / `npm run lint`; deploy via the `/deploy` skill (Vercel, dash.thegoodcompanysg.dev) | `web/` |

On this machine iOS builds **must** set `DEVELOPER_DIR` to Xcode-beta and pass
`CODE_SIGNING_ALLOWED=NO`. A failure at `CodeSign swift-crypto_Crypto.bundle` is a
pre-existing local keychain issue, not a code problem — do not try to "fix" it.

---

## Cross-platform parity workflow

After implementing any iOS feature, before declaring the task done:

1. Run `git diff --stat HEAD~N..HEAD -- iOS/` to summarise the iOS files touched.
2. Output a **paste-ready prompt block** (see template below) under a heading **"📋 Android port handoff"** containing:
   - One-paragraph feature summary (what was built and why).
   - Bulleted list of iOS files changed with a one-line purpose each.
   - Equivalent Android file targets (see `Android/PORTING_NOTES.md` for the mapping).
   - Any new Supabase columns, RPCs, or Storage buckets the Android code must call.
   - A sample unit test the Android agent should write (mirroring the corresponding iOS XCTest).
3. Output the same block under **"📋 Web port handoff"** for the `web/` package.

> **The user pastes each block into a fresh agent invocation — do NOT spawn the porting agent automatically.** Each port is a separate review cycle.

### iOS → Android file mapping

The authoritative mapping now lives in `Android/PORTING_NOTES.md`. Quick reference:

| iOS file | Android equivalent |
|---|---|
| `Models/Models.swift` | `data/models/Models.kt` |
| `Services/AttendanceService.swift` | `data/service/AttendanceService.kt` |
| `Services/FeatureFlags.swift` | `data/service/FeatureFlags.kt` |
| `Views/Kiosk/GlobalKioskView.swift` | `screens/kiosk/GlobalKioskScreen.kt` |
| `Views/Parent/ParentDashboardView.swift` | `screens/ParentDashboardScreen.kt` *(UI pending)* |
| `Views/Session/StudentProfileView.swift` | `screens/StudentProfileSheet.kt` |
| `Views/Session/RosterView.swift` | `screens/RosterScreen.kt` |
| `Views/Admin/ClassFormView.swift` | `screens/ClassFormDialog.kt` |
| `Views/Admin/StudentManagementView.swift` | `screens/StudentManagementScreen.kt` |

### Paste-ready prompt template

```
You are porting iOS feature changes to the Android app at
/Users/limboenedmund/Documents/apps/TAVA/TAVAttendance/Android/

## Feature summary
[one paragraph]

## iOS files changed
- `iOS/TAVAttendance/[path]` — [purpose]

## Android targets
- `Android/app/src/main/java/com/example/tavattendance/[path]` — [purpose]

## New Supabase schema (must be consumed by Android)
- [list new columns, RPCs, buckets]

## Sample test to write
[paste the equivalent iOS XCTest case as pseudo-Kotlin]

Implement all changes. Match existing Kotlin/Compose patterns in the repo.
Do not change any Supabase migration files — they are shared.
```

---

## Supabase credentials configuration

Credentials are no longer hardcoded in source. Each platform loads them at build/runtime:

| Platform | Location | Notes |
|---|---|---|
| iOS | `Config.xcconfig` (gitignored) → `Info.plist` via `$(SUPABASE_PROJECT_URL)` | Copy `Config.xcconfig.example` to `Config.xcconfig` and fill in values. Read via `Bundle.main.object(forInfoDictionaryKey:)` in `SupabaseManager.swift`. |
| Android | `Android/secrets.properties` (gitignored) → `buildConfigField` | Copy `secrets.properties.example` to `secrets.properties` and fill in values (or set env vars in CI). `build.gradle.kts` reads it at configure time; accessed via `BuildConfig.SUPABASE_PROJECT_URL` in `SupabaseClient.kt`. |
| Web | Environment variables (`NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`) | Standard Next.js pattern. Set in Vercel dashboard or `.env.local`. |

## Error handling improvements

All three platforms now use structured error handling instead of silent catches:

- **iOS**: New `AppError` type (`Core/AppError.swift`) + `View.errorAlert()` modifier. Errors surface as alerts with retry/dismiss options. Updated views: `GlobalKioskView`, `SessionListView`, `SessionDetailView`, `ExportView`.
- **Web**: Query functions in `lib/queries.ts` now throw `Error` on failure (previously returned `[]`). Callers should use error boundaries or try/catch.
- **Android**: Uses `runCatching` extensively; error handling is a known gap (most results are not inspected). See `SessionListScreen.kt`, `RosterScreen.kt`, `GlobalKioskScreen.kt` for patterns.
