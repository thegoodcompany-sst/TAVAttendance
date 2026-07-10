# Migrations

Forward migrations are applied in numeric order: `NNN_name.sql`.

## Down-migration convention (DEVOPS-01)

Starting with migration **012**, every new migration ships a paired reverse
script at `down/NNN_name.sql` that undoes exactly what the forward script did
(drop tables/functions it created, restore the prior body of any function it
replaced, re-add any constraint it removed).

- Forward: `supabase db push` (or apply in order).
- Reverse a single migration manually, newest-first:
  ```bash
  psql "$DATABASE_URL" -f supabase/migrations/down/014_feature_tables.sql
  psql "$DATABASE_URL" -f supabase/migrations/down/013_audit_fixes.sql
  psql "$DATABASE_URL" -f supabase/migrations/down/012_feature_flags.sql
  ```

Down scripts must be run in reverse numeric order and only as far back as needed.

Migrations **001–011** predate this convention and have **no** down scripts; do
not attempt to reverse them with this mechanism. Restore from a backup instead.

## Self-verifying migrations (DEVOPS-02)

Starting with migration **018** (the first example), every new forward migration ends with a
verification block that asserts the migration actually did what it claims —
so a partially-applied migration aborts (and rolls back, since each migration
runs in one transaction) instead of leaving prod in a half-state, and the
assertion name tells you exactly what's missing. Incidents behind this:
migration 007 sat unapplied for weeks, and 015 silently recreated a view
without `security_invoker`.

Template — adapt the asserts to what the migration creates:

```sql
-- Verification (DEVOPS-02): abort if this migration did not fully apply.
DO $$
BEGIN
  ASSERT (SELECT EXISTS (SELECT FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = 'classes'
            AND column_name = 'new_column')), 'classes.new_column missing';
  ASSERT (SELECT EXISTS (SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public' AND p.proname = 'new_function')), 'new_function missing';
  -- touched attendance_summary? security_invoker must survive (the 015 regression):
  ASSERT (SELECT coalesce('security_invoker=true' = ANY (c.reloptions), false)
          FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
          WHERE n.nspname = 'public' AND c.relname = 'attendance_summary'),
         'attendance_summary lost security_invoker';
END $$;
```

Existing migrations (001–017) are already applied to prod and are never edited
(see CLAUDE.md; the one sanctioned exception was the HUMANS.md §36 replayability
fixes to 005/010/014, which changed syntax, not end state); the convention
applies forward only.

## Current migrations

| #   | File                          | Purpose                                    | Down? |
|-----|-------------------------------|--------------------------------------------|-------|
| 001 | schema                        | initial schema                             | no    |
| 002 | rls                           | row-level security                         | no    |
| 003 | functions_triggers            | sync_attendance, session helpers           | no    |
| 004 | security_fixes                | profile RLS hardening                      | no    |
| 005 | sprint_features               | recurrence, sub-tutor, result slips        | no    |
| 006 | session_end                   | ended_at / sub_tutor_id                    | no    |
| 007 | security_invoker_view         | attendance_summary view                    | no    |
| 008 | attendance_session_guard      | block writes to ended sessions             | no    |
| 009 | security_hardening            | search_path pinning, grants                | no    |
| 010 | audit_fixes                   | marked_at clamp, RLS fixes                 | no    |
| 011 | pdpa_compliance               | retention, consent, result-slips bucket    | no    |
| 012 | feature_flags                 | feature_flags table + is_feature_enabled   | yes   |
| 013 | audit_fixes                   | SEC-05, UX-06, DOC-02, MAINT-11, SP-02     | yes   |
| 014 | feature_tables                | avatar_url, device_tokens, roster RPC      | yes   |
| 015 | study_space_and_notice        | is_study_space + singleton class, roster RPC, notice v1.1 | yes   |
| 016 | security_fixes                | SEC-16a–j: security_invoker restore, handle_new_user hardening | yes   |
| 017 | advisor_followups             | search_path pin + anon revokes (post-drift-campaign advisors) | yes   |
| 018 | restore_substitute_policies   | substitute-tutor RLS missing in prod (drift-detector find); first DEVOPS-02 migration | yes   |
| 019 | reconcile_prod_gaps           | audit triggers + perf indexes missing in prod (drift-detector find); formatting re-pins | yes   |
