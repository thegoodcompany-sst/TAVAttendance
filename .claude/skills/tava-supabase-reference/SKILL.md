---
name: tava-supabase-reference
description: Use when writing or reviewing any Supabase/Postgres code for TAVA — RLS policies, PostgREST queries and embedded selects, SECURITY DEFINER functions, views with security_invoker, upserts/ON CONFLICT, storage buckets and signed URLs, pg_cron — the domain theory as it applies to THIS schema, for someone who hasn't run Supabase in production before.
---

# TAVA Supabase Reference

The Supabase/Postgres concepts a mid-level engineer needs, taught on this
project's actual schema. Not a Supabase tutorial — the parts that are
load-bearing HERE.

**When NOT to use this skill:** PDPA data-handling rules (use
`tava-pdpa-reference`); applying anything to prod (use
`tava-prod-drift-campaign` + `tava-change-control`).

## The mental model

Clients hold only the **anon key** (public by design — printable in every app
binary). Every request carries the user's JWT; **PostgREST executes SQL as
that user**, and Row-Level Security policies decide row visibility. There is
no API server to enforce anything — if RLS is wrong, the data is exposed.
That's why the worst incidents here were RLS-class bugs.

Key schema (migration 001 + successors): `profiles` (role: admin/tutor/parent),
`students`, `classes`, `enrollments`, `sessions` (one per class per date),
`attendance_records` (status: `present|late|absent|excused`), `dismissals`,
`parent_student_links`, `feature_flags`, PDPA tables (see sibling skill),
Phase-2/3 stubs (`result_slips`, `messages`, `awards`, `food_polls`, ...).

## RLS here

- Helper predicates (`is_admin()`, `is_parent()`, `tutor_owns_class(uuid)`) are SECURITY DEFINER functions callable by `authenticated` **by design** — advisors WARN about this; it's accepted (policies need them). Documented in HUMANS.md Notes.
- Tutors see only their classes (`tutor_owns_class`); parents see only linked children (`parent_student_links`); admins see everything. This is why the kiosk iPad must be admin.
- `rate_limit_events` has RLS enabled with NO policies — service-role-only by design. Don't "fix" it.
- Adding a policy? Test as each role in local Studio (`supabase start`, impersonate via the SQL editor's role switcher) before shipping.

## Views and `security_invoker`

Postgres views default to running as their **owner**, bypassing RLS. Supabase
grants read to `authenticated`/`anon` broadly, so an owner-privileged view =
public data. Fix: `WITH (security_invoker = true)`. **Trap: `CREATE OR
REPLACE VIEW` resets options** — every touch of `attendance_summary` must
re-state it (this leaked all attendance twice; see archaeology skill).

```sql
SELECT reloptions FROM pg_class WHERE relname='attendance_summary';
-- must show {security_invoker=on}
```

## SECURITY DEFINER functions

Used where a user must do something their RLS can't (e.g. PDPA
`export_student_personal_data`, `anonymise_student`, `erase_student`). House
rules, all enforced in migration 009/016:

1. First line of the body guards: `IF NOT is_admin() THEN RAISE EXCEPTION ... END IF;`
2. Pin the search path: `SET search_path = public, pg_temp` in the function definition (prevents object-shadowing attacks).
3. `REVOKE EXECUTE ... FROM anon, PUBLIC;` then grant to `authenticated` only if needed.

## PostgREST specifics that bite

- **Embedded selects** ride FK inference: `session:sessions(session_date, class:classes(name))` works because `attendance_records.session_id → sessions.id → classes.id`. Rename an FK and the string 400s (blank UI, error swallowed).
- **TIME columns** return as `"HH:mm:ss"` strings, not `"HH:mm"`. Inserts coerce free text like `"20:00"` fine.
- **Schema cache**: after creating/replacing any function or table via SQL, run `NOTIFY pgrst, 'reload schema';` or PostgREST 404s the new RPC.
- **Upserts need a real UNIQUE constraint** matching `onConflict:` columns, or Postgres throws 42P10 (the "Failed to mark dismissal" incident).

## The offline-sync RPC (worked example)

`sync_attendance(records jsonb)` — the project's most instructive function:

```text
ON CONFLICT (session_id, student_id)
  DO UPDATE ... WHERE attendance_records.marked_at <= EXCLUDED.marked_at
```
= last-write-wins by client timestamp (older offline records never clobber
newer server rows). A second `ON CONFLICT (client_mutation_id) DO NOTHING`
absorbs exact retries. Returns `{synced, skipped, blocked_ended_session}` —
`skipped` = lost the timestamp race; `blocked_ended_session` = session had
`ended_at` set (writes to ended sessions are trigger-blocked, migration
008/016). Design lesson: idempotency + explicit rejection counts beat silent
success.

## Storage

Two **private** buckets (clients use short-lived signed URLs, never public
URLs): `result-slips` (migration 011; admin write, parent reads own child)
and `student-photos` (migration 014; admin write, authed read; **not yet
applied to prod** as of 2026-07-09). Upload size caps are **client-side**
checks, not bucket settings (result slips 10 MB, photos 5 MB — per
CONTRIBUTING.md §1; the photo check lives in iOS `AttendanceService.swift`).
Path convention:
`<student_id>/<file>`. Explicit app-driven erase/anonymise sweeps both buckets
before the database RPC. SQL-only scheduled retention still cannot delete
Storage objects; HUMANS.md §9 tracks the orphan-cleanup gap.

## Scheduled jobs

`pg_cron` runs `pdpa-daily-purge` at 18:20 daily → `purge_expired_personal_data()`
(migration 011). Check: `SELECT * FROM cron.job WHERE jobname='pdpa-daily-purge';`
Safe to run the function manually — it returns counts.

## Auth

- Accounts are invite-only. Prod must keep public signup OFF (dashboard toggle, HUMANS.md §31); local `supabase/config.toml` already sets `enable_signup = false` for the relevant provider.
- `handle_new_user` trigger creates the `profiles` row on signup/invite. Post-016 it never trusts `raw_user_meta_data.role` for privileged roles.
- Local vs prod auth settings can drift — config.toml governs LOCAL ONLY; prod is dashboard-controlled.

## Provenance and maintenance

Current as of 2026-07-09 (16 migrations; supabase-js 2.x, supabase-swift 2.x).
- Function inventory: `grep -n 'CREATE OR REPLACE FUNCTION\|CREATE FUNCTION' supabase/migrations/*.sql | grep -v down`
- Bucket definitions: `grep -n 'result-slips\|student-photos' supabase/migrations/011* supabase/migrations/014*`
- RPC return shape: `grep -n 'blocked_ended_session' supabase/migrations/013_audit_fixes.sql`
