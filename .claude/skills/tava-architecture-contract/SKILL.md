---
name: tava-architecture-contract
description: Use when designing or reviewing any TAVA feature, or when asking "why is it built this way" / "can I change this" — the load-bearing design decisions with rationale, the invariants that must hold (study-space exclusion, kiosk-as-admin, offline idempotency, status semantics), and the known weak points stated plainly.
---

# TAVA Architecture Contract

The decisions that hold the system up. Changing anything here without reading
its WHY breaks something a table below can predict.

**When NOT to use this skill:** you need commands (use `tava-run-and-operate`
or `tava-build-and-env`); you need the incident history behind a decision
(use `tava-failure-archaeology`); you've decided to change something and need
the gating rules (use `tava-change-control`).

## System shape

One Supabase project (Postgres + PostgREST + Auth + Storage) is the entire
backend. Three clients: iPad kiosk + teacher app (SwiftUI, `iOS/`), Android
mirror (Compose, `Android/`), admin dashboard (Next.js, `web/`). There is no
custom API server — every client talks PostgREST/RPC directly, so **Row-Level
Security (RLS) IS the authorization layer**. Roles: `admin`, `tutor`,
`parent` (DB-checked on `profiles.role`).

Data-access seam per client: Supabase access stays in iOS services and
`AttendanceService` domain extensions, Android `data/service` data sources,
and web `lib/queries/*` plus server actions. Split by domain when useful; never
scatter queries into views, composables, or client components.

## Invariants (MUST hold; violating any is a bug even if nothing crashes)

1. **Study-space attendance never appears in any report, report card, or parent view.** The drop-in study room is modelled as one flagged class (`classes.is_study_space = TRUE`, fixed UUID `57000000-0000-0000-0000-000000000001`) to reuse the attendance stack. Exclusion is enforced at every source: `attendance_summary` view, `get_roster_for_date`, `fetchMyClasses`, iOS `fetchStudentAttendanceHistory`, web `getTodaySessions`/`getDailyAttendance`/`getStudentRecentRecords`. **Every NEW reporting/parent query must add `classes.is_study_space = FALSE`.**
2. **The kiosk iPad is signed in as an admin account.** `fetchKioskEntries` → `fetchMyClasses` → RLS filters tutors to their own classes, which would break the global kiosk. Operational rule, not code.
3. **`attendance_summary` carries `WITH (security_invoker = true)`** — without it the view runs as owner and bypasses RLS. Re-state it on every `CREATE OR REPLACE`. (Restored on prod 2026-07-09 via migration 016.)
4. **Offline sync is actor-bound, server-timed and idempotent.** Migration 038
   ignores client `marked_at`, stamps `auth.uid()`/`clock_timestamp()`, serialises
   mutation IDs, and retains receipts when a newer mutation replaces an older
   one. Replays by the same actor are skipped; identifier collisions fail.
   Ended sessions and open sessions more than seven days old reject offline
   writes. Native queues are also bound to the signed-in account.
5. **Feature flags gate all unshipped features and ship OFF.** One `feature_flags` table read by all three platforms; flips are admin-only (RLS) and human-verified.
6. **Migrations are append-only** (new numbered file + reverse script in
   `migrations/down/` from 012 on). Production's historical ledger is sparse,
   so current state is proved by live drift/security checks, not filenames.

## Load-bearing decisions and their WHY

| Decision | Why | If you're tempted to change it |
|---|---|---|
| No backend server; RLS is authz | One less deploy target for a 3-person tuition centre; Supabase RLS is sufficient at this scale | Any bypass (SECURITY DEFINER fn, service-role call) must self-guard with `is_admin()` — see the existing PDPA RPCs. |
| `schedule_time` is Postgres `TIME` (not TEXT) | Type safety; PostgREST returns `"HH:mm:ss"` strings | Parsers split on `:` and use [0],[1] so both `HH:mm` and `HH:mm:ss` work. Don't assume two components. |
| Kiosk pre-creates today's sessions on load (`getOrCreateSession`) | Roster is ready before class starts | Day-filtered since migration 015 (`classMeetsToday`: BYDAY match, or `schedule_day` match, or neither = ad-hoc). Session counts include attendance-less sessions — intentional. |
| Student history uses PostgREST FK-inference (`session:sessions(session_date, class:classes(name))`) | No join code | Renaming either FK breaks the select string in `fetchStudentAttendanceHistory` — update it in the same change. |
| Multi-class students show the "worst" stored status on the kiosk | One card per student | Merge order is `late > present > absent`; `nil` means every session has no attendance row. |
| Dismissals live in a separate `dismissals` table, not a status | Dismissed students were PRESENT (counts toward attendance %); dismissal is a safety event, not an attendance state | Purple card; original status shown underneath; undo via admin long-press. |
| "Not Here Yet" = no attendance row vs "Absent" = stored hard mark | Front-desk reality: kids tap the wrong card | Clear through `clear_attendance`; never emulate clearing with another stored status. |
| Kiosk admin mode: no PIN = always admin; PIN = lock/unlock, `isAdminUnlocked` is `@State` (not persisted across restarts) | Demo-friendly default; restart = safe state | PIN hash currently in UserDefaults — known weak point below. |
| Users are managed by web `/users` or, as a fallback, Dashboard invite | `handle_new_user` creates a least-privilege profile; web trusted actions assign approved roles | Only the DB-managed superadmin may manage admin accounts; never trust invite metadata for privileged roles. |
| Parent clients use shaped RPCs | Migration 038 removed broad direct-table parent reads and exposes safe columns only | Extend the safe projection/RPC and its role tests; never restore broad table access for convenience. |

## Known weak points (open, stated plainly)

- **Full-admin kiosk session.** PIN/biometric UI contains students but the
  device still holds a reusable admin session; least-privilege kiosk identity
  remains HUMANS.md §63.
- **iOS kiosk PIN verifier remains in UserDefaults.** Android auth sessions and
  PKCE verifiers are now Keystore/AES-GCM protected, but native offline queues
  remain unencrypted application preferences (HUMANS.md §64).
- **Privileged sessions are password-only.** MFA/AAL2 is open (§62).
- **Production verification and activation are human gates.** Migration/Edge
  code in Git is not proof that production schema, Auth settings, headers,
  Vault secrets or cleanup workers are current (§§60–68).
- **Some feature-flagged workflows remain dark pending physical QA.** Query the
  environment; do not infer flag state from seed migrations.

## Provenance and maintenance

Audited 2026-08-11 after aligning the documented data-access seam with the
domain-split services currently present on all three clients.
- Invariant 1 enforcement points: `rg -n 'is_study_space' web/lib iOS Android supabase/migrations/038*`
- Worst-status merge: `rg -n 'worstStatus' iOS/TAVAttendance/Services/AttendanceService+Kiosk.swift`
- View option: `SELECT reloptions FROM pg_class WHERE relname='attendance_summary';`
