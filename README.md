# TAVA Attendance — Every child accounted for

Student-operations system for TAVA's nonprofit tuition centre. Its core promise
is **every child accounted for**. An iPad-native kiosk (SwiftUI), Android app
(Jetpack Compose), web admin dashboard (Next.js), and a Linux arrival station
(`station/`) share one Supabase backend. The station is dark behind
`nfc_sign_in` and is not in production.

TAVA is not a payments, accounting, payroll, CRM, or business-ERP product. It
focuses on the student journey and the evidence staff need to act safely.

See **[CONTRIBUTING.md](CONTRIBUTING.md)** for full local setup of every platform.
Agents: project rules live in [AGENTS.md](AGENTS.md) (`CLAUDE.md` stubs to it);
product direction in [ROADMAP.md](ROADMAP.md); the next implementation queue in
[NEXT_BUILD_CHANGES.md](NEXT_BUILD_CHANGES.md); deploy and release runbooks in
`.claude/skills/`.

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
| Offline marking with automatic sync on reconnect (tutor roster only; kiosk is online-only) | Teachers |

## Stack

- **iOS**: SwiftUI, targeting iPad (iPadOS 17+) — `iOS/`
- **Android**: Kotlin + Jetpack Compose — `Android/`
- **Web**: Next.js admin dashboard — `web/`
- **Arrival station**: Linux daemon, USB PC/SC NFC — `station/`
- **Backend**: Supabase (Postgres + PostgREST + Auth + Storage) — `supabase/`
- **Offline (iOS/Android)**: tutor roster pending store → `sync_attendance` RPC on reconnect. The centre kiosk is online-only.

### Platforms

| Platform | Directory | Run |
|---|---|---|
| iOS (kiosk + teacher) | `iOS/` | `open iOS/TAVAttendance.xcodeproj` |
| Android | `Android/` | `cd Android && ./gradlew installDebug` |
| Web (admin dashboard) | `web/` | `cd web && bun install && bun run dev` |
| Arrival station | `station/` | See `station/README.md`. Not production. |

Each platform reads Supabase credentials from a gitignored config file — see
[CONTRIBUTING.md](CONTRIBUTING.md). Feature flags in the `feature_flags` table gate
in-progress features (parent portal, push notifications, student photos, study space
tracking, test mode, session notes, QR sign-in, awards, analytics, retrospective
sessions, and NFC sign-in); they ship OFF unless a migration explicitly documents otherwise.

Built and gated (not future work — see [ROADMAP.md](ROADMAP.md) for that): parent
portal, awards, student photos, session notes, QR sign-in, push notifications
(credentials still human), food polls. Kiosk dismissal and web analytics are
live. Do not grow QR further; 2027 arrival is NFC.

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
station/          Linux arrival station (Pi-class box, USB NFC). Dark. Not production.
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

Roles: `admin`, `tutor`, `parent`, and `arrival_station` after migration 059.
A trigger (`handle_new_user`) auto-creates the `profiles` row as `parent`.
The station role is not an invite option. Provision it per `HUMANS.md` §78.
Admins link parent accounts to children from **/users**; the UI calls the existing
`link_parent_student` / `unlink_parent_student` RPCs.

---

## Roadmap

Future work: **[ROADMAP.md](ROADMAP.md)**. Next implementation queue:
[NEXT_BUILD_CHANGES.md](NEXT_BUILD_CHANGES.md). What changed between builds:
[RELEASE_NOTES.md](RELEASE_NOTES.md).
