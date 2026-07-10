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

Single-service pattern per client: all Supabase access goes through ONE
service (`iOS/TAVAttendance/Services/AttendanceService.swift`,
`Android/.../data/service/AttendanceService.kt`, `web/lib/queries.ts` +
server actions). Don't scatter queries into views/components.

## Invariants (MUST hold; violating any is a bug even if nothing crashes)

1. **Study-space attendance never appears in any report, report card, or parent view.** The drop-in study room is modelled as one flagged class (`classes.is_study_space = TRUE`, fixed UUID `57000000-0000-0000-0000-000000000001`) to reuse the attendance stack. Exclusion is enforced at every source: `attendance_summary` view, `get_roster_for_date`, `fetchMyClasses`, iOS `fetchStudentAttendanceHistory`, web `getTodaySessions`/`getDailyAttendance`/`getStudentRecentRecords`. **Every NEW reporting/parent query must add `classes.is_study_space = FALSE`.**
2. **The kiosk iPad is signed in as an admin account.** `fetchKioskEntries` → `fetchMyClasses` → RLS filters tutors to their own classes, which would break the global kiosk. Operational rule, not code.
3. **`attendance_summary` carries `WITH (security_invoker = true)`** — without it the view runs as owner and bypasses RLS. Re-state it on every `CREATE OR REPLACE`. (Restored on prod 2026-07-09 via migration 016.)
4. **Offline sync is idempotent and last-write-wins by `marked_at`.** `sync_attendance` uses `ON CONFLICT ... WHERE marked_at <= EXCLUDED.marked_at` plus `ON CONFLICT (client_mutation_id) DO NOTHING`; ended sessions reject writes (returned as `blocked_ended_session`). Consequence: device clock accuracy matters; a badly wrong clock silently loses.
5. **Feature flags gate all unshipped features and ship OFF.** One `feature_flags` table read by all three platforms; flips are admin-only (RLS) and human-verified.
6. **Migrations are append-only** (new numbered file + `.down.sql` from 012 on). Never edited, because prod is partially applied out-of-band.

## Load-bearing decisions and their WHY

| Decision | Why | If you're tempted to change it |
|---|---|---|
| No backend server; RLS is authz | One less deploy target for a 3-person tuition centre; Supabase RLS is sufficient at this scale | Any bypass (SECURITY DEFINER fn, service-role call) must self-guard with `is_admin()` — see the existing PDPA RPCs. |
| `schedule_time` is Postgres `TIME` (not TEXT) | Type safety; PostgREST returns `"HH:mm:ss"` strings | Parsers split on `:` and use [0],[1] so both `HH:mm` and `HH:mm:ss` work. Don't assume two components. |
| Kiosk pre-creates today's sessions on load (`getOrCreateSession`) | Roster is ready before class starts | Day-filtered since migration 015 (`classMeetsToday`: BYDAY match, or `schedule_day` match, or neither = ad-hoc). Session counts include attendance-less sessions — intentional. |
| Student history uses PostgREST FK-inference (`session:sessions(session_date, class:classes(name))`) | No join code | Renaming either FK breaks the select string in `fetchStudentAttendanceHistory` — update it in the same change. |
| Multi-class students show the "worst" status on the kiosk | One card per student | Merge order is `late > present > absent > excused`, in `AttendanceService.worstStatus(_:_:)`. |
| Dismissals live in a separate `dismissals` table, not a status | Dismissed students were PRESENT (counts toward attendance %); dismissal is a safety event, not an attendance state | Purple card; original status shown underneath; undo via admin long-press. |
| "Not Here" = `excused` (soft, student can re-sign-in) vs "Absent" (hard, admin-only) | Front-desk reality: kids tap the wrong card | Don't merge these states. |
| Kiosk admin mode: no PIN = always admin; PIN = lock/unlock, `isAdminUnlocked` is `@State` (not persisted across restarts) | Demo-friendly default; restart = safe state | PIN hash currently in UserDefaults — known weak point below. |
| Users created via Supabase Dashboard invite (`handle_new_user` trigger builds `profiles`) or web invite action | No user-management UI yet | Role comes from invite metadata but (post-016) the trigger never trusts metadata to mint privileged roles; the web action assigns role via service role after creation. |
| Parent portal needs no new RLS | Parent read policies for `students`/`attendance_records` shipped in `002_rls.sql` from day one | Just flip the flag when UI is ready (all platforms). |

## Known weak points (open, stated plainly)

- ~~Prod schema drift~~ — RESOLVED 2026-07-09 (prod = migrations 001–017). The prevention protocol and verification snapshot live in `tava-prod-drift-campaign`.
- **Kiosk PIN hash in UserDefaults** (Keychain move deferred; `ponytail:` marker in `GlobalKioskView.swift`). Restored/migrated iPads risk lock-out.
- **Android error handling**: many `runCatching` results uninspected — failures can be silent.
- **No automated test suite** (one Android unit test exists, blocked locally by JDK; everything else is manual checklists — see `tava-validation-and-qa`).
- **Phase 2/3 tables exist but are unimplemented** (`result_slips`, `messages`, `awards`, `dismissals`*, `food_polls`, `food_poll_responses`) — RLS admin-only until built. (*dismissals is partially live via the kiosk.)
- **Web `PdpaPanel` built but never wired** into the student page (decision pending, HUMANS.md §29).
- **Device clock dependency** in offline sync (invariant 4).

## Provenance and maintenance

Current as of 2026-07-09.
- Invariant 1 enforcement points: `grep -rn 'is_study_space' web/lib iOS supabase/migrations/015* supabase/migrations/016* | grep -c FALSE` (expect multiple hits)
- Worst-status merge: `grep -n 'worstStatus' iOS/TAVAttendance/Services/AttendanceService.swift`
- View option: `SELECT reloptions FROM pg_class WHERE relname='attendance_summary';`
