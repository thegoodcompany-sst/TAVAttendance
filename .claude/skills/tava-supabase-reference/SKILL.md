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

Key schema (migration 001 + successors through 053): `profiles` (role: admin/tutor/parent),
`students`, `classes`, `enrollments`, `sessions` (one per class per date),
`attendance_records` (status: `present|late|absent|excused`), `dismissals`,
`parent_student_links`, `feature_flags`, PDPA tables (see sibling skill),
feature workflows (`result_slips`, `messages`, `awards`, retrospective
sessions), security receipts/principals and durable Storage cleanup state.

## RLS here

- Helper predicates (`is_admin()`, `is_parent()`, `tutor_owns_class(uuid)`) are SECURITY DEFINER functions callable by `authenticated` **by design** — advisors WARN about this; it's accepted (policies need them). Documented in HUMANS.md Notes.
- Tutors/substitutes receive bounded class/session capabilities. Parents use
  migration-038 safe-column RPC projections for linked children rather than
  broad base-table reads. Admins are broad but destructive/superadmin actions
  are separately restricted.
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

Used where a user must do something their RLS cannot, including shaped
projections and trusted workflows. House rules, enforced and regression-tested
in migration 038:

1. Guard the caller/feature/capability inside the function; SECURITY DEFINER is
   never authorisation by itself.
2. Pin the search path: `SET search_path = public, pg_temp` in the function definition (prevents object-shadowing attacks).
3. `REVOKE EXECUTE ... FROM anon, PUBLIC;` then grant to `authenticated` only if needed.

## PostgREST specifics that bite

- **Embedded selects** ride FK inference: `session:sessions(session_date, class:classes(name))` works because `attendance_records.session_id → sessions.id → classes.id`. Rename an FK and the string 400s (blank UI, error swallowed).
- **TIME columns** return as `"HH:mm:ss"` strings, not `"HH:mm"`. Inserts coerce free text like `"20:00"` fine.
- **Schema cache**: after creating/replacing any function or table via SQL, run `NOTIFY pgrst, 'reload schema';` or PostgREST 404s the new RPC.
- **Upserts need a real UNIQUE constraint** matching `onConflict:` columns, or Postgres throws 42P10 (the "Failed to mark dismissal" incident).

## The offline-sync RPC (worked example)

`sync_attendance(records jsonb)` accepts at most 500 items. Migration 038
server-stamps actor/time, serialises each mutation ID with an advisory lock,
recognises same-actor replays from live rows or durable receipts, and rejects
collisions. It permits only bounded recent open-session offline replay; ended
sessions increment `blocked_ended_session`. Client timestamps are not write
authority.

## Storage

Two **private** buckets use server-minted signed upload/download flows.
Migration 038 enforces canonical student paths, rate/size/MIME bounds, content
signatures and atomic finalisation. Direct public URLs and client-only upload
validation are not sufficient. Erasure/anonymisation enqueue durable Storage
cleanup; a dedicated Edge worker drains it once the production function,
Vault invocation secret and cron are active (HUMANS.md §65).

## Scheduled jobs

`pg_cron` runs `pdpa-daily-purge` at 18:20 daily → `purge_expired_personal_data()`
(migration 011). Check: `SELECT * FROM cron.job WHERE jobname='pdpa-daily-purge';`
Safe to run the function manually — it returns counts.

## Auth

- Accounts are invite-only. Prod must keep public signup OFF (dashboard toggle, HUMANS.md §31); local `supabase/config.toml` already sets `enable_signup = false` for the relevant provider.
- `handle_new_user` creates a least-privilege profile and never trusts
  `raw_user_meta_data.role` for privileged roles. Trusted web actions assign
  approved roles; only the DB superadmin manages admins.
- Local vs prod auth settings can drift — config.toml governs LOCAL ONLY; prod is dashboard-controlled.

## Provenance and maintenance

Audited 2026-07-26 (migrations 001–053; dependency lockfiles are the version
sources).
- Function inventory: `rg -n 'CREATE( OR REPLACE)? FUNCTION' supabase/migrations/*.sql`
- Current security boundary: migration 038 + `scripts/prod-security-check.sql`
- RPC return shape: `rg -n 'blocked_ended_session' supabase/migrations/038*`
