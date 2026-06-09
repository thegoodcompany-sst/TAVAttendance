# CLAUDE.md — Agent knowledge for TAVA Attendance

Things that cannot be derived by reading the codebase. Read this before writing any code.

---

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

### `fetchKioskEntries` creates sessions as a side effect
Every time the kiosk tab loads, `getOrCreateSession` is called for every active class. This means today's session rows exist in Postgres from the moment the kiosk is first opened, even if no one has attended yet. This is intentional (so the roster is ready before class starts) but be aware when querying session counts.

### Offline sync idempotency
`PendingAttendanceStore` persists pending records in UserDefaults. The `sync_attendance` Postgres function uses `ON CONFLICT ... WHERE marked_at <= EXCLUDED.marked_at` — a more recent server record will NOT be overwritten by an older offline record. Device clock accuracy matters; if a device's clock is badly wrong, sync may silently skip its records.

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
| `dismissals` | Student pick-up & "safely home" tracking | Schema only |
| `food_polls` | Event food ordering by centre | Schema only |
| `food_poll_responses` | Student/parent responses | Schema only |

The `attendance_summary` **view** is live and queryable — it aggregates attendance % per student per class. Good starting point for an admin analytics screen.

---

## User management (no UI exists yet)

All user accounts are created via the **Supabase Dashboard** (or Supabase CLI):

```
Dashboard → Authentication → Users → Invite User
Email: teacher@example.com
Metadata: { "full_name": "Wayne Tan", "role": "tutor" }
```

The `handle_new_user` trigger auto-creates the `profiles` row. The `role` field must be one of `admin`, `tutor`, or `parent` — checked at the DB level.

To link a parent to their child(ren), insert into `parent_student_links`:
```sql
INSERT INTO parent_student_links (parent_id, student_id)
VALUES ('<parent_auth_uuid>', '<student_uuid>');
```

No UI for this exists yet. It's a common first ask when the parent role is activated.

---

## Testing procedures

There is no automated test suite. Manual testing checklist:

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
| iOS | `bash scripts/test_ios.sh` | `iOS/` |
| Android | `./gradlew test` | `Andriod/` (note: directory name is misspelled in repo) |
| Web | `pnpm test` | `web/` |

---

## Cross-platform parity workflow

After implementing any iOS feature, before declaring the task done:

1. Run `git diff --stat HEAD~N..HEAD -- iOS/` to summarise the iOS files touched.
2. Output a **paste-ready prompt block** (see template below) under a heading **"📋 Android port handoff"** containing:
   - One-paragraph feature summary (what was built and why).
   - Bulleted list of iOS files changed with a one-line purpose each.
   - Equivalent Android file targets (see `Andriod/PORTING_NOTES.md` for the mapping once it exists; until then, use the mapping table at the bottom of this section).
   - Any new Supabase columns, RPCs, or Storage buckets the Android code must call.
   - A sample unit test the Android agent should write (mirroring the corresponding iOS XCTest).
3. Output the same block under **"📋 Web port handoff"** for the `web/` package.

> **The user pastes each block into a fresh agent invocation — do NOT spawn the porting agent automatically.** Each port is a separate review cycle.

### iOS → Android file mapping (until PORTING_NOTES.md exists)

| iOS file | Android equivalent |
|---|---|
| `Models/Models.swift` | `data/models/Models.kt` |
| `Services/AttendanceService.swift` | `data/service/AttendanceService.kt` |
| `Views/Kiosk/GlobalKioskView.swift` | `screens/kiosk/GlobalKioskScreen.kt` |
| `Views/Session/StudentProfileView.swift` | `screens/StudentProfileSheet.kt` |
| `Views/Session/RosterView.swift` | `screens/RosterScreen.kt` |
| `Views/Session/SessionListView.swift` | `screens/SessionListScreen.kt` |
| `Views/Admin/ClassFormView.swift` | `screens/ClassFormDialog.kt` |
| `Views/Admin/StudentManagementView.swift` | `screens/StudentManagementScreen.kt` |
| `Views/Admin/ExportView.swift` | *(new)* `screens/ExportScreen.kt` |
| `Views/Admin/StudentImportView.swift` | *(new)* `screens/StudentImportScreen.kt` |
| `Views/Admin/ParentLinkView.swift` | *(new)* `screens/ParentLinkScreen.kt` |

### Paste-ready prompt template

```
You are porting iOS feature changes to the Android app at
/Users/limboenedmund/Documents/apps/TAVA/TAVAttendance/Andriod/
(note: directory name is misspelled — "Andriod" not "Android").

## Feature summary
[one paragraph]

## iOS files changed
- `iOS/TAVAttendance/[path]` — [purpose]

## Android targets
- `Andriod/app/src/main/java/com/example/tavattendance/[path]` — [purpose]

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
| Android | `app/build.gradle.kts` → `buildConfigField` | Defined in `defaultConfig` block. Accessed via `BuildConfig.SUPABASE_PROJECT_URL` in `SupabaseClient.kt`. |
| Web | Environment variables (`NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`) | Standard Next.js pattern. Set in Vercel dashboard or `.env.local`. |

## Error handling improvements

All three platforms now use structured error handling instead of silent catches:

- **iOS**: New `AppError` type (`Core/AppError.swift`) + `View.errorAlert()` modifier. Errors surface as alerts with retry/dismiss options. Updated views: `GlobalKioskView`, `SessionListView`, `SessionDetailView`, `ExportView`.
- **Web**: Query functions in `lib/queries.ts` now throw `Error` on failure (previously returned `[]`). Callers should use error boundaries or try/catch.
- **Android**: Uses `runCatching` extensively; error handling is a known gap (most results are not inspected). See `SessionListScreen.kt`, `RosterScreen.kt`, `GlobalKioskScreen.kt` for patterns.

## `.claude/settings.json`

`bgIsolation` is set to `"none"`. This was required because this project had uncommitted local changes when the first background agent session started — the default worktree would have branched from `origin/main`, missing the local changes entirely.  
If you start fresh (clean commit on main), you can remove this setting to re-enable worktree isolation for background agents.
