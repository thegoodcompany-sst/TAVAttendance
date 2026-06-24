# Migrations

Forward migrations are applied in numeric order: `NNN_name.sql`.

## Down-migration convention (DEVOPS-01)

Starting with migration **012**, every new migration ships a paired reverse
script named `NNN_name.down.sql` that undoes exactly what the forward script did
(drop tables/functions it created, restore the prior body of any function it
replaced, re-add any constraint it removed).

- Forward: `supabase db push` (or apply in order).
- Reverse a single migration manually, newest-first:
  ```bash
  psql "$DATABASE_URL" -f supabase/migrations/014_feature_tables.down.sql
  psql "$DATABASE_URL" -f supabase/migrations/013_audit_fixes.down.sql
  psql "$DATABASE_URL" -f supabase/migrations/012_feature_flags.down.sql
  ```

Down scripts must be run in reverse numeric order and only as far back as needed.

Migrations **001–011** predate this convention and have **no** down scripts; do
not attempt to reverse them with this mechanism. Restore from a backup instead.

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
