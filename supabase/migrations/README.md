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
| 020 | test_mode_flag                | test_mode feature flag (seeded ON for demo day 2026-07-11) | yes   |
| 021 | notify_parent_trigger         | pg_net trigger → notify-parent edge fn on late/absent (inert until Vault key seeded) | yes   |
| 022 | advisor_followups_021         | revoke RPC exec on trigger fn; pg_net → extensions schema | yes   |
| 023 | student_results               | tutor-entered subject grades (AL1–AL8 / A1–F9), staff RLS | yes   |
| 024 | wipe_operational_data         | superadmin-only pre-launch data wipe RPC (keeps accounts/config/Study Space) | yes   |
| 025 | export_include_student_results | subject-access export now includes student_results (PDPA QA find 2026-07-12) | yes   |
| 026 | feature_flags_notes_qr_awards | session_notes / qr_sign_in / awards flag rows, all OFF | yes   |
| 027 | awards_unique                 | UNIQUE (student_id, award_type, period) on awards | yes   |
| 028 | policy_documents_public_read  | anon SELECT on current policy docs (public /privacy page for App Review) | yes   |
| 029 | user_delete_set_null          | provenance FKs to auth.users → ON DELETE SET NULL (admin user delete failed with 23503) | yes   |
| 030 | safely_home                   | mark_safely_home parent RPC (once-only) + dismissal-insert notify trigger (inert like 021) | yes   |
| 031 | app_events                    | Supabase-native analytics events, daily health view, 90-day purge, analytics flag | yes   |
| 032 | app_events_hardening          | Safe duration aggregation, cron refresh, stronger analytics assertions | yes   |
| 033 | app_events_singapore_day      | Group daily analytics by the Singapore centre calendar day | yes   |
| 034 | privacy_authorization_hardening | Atomic consent, append-only ledger, report/export and tutor authorization hardening | yes   |
| 035 | parent_portal_writes          | Parent INSERT policies for result_slips (+storage) and messages, thread indexes | yes   |
| 036 | parent_message_privacy        | Scope direct messages to the sending/receiving parent when siblings share a child | yes   |
| 037 | retrospective_sessions        | Flagged past-session create/edit, historical roster, and ended-attendance correction RPCs | yes   |
| 038 | security_boundary_hardening   | Tutor/substitute/session capabilities, safe parent projections, bounded analytics/push, DB-managed superadmin/role gates, service-only erasure, durable Storage cleanup, identifier-rotating pseudonymisation, and upload boundaries | yes   |
| 039 | feature_flag_superadmin_update_grant | Restore authenticated UPDATE table privilege while retaining the superadmin-only RLS boundary | yes   |
| 040 | record_tutor_policy_read_grants | Record RLS-bounded enrollment and tutor-assignment read privileges required by tutor policy evaluation | yes   |
| 041 | record_student_policy_read_grant | Record the RLS-bounded student read privilege required by tutor policy evaluation | yes   |
