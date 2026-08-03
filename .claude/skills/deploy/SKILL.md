---
name: deploy
description: Use when deploying the TAVA web dashboard to production at dash.thegoodcompanysg.dev — covers security gates, Vercel environment checks, production deploy, rollback, and post-deploy verification.
---

# TAVA Web Deploy

Deploys `web/` to the `tava-dashboard` Vercel project, aliased to
`https://dash.thegoodcompanysg.dev`. Run Vercel commands from `web/`; its
`.vercel/project.json` is the project binding.

## Required production environment

Confirm the names exist with `cd web && vercel env ls production`. Never print
values or put a secret literal in a shell command.

| Variable | Exposure | Purpose |
|---|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | public | Exact Supabase project origin; also shapes CSP |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | public | Browser Supabase client |
| `SUPABASE_SERVICE_ROLE_KEY` | server secret | Invite/remove and trusted Storage workflows |
| `SITE_URL` | server config | Must be `https://dash.thegoodcompanysg.dev` for invite redirects |

Add a missing value interactively with `vercel env add VAR_NAME production`.
Do not use `printf 'secret' | ...`: the literal may be retained in shell history
or captured in an operator transcript. `SUPERADMIN_EMAIL` is obsolete;
migration 038 moved that authority to the single DB-managed
`security_principals(capability='superadmin')` row.

## Mandatory pre-deploy gates

1. Start from a reviewed commit on protected `main`; do not give production
   credentials to an unreviewed branch.
2. Confirm GitHub `CI` and `Remote security checks` are green for that commit.
   The remote workflow compares production to a clean migration replay and runs
   `scripts/prod-security-check.sql`.
3. From the repo root, independently run the read-only schema reference gate:

   ```bash
   scripts/drift-check.sh
   psql "$TAVA_DB_URL" -v ON_ERROR_STOP=1 -f scripts/prod-security-check.sql
   ```

   `TAVA_DB_URL` is a secret. Do not add it to a command line, commit it, or
   retain it in a transcript.
4. From `web/`:

   ```bash
   bun install --frozen-lockfile
   bun audit --audit-level=high
   bun run test
   bun run lint
   bun run build
   ```

If a gate fails, stop. Apply any required migration and re-run the production
checks before deploying app code that depends on it.

## Deploy and record

```bash
cd web
vercel deploy --prod --yes
```

Record the immutable deployment URL and source commit. Do not rely only on the
custom alias when identifying a rollback target.

## Post-deploy verification

```bash
curl --fail --silent --show-error --output /dev/null \
  --write-out 'login: %{http_code}\n' \
  https://dash.thegoodcompanysg.dev/login
curl --silent --show-error --output /dev/null \
  --write-out 'root: %{http_code} redirect=%{redirect_url}\n' \
  https://dash.thegoodcompanysg.dev/
curl --fail --silent --show-error --dump-header - --output /dev/null \
  https://dash.thegoodcompanysg.dev/login
```

Verify:

- `/login` is 200 and `/` redirects an unauthenticated request to `/login`;
- CSP contains the exact configured Supabase HTTPS/WSS origins, not a wildcard;
- HSTS, frame denial, `nosniff`, referrer, permissions and COOP headers exist;
- an admin can sign in and load the dashboard;
- a non-admin cannot enter the admin layout;
- `/privacy` remains public;
- invite links return to the production origin.

Supabase Auth must separately allowlist:

- Site URL: `https://dash.thegoodcompanysg.dev`
- Redirect URL: `https://dash.thegoodcompanysg.dev/**`

## Rollback

Use the Vercel dashboard or CLI to promote the last known-good immutable
deployment. A web rollback does not roll back database state. Never run a down
migration merely to match a rolled-back web build; first determine whether the
schema change is backward-compatible and follow `tava-change-control`.

## Failure rules

- A missing `SUPABASE_SERVICE_ROLE_KEY` is a hard configuration failure for
  privileged server actions.
- Never bypass the production drift/security gates because the login page is
  healthy; it does not exercise protected data paths.
- Never paste environment values, database URLs, auth tokens, or response
  cookies into an issue, chat, build log, or runbook.

## Provenance

Audited 2026-07-26 against `web/`, `.github/workflows/ci.yml`,
`.github/workflows/remote-security.yml`, `scripts/drift-check.sh`, and
`scripts/prod-security-check.sql`. Live production state must still be measured
at deploy time.
