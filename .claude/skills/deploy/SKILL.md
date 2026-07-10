---
name: deploy
description: Use when deploying the TAVA web dashboard to production at dash.thegoodcompanysg.dev — covers Vercel env var checks, production deploy, and post-deploy verification including the Supabase redirect URL requirement.
---

# TAVA Web Deploy

## Overview

Deploys `web/` to the `tava-dashboard` Vercel project, aliased to `https://dash.thegoodcompanysg.dev`. Always run from the `web/` directory — the `.vercel/project.json` there links to the correct project.

## Required Production Env Vars

Before deploying, confirm all four are set in Vercel Production (`vercel env ls production`):

| Variable | Purpose |
|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | Supabase project URL |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Public anon key |
| `SUPABASE_SERVICE_ROLE_KEY` | Admin client for invite/remove actions |
| `SITE_URL` | `https://dash.thegoodcompanysg.dev` — controls `redirectTo` in invite emails |

Add a missing var with:
```bash
printf 'value' | vercel env add VAR_NAME production
```

## Pre-Deploy Gate — Schema Check (mandatory)

Web code referencing a column prod lacks took the dashboard down on 2026-06-27.
Before every deploy, verify every table/column/RPC referenced in `web/` exists in prod:

1. Run this via the Supabase MCP `execute_sql` tool and save the JSON result to a temp file:
   ```sql
   select json_build_object(
     'tables',   (select json_agg(distinct table_name)   from information_schema.tables   where table_schema='public'),
     'columns',  (select json_agg(distinct column_name)  from information_schema.columns  where table_schema='public'),
     'routines', (select json_agg(distinct routine_name) from information_schema.routines where routine_schema='public'));
   ```
2. `node scripts/check-web-schema.mjs <temp-file>` — must print "Schema check passed".

If it fails: the missing migration must be applied to prod FIRST (see `tava-change-control` ordering rule). Do not deploy.

(With `TAVA_DB_URL` + psql available, `scripts/drift-check.sh` does both steps.)

## Deploy

```bash
cd web
vercel deploy --prod --yes
```

Build takes ~40s. Output confirms alias: `Aliased: https://dash.thegoodcompanysg.dev`.

## Post-Deploy Checks

```bash
curl -s -o /dev/null -w "login: %{http_code}\n" https://dash.thegoodcompanysg.dev/login
# expect 200
curl -s -o /dev/null -w "root: %{http_code}\n" https://dash.thegoodcompanysg.dev/
# expect 307 (auth redirect)
```

## Supabase Redirect URL — Required Manual Step

`SITE_URL` controls what the app *sends* as `redirectTo` in invite emails. Supabase will only honor it if the URL is allowlisted. **Without this step, invite links resolve to Supabase's fallback Site URL, not the dashboard.**

In [Supabase Dashboard](https://supabase.com/dashboard) → project `zgikcbsxzjgbigywxbbj` → **Authentication → URL Configuration**:

1. **Site URL**: `https://dash.thegoodcompanysg.dev`
2. **Redirect URLs**: add `https://dash.thegoodcompanysg.dev/**`

This is a one-time dashboard-only setting (no CLI/MCP tool available).

## Common Mistakes

- **Deploying from root** instead of `web/` — Vercel picks up the wrong project.
- **Missing `SUPABASE_SERVICE_ROLE_KEY`** — invite and remove user actions silently 500.
- **Setting `SITE_URL` but skipping Supabase allowlist** — invite links still go to the wrong domain.
