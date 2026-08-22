# Supabase change guide

The root `AGENTS.md` applies here. When production is involved, read
`.claude/skills/tava-prod-drift-campaign/SKILL.md` first.

## Migration discipline

- Never edit an existing forward migration.
- Add the next numbered `migrations/NNN_name.sql` and matching
  `migrations/down/NNN_name.sql`. Reverse scripts must stay in `down/`, where
  the Supabase CLI will not replay them as forward migrations.
- Add a row to `migrations/README.md` and a concise `RELEASE_NOTES.md` entry.
- Preserve RLS, grants, role checks, Study Space exclusion, and
  `security_invoker` behavior when replacing an object.
- Inspect later replacements of the same function/view before changing it; the
  latest applied body wins when historical migrations were out of order.

## Verification

From the repository root, replay the complete current migration set:

```bash
supabase db start
supabase db reset --local
supabase db lint --local --schema public --level error --fail-on error
for test_file in supabase/tests/*.sql; do
  psql "$TAVA_LOCAL_DB_URL" -v ON_ERROR_STOP=1 -f "$test_file"
done
```

Never run `supabase db reset` or `supabase db push` against production. Apply
only exact reviewed migration SQL using the production runbook, then query the
live objects and run the drift/security gates. Do not expose real student or
parent rows while collecting evidence.
