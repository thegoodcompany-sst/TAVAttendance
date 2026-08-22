# TAVA Attendance — Every child accounted for

Student-operations system for TAVA's nonprofit tuition centre. Its core promise
is **every child accounted for**. An iPad-native kiosk (SwiftUI), Android app
(Jetpack Compose), and web admin dashboard (Next.js) share one Supabase backend.

TAVA is not a payments, accounting, payroll, CRM, or business-ERP product. It
focuses on the student journey and the evidence staff need to act safely.

See **[CONTRIBUTING.md](CONTRIBUTING.md)** for full local setup of every platform.
Agents: project rules live in [AGENTS.md](AGENTS.md) (`CLAUDE.md` stubs to it);
next-build plans in [NEXT_BUILD_CHANGES.md](NEXT_BUILD_CHANGES.md); deploy and
release runbooks in `.claude/skills/`.

## What it does today

| Feature | Who uses it |
|---|---|
| Global sign-in kiosk (all classes, one iPad) | Students |
| Auto-marks late based on class start time | Kiosk |
| Long-press to force-late or "not here yet" | PIN-unlocked kiosk admin |
| PIN-locked kiosk with admin override mode | Admin |
| Per-class roster with P / A / L marking (unmarked = Not Here Yet) | Teachers |
| Arrival time display in roster | Teachers |
| Student attendance history (tap any roster row) | Teachers |
| Class management (create / edit / deactivate) | Admin |
| Student enrolment per class | Admin |
| Tutor assignment per class | Admin |
| Parent↔student account linking | Admin |
| Parent attendance, result-slip upload, and centre messaging (flag-gated) | Parents |
| Result-slip acknowledgement and parent-message replies | Admin |
| Human-readable audit activity (actor + action + entity) | Admin |
| Offline marking with automatic sync on reconnect | Staff |

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
| Web (admin dashboard) | `web/` | `cd web && bun install && bun run dev` |

Each platform reads Supabase credentials from a gitignored config file — see
[CONTRIBUTING.md](CONTRIBUTING.md). Feature flags in the `feature_flags` table gate
in-progress features (parent portal, push notifications, student photos, study space
tracking, test mode, session notes, QR sign-in, awards, analytics, and retrospective
sessions); they ship OFF unless a migration explicitly documents otherwise.

## Project layout

```
iOS/TAVAttendance/
  Core/           AuthManager, NetworkMonitor, PendingAttendanceStore, SupabaseManager
  Models/         Database DTOs and domain values
  Services/       Focused AttendanceService extensions and supporting services
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
  migrations/     Append-only schema history (indexed in supabase/migrations/README.md)
  functions/      notification + durable private-Storage cleanup workers
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
Supabase invite that lands on the set-password page). This is the supported path:
new-user metadata is deliberately not trusted for authorization, so a Dashboard
invite is created as the least-privileged `parent` until an admin assigns its role
through a trusted admin path.

Roles: `admin`, `tutor`, `parent`. A trigger (`handle_new_user`) auto-creates the `profiles` row.
Admins link parent accounts to children from **/users**; the UI calls the existing
`link_parent_student` / `unlink_parent_student` RPCs.

---

## Roadmap

### Student Assurance direction — PLANNED, NOT SHIPPED

The September 2026 priority is a two-month pilot at one centre with fewer than
50 children. It validates the existing kiosk, tutor roster, offline recovery,
paper fallback, and web reconciliation loop. Edmund observes and records fixes;
the centre lead owns operational go/no-go; each session has a named desk lead.

No roadmap expansion enters the pilot. Before real-child testing, delayed
offline writes must be unable to overwrite newer authorised corrections, and
the existing human/device readiness gates must pass.

After the pilot, evidence gates this sequence:

1. authoritative session calendar and expected-today roster;
2. admin-only Web Live Accountability Board and Exception Inbox;
3. observed and approved handoff evidence;
4. one Parent Assurance channel and trigger; and
5. only the longitudinal child context proven to change a safe action.

The full approved direction and boundaries are in
[`docs/superpowers/specs/2026-08-17-student-assurance-os-design.md`](docs/superpowers/specs/2026-08-17-student-assurance-os-design.md).

### Phase 2 — Parent Portal — BUILT, FLAG-GATED 2026-07-17
The `parent_portal` flag remains OFF until centre verification. Migrations 035–036
were applied to prod on 2026-07-17 before the final web deployment.

- **Attendance visibility**: parents see each linked child's attendance summary
- **Result slip uploads**: parents upload PDF/JPG/PNG slips; admins view and acknowledge them at **/result-slips**
- **Messaging**: per-child centre↔parent threads; admins reply at **/messages**
- **Account linking**: admins assign/unassign children from parent accounts at **/users**
- **Parent apps**: iOS, Android, and web parent areas remain gated by `parent_portal`

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
