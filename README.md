# TAVA Attendance

iPad-native attendance system for TAVA tutoring centre. Built with SwiftUI and Supabase.

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

- **iOS**: SwiftUI, targeting iPad (iPadOS 17+)
- **Backend**: Supabase (Postgres + PostgREST + Auth)
- **Offline**: `PendingAttendanceStore` (UserDefaults) → `sync_attendance` RPC on reconnect

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
    Kiosk/        GlobalKioskView (main kiosk), KioskView (unused stub)
    Session/      SessionListView, RosterView, StudentProfileView

supabase/
  migrations/
    001_schema.sql   Core tables + Phase 2/3 stubs
    002_rls.sql      Row-level security for all tables
    003_functions_triggers.sql  RPCs, audit triggers, attendance_summary view
  seed.sql
```

## Running locally

```bash
# 1. Install Supabase CLI and start local stack
supabase start

# 2. Apply migrations
supabase db reset

# 3. Open iOS project
open iOS/TAVAttendance.xcodeproj
# Edit Core/SupabaseManager.swift with your Supabase URL + anon key
# Run on an iPad simulator or connected iPad
```

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
- **Student photo** on the kiosk card (add `avatar_url` to students, store in Supabase Storage)
- **Push notifications** via APNs: notify parent when child is marked late or absent
- **Teacher notes per session**: the `sessions.notes` column exists, just needs a UI field in RosterView
- **Bulk absent marking**: "Mark all unmarked as absent" button for end-of-class cleanup
- **QR / NFC sign-in**: student scans a QR on entry instead of tapping their name card
