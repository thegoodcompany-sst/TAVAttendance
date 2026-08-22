---
name: tava-prod-drift-campaign
description: Use before any production schema work, when a migration fails in production but works locally, or when investigating suspected schema drift. Carries the current verification protocol and the historical reconciliation lessons without treating an old snapshot as live truth.
---

# TAVA production drift control

The 2026-07-09 reconciliation repaired the historical 001–017 drift. That is
history, not proof of current state. Determine the repository migration set
from `supabase/migrations/`; never write “prod matches migrations” unless the
current commit's remote drift and security gates have just passed.

## Prevention protocol

1. Query the live environment; do not infer it from files or the sparse
   `supabase_migrations.schema_migrations` ledger.
2. Replay all migrations locally before a production apply:

   ```bash
   supabase db start
   supabase db reset --local
   supabase db lint --local --schema public --level error --fail-on error
   for test_file in supabase/tests/*.sql; do
     psql "$TAVA_LOCAL_DB_URL" -v ON_ERROR_STOP=1 -f "$test_file"
   done
   ```

3. Apply reviewed SQL from its exact committed migration file. Do not edit old
   migrations or run an unrecorded dashboard snippet.
4. Apply schema before deploying clients that reference it.
5. After function changes, run `NOTIFY pgrst, 'reload schema';`.
6. Run the read-only production gates:

   ```bash
   scripts/drift-check.sh
   psql "$TAVA_DB_URL" -v ON_ERROR_STOP=1 -f scripts/prod-security-check.sql
   ```

7. Require the `Remote security checks` workflow on protected `main`. It
   compares live production with a clean local replay and fails on structural
   drift after the explicit security assertions pass.
8. Review Supabase security and performance advisors. New findings need a
   numbered migration or a reviewed update to the accepted baseline.

`supabase db reset` against production is destructive and forbidden.
`supabase db push` against this production project is also forbidden: the
historical ledger is sparse and can attempt to replay partially present work.

## Diagnosing a failed apply

Before changing SQL, inspect prerequisites in the live database:

```sql
SELECT column_name
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = '<table>';

SELECT proname, pg_get_function_identity_arguments(oid)
FROM pg_proc
WHERE pronamespace = 'public'::regnamespace
  AND proname = '<function>';

SELECT policyname, cmd, roles, qual, with_check
FROM pg_policies
WHERE schemaname = 'public' AND tablename = '<table>';

SELECT reloptions
FROM pg_class
WHERE oid = 'public.attendance_summary'::regclass;
```

If `CREATE OR REPLACE FUNCTION` changes a return type, it must be dropped and
recreated in the same reviewed transaction. If migrations were applied out of
numeric order, compare every later replacement of the same object; the last
applied function/view body wins.

## Security invariants

Do not maintain a hand-copied object snapshot here. The executable source is
`scripts/prod-security-check.sql`, which currently checks the migration-038
authorization boundary and later grant-recording migrations, including:

- `attendance_summary` security-invoker behaviour;
- actor/server-time enforcement and bounded offline replay;
- staff, substitute, parent, superadmin and feature-flag boundaries;
- private Storage paths, signed-upload/finalisation flows and cleanup queue;
- role/grant restrictions on sensitive tables and RPCs.

When a security invariant changes, update that script and its local SQL
regressions in the same commit.

## Historical reconciliation record

On 2026-07-09, production was brought through 017 after discovering that 004,
005 and multiple RPC fragments were absent despite the repository state.
Prerequisite queries caught missing columns/functions before dependent
migrations ran. Return-type changes required drop/recreate, and later
migrations had to be re-applied after older function bodies were backfilled.
The detailed human record remains in `HUMANS.md` §§14 and 30.
