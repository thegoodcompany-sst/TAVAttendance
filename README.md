# TAVA Attendance

Attendance system for TAVA tutoring centre. An iPad-native kiosk (SwiftUI), an
Android app (Jetpack Compose), and a web admin dashboard (Next.js), all backed by
the same Supabase project.

See **[CONTRIBUTING.md](CONTRIBUTING.md)** for full local setup of every platform.
Agents: project rules live in [CLAUDE.md](CLAUDE.md); task runbooks in `.claude/skills/tava-*`.

## What it does today

| Feature | Who uses it |
|---|---|
| Global sign-in kiosk (all classes, one iPad) | Students |
| Auto-marks late based on class start time | Kiosk |
| Long-press to force-late or "not here" | Anyone at kiosk |
| PIN-locked kiosk with admin override mode | Admin |
| Per-class roster with P/A/L/E marking | Teachers |
| Arrival time display in roster | Teachers |
| Student attendance history (tap any roster row) | Teachers |
| Class management (create / edit / deactivate) | Admin |
| Student enrolment per class | Admin |
| Tutor assignment per class | Admin |
| Offline marking with automatic sync on reconnect | Everyone |

## Stack

- **iOS**: SwiftUI, targeting iPad (iPadOS 17+) — `iOS/`
- **Android**: Kotlin + Jetpack Compose — `Android/`
- **Web**: Next.js admin dashboard — `web/`
- **Backend**: Supabase (Postgres + PostgREST + Auth + Storage) — `supabase/`
- **Offline (iOS/Android)**: pending store → `sync_attendance` RPC on reconnect

### Platforms

| Platform | Directory | Run |
|---|---|---|
| iOS (kiosk + teacher) | `iOS/` | `open iOS/TAVAttendance.xcodeproj` |
| Android | `Android/` | `cd Android && ./gradlew installDebug` |
| Web (admin dashboard) | `web/` | `cd web && npm install && npm run dev` |

Each platform reads Supabase credentials from a gitignored config file — see
[CONTRIBUTING.md](CONTRIBUTING.md). Feature flags in the `feature_flags` table gate
in-progress features (parent portal, push notifications, student photos, study space
tracking, test mode, session notes, QR sign-in, awards); they ship OFF.

## Project layout

```
iOS/TAVAttendance/
  Core/           AuthManager, NetworkMonitor, PendingAttendanceStore, SupabaseManager
  Models/         Models.swift — all value types and Codable structs
  Services/       AttendanceService.swift — single service, all Supabase calls
  Views/
    Admin/        Class, student, enrolment, tutor-assignment management
    Auth/         LoginView
    Classes/      ClassListView (teacher entry point)
    Kiosk/        GlobalKioskView (main kiosk), StudySpaceView, QRScannerView (flag-gated)
    Parent/       ParentDashboardView (flag-gated parent portal)
    Session/      SessionListView, RosterView, StudentProfileView
    Tutor/        StudentResultsView (tutor results entry)

Android/          Kotlin + Jetpack Compose app (see Android/PORTING_NOTES.md)
web/              Next.js admin dashboard
supabase/
  migrations/     001…027 (see supabase/migrations/README.md for the down-migration convention)
  functions/      notify-parent edge function (PROD-02, flag-gated)
  seed.sql
```

## Running locally

```bash
# 1. Install Supabase CLI and start local stack
supabase start

# 2. Apply migrations
supabase db reset

# 3. Configure iOS credentials (NOT by editing source)
cp iOS/Config.xcconfig.example iOS/Config.xcconfig
# Fill in SUPABASE_PROJECT_URL + SUPABASE_ANON_KEY. These are read from Info.plist
# via $(SUPABASE_PROJECT_URL) in SupabaseManager.swift — do not hardcode them in code.

# 4. Open and run the iOS project
open iOS/TAVAttendance.xcodeproj
# Run on an iPad simulator or connected iPad
```

For Android (`Android/secrets.properties`) and Web (`web/.env.local`) credential
setup, plus the Supabase Storage buckets and the local test checklist, see
[CONTRIBUTING.md](CONTRIBUTING.md).

## User accounts

Admins invite users from the web dashboard (**/users** page — email + role, sends a
Supabase invite that lands on the set-password page). The Supabase Dashboard
(**Authentication → Invite User** with `raw_user_meta_data`
`{ "full_name": "Teacher Name", "role": "tutor" }`) remains the manual fallback.

Roles: `admin`, `tutor`, `parent`. A trigger (`handle_new_user`) auto-creates the `profiles` row.
Linking parents to children (`parent_student_links`) is still a manual SQL insert.

---

## Roadmap

### Phase 2 — Parent Portal
Tables already exist in the schema (`result_slips`, `messages`). RLS is admin-only until implemented.

- **Attendance visibility**: parents see their child's attendance history (RLS policy already written)
- **Result slip uploads**: parents upload exam score slips → admin/tutor acknowledges → stored in Supabase Storage via `result_slips` table
- **Messaging**: direct messaging between centre and parent via `messages` table
- **Parent app tab**: new tab visible only to `parent` role accounts

### Phase 2 — Analytics Dashboard (admin) — SHIPPED 2026-07-10
- Web **/analytics**: per-student-per-class attendance % (from `attendance_summary`) + monthly-drop watchlist
- When the `test_mode` flag is OFF, analytics filters to tuition days (Mon/Thu) so test data stays hidden
- Awards system — *built, behind the `awards` flag*: web **/awards** computes candidates from `attendance_summary` and records rows in `awards`

### Phase 3 — Dismissal & Safety (partially live)
- Kiosk dismissal marking is LIVE — admin dismisses a student (purple card), stored in `dismissals`
- Parent push on late/absent: backend wired end-to-end (migration 021 trigger + APNs sender in
  `notify-parent`) but inert until credentials are supplied (HUMANS.md §17) and the
  `push_notifications` flag flips; "safely home" confirmation still open

### Phase 3 — Food/Event Ordering
- `food_polls` table exists — centre creates a poll (e.g. "Hari Raya lunch order"), students/parents respond
- Admin sees aggregated order, no manual WhatsApp collection

### Near-term improvements (no new tables needed)
- **Student photo** on the kiosk card — *built, behind the `student_photos` flag* (`avatar_url` + `student-photos` bucket)
- **Push notifications** via APNs/FCM — *scaffolded, behind the `push_notifications` flag* (`device_tokens` + `notify-parent` edge function; needs real APNs/FCM keys)
- **Parent portal** — *built, behind the `parent_portal` flag* (iOS `ParentDashboardView`, Android `ParentDashboardScreen`, web `/parent`)
- **Bulk absent marking** — *shipped*: "Mark rest absent" in the roster
- **Teacher notes per session** — *built, behind the `session_notes` flag* (iOS/Android roster + web session detail)
- **QR sign-in** — *built, behind the `qr_sign_in` flag*: kiosk camera scanner reusing the tap-to-sign path; web prints per-student QR codes (NFC still open)
