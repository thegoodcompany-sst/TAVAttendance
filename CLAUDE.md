# TAVA Attendance Platform

Nonprofit tuition centre attendance and student management system.
**iOS app** (Swift/SwiftUI) + **Supabase backend** (Postgres, Auth, RLS, Realtime).

## Repo Structure

```
TAVAttendance/
├── iOS/                         SwiftUI iOS app
│   ├── TAVAttendance.xcodeproj
│   └── TAVAttendance/
│       ├── Core/                SupabaseManager, AuthManager, NetworkMonitor, PendingAttendanceStore
│       ├── Models/              All Codable structs (Profile, TAVClass, Student, TAVSession, etc.)
│       ├── Services/            AttendanceService — all Supabase calls (views never call client directly)
│       └── Views/               LoginView, ClassListView, SessionListView, RosterView
├── Backend/
│   ├── supabase/
│   │   ├── config.toml          Local dev config
│   │   ├── seed.sql             Dev seed data (3 users: admin/tutor/parent)
│   │   └── migrations/
│   │       ├── 001_schema.sql   All tables
│   │       ├── 002_rls.sql      Row Level Security policies
│   │       └── 003_functions_triggers.sql  Audit log, RPCs, offline sync
│   ├── API.md                   iOS integration guide with Swift SDK examples
│   └── README.md                Backend setup and deployment instructions
└── supabase/                    Supabase CLI root (config only — migrations live in Backend/supabase/)
```

## Backend

**Stack:** Supabase (Postgres + Auth + RLS + Realtime + Storage)
**Region:** ap-southeast-1 (Singapore — PDPA data residency)

### Local dev

```bash
# Prerequisites: Docker (Colima works: `colima start --cpu 2 --memory 4`)
cd Backend
supabase start        # first run pulls ~3GB of images; subsequent starts are instant
supabase db reset     # applies all migrations + seed data
```

Seed accounts (local only, password `TAVAdev123!`):

| Role   | Email           |
|--------|-----------------|
| Admin  | admin@tava.dev  |
| Tutor  | tutor@tava.dev  |
| Parent | parent@tava.dev |

After `supabase start`, copy the **anon key** from the output into `iOS/TAVAttendance/Core/SupabaseManager.swift`.

### Deploy to production

```bash
cd Backend
supabase link --project-ref YOUR_PROJECT_REF
supabase db push
```

## iOS

See `iOS/README.md` for full setup. Short version:

1. Open `iOS/TAVAttendance.xcodeproj`
2. **File → Add Package Dependencies** → `https://github.com/supabase/supabase-swift` → add `Supabase` product to target
3. Right-click the **TAVAttendance** group → **Add Files** → select `Core/`, `Models/`, `Services/`, `Views/` (Create groups, not folder references)
4. Fill in Supabase URL + anon key in `Core/SupabaseManager.swift`
5. Build with ⌘B

## Roles & Access

| Role   | Can see                                      | Can write                          |
|--------|----------------------------------------------|------------------------------------|
| admin  | Everything                                   | Everything                         |
| tutor  | Their assigned classes and enrolled students | Attendance for their own sessions  |
| parent | Their own children's records only            | Read-only                          |

## Phase Roadmap

| Phase | Status       | Features                                                  |
|-------|--------------|-----------------------------------------------------------|
| 1     | **Complete** | Auth, classes, sessions, attendance (P/A/L/E), offline sync, audit log |
| 2     | Schema only  | Result slips (upload/view), direct messaging, auto awards |
| 3     | Schema only  | Dismissal tracking, "Safely Home" confirmation, food polls |

Phase 2/3 database tables exist but have admin-only access. To unlock: add RLS policies + service methods in a new migration file.

## Key Conventions

- **Views never call Supabase directly** — all API calls go through `AttendanceService` (or a new `XxxService`)
- **Offline sync** — mark attendance locally via `PendingAttendanceStore`, `syncPending()` fires automatically on reconnect
- **Audit log** — every write to `students`, `attendance_records`, `sessions`, `enrollments` is logged automatically via DB trigger; no app code needed
- **New migrations** — add files to `Backend/supabase/migrations/` with the next sequence number; never edit existing migrations
- **Secrets** — anon key is safe to ship in the app; never commit or ship the service role key
