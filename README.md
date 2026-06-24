# TAVA Attendance

Attendance system for TAVA tutoring centre. An iPad-native kiosk (SwiftUI), an
Android app (Jetpack Compose), and a web admin dashboard (Next.js), all backed by
the same Supabase project.

See **[CONTRIBUTING.md](CONTRIBUTING.md)** for full local setup of every platform.

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
in-progress features (parent portal, push notifications, student photos); they ship OFF.

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
    Kiosk/        GlobalKioskView (main kiosk)
    Parent/       ParentDashboardView (flag-gated parent portal)
    Session/      SessionListView, RosterView, StudentProfileView

Android/          Kotlin + Jetpack Compose app (see Android/PORTING_NOTES.md)
web/              Next.js admin dashboard
supabase/
  migrations/     001…014 (see supabase/migrations/README.md for the down-migration convention)
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

Users are invited via the **Supabase Dashboard → Authentication → Invite User**.  
Set `raw_user_meta_data` on the invite:

```json
{ "full_name": "Teacher Name", "role": "tutor" }
```

Roles: `admin`, `tutor`, `parent`. A trigger (`handle_new_user`) auto-creates the `profiles` row.

---

## Roadmap

### Phase 2 — Parent Portal
Tables already exist in the schema (`result_slips`, `messages`). RLS is admin-only until implemented.

- **Attendance visibility**: parents see their child's attendance history (RLS policy already written)
- **Result slip uploads**: parents upload exam score slips → admin/tutor acknowledges → stored in Supabase Storage via `result_slips` table
- **Messaging**: direct messaging between centre and parent via `messages` table
- **Parent app tab**: new tab visible only to `parent` role accounts

### Phase 2 — Analytics Dashboard (admin)
- The `attendance_summary` view is already live in Postgres — wire it up to a dashboard screen
- Attendance % per class, per student, trend over time
- Awards system (`awards` table exists): flag students with perfect attendance, most improved, etc.

### Phase 3 — Dismissal & Safety
- `dismissals` table exists — record when each student leaves and "safely home" confirmation
- Tutor taps student to dismiss; parent receives push notification and confirms arrival home
- Useful for younger students where parents want pick-up confirmation

### Phase 3 — Food/Event Ordering
- `food_polls` table exists — centre creates a poll (e.g. "Hari Raya lunch order"), students/parents respond
- Admin sees aggregated order, no manual WhatsApp collection

### Near-term improvements (no new tables needed)
- **Student photo** on the kiosk card — *built, behind the `student_photos` flag* (`avatar_url` + `student-photos` bucket)
- **Push notifications** via APNs/FCM — *scaffolded, behind the `push_notifications` flag* (`device_tokens` + `notify-parent` edge function; needs real APNs/FCM keys)
- **Parent portal** — *built, behind the `parent_portal` flag* (iOS `ParentDashboardView`, web `/parent`)
- **Bulk absent marking** — *shipped*: "Mark rest absent" in the roster
- **Teacher notes per session**: the `sessions.notes` column exists, just needs a UI field in RosterView
- **QR / NFC sign-in**: student scans a QR on entry instead of tapping their name card
